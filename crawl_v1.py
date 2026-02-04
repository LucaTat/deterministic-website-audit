from __future__ import annotations

from collections import deque
import json
import os
import re
from urllib.parse import urljoin, urlparse, urlunparse

import requests
from bs4 import BeautifulSoup

from net_guardrails import (
    DEFAULT_HEADERS,
    DEFAULT_TIMEOUT,
    MAX_HTML_BYTES,
    MAX_REDIRECTS,
    ignore_robots,
    parse_robots,
    read_limited_text,
    redact_headers,
    robots_disallows,
    validate_url,
)
from safe_fetch import safe_session
import signal_detector

try:
    from defusedxml import ElementTree as ET
except ImportError:
    import xml.etree.ElementTree as ET # Fallback if defusedxml is missing

HEADERS = DEFAULT_HEADERS

HARD_CAP_DISCOVERED = 2000
HARD_CAP_ANALYZED = 500
TARGET_ANALYZED = 25

HTML_EXTENSIONS = {"", ".html", ".htm", ".php", ".asp", ".aspx", ".jsp"}
ASSET_EXTENSIONS = {
    ".jpg", ".jpeg", ".png", ".gif", ".webp", ".svg", ".ico",
    ".css", ".js", ".mjs", ".map",
    ".pdf", ".zip", ".rar", ".7z", ".gz",
    ".mp4", ".mp3", ".wav", ".avi", ".mov", ".wmv", ".webm",
    ".woff", ".woff2", ".ttf", ".otf", ".eot",
    ".xml", ".json", ".txt", ".csv",
    ".doc", ".docx", ".xls", ".xlsx", ".ppt", ".pptx",
    ".apk", ".exe", ".dmg", ".pkg",
}


def _site_root(url: str) -> str:
    parsed = urlparse(url)
    if not parsed.scheme or not parsed.netloc:
        return ""
    return f"{parsed.scheme}://{parsed.netloc}"


def _normalize_url(url: str, base_url: str) -> str:
    if not url:
        return ""
    joined = urljoin(base_url, url)
    parsed = urlparse(joined)
    if parsed.scheme not in ("http", "https"):
        return ""
    netloc = (parsed.netloc or "").lower()
    if not netloc:
        return ""
    if netloc.endswith(":80") and parsed.scheme == "http":
        netloc = netloc[:-3]
    if netloc.endswith(":443") and parsed.scheme == "https":
        netloc = netloc[:-4]
    path = parsed.path or "/"
    return urlunparse((parsed.scheme, netloc, path, "", parsed.query, ""))


def _host_key(value: str) -> str:
    host = (value or "").lower()
    if host.startswith("www."):
        host = host[4:]
    return host


def _same_host(url: str, site_root: str) -> bool:
    if not url or not site_root:
        return False
    return _host_key(urlparse(url).netloc) == _host_key(urlparse(site_root).netloc)


def _is_html_candidate(url: str) -> bool:
    path = (urlparse(url).path or "").lower()
    ext = os.path.splitext(path)[1]
    if ext in ASSET_EXTENSIONS:
        return False
    if ext in HTML_EXTENSIONS:
        return True
    return ext == ""


def _extract_title_snippets(html: str, max_snippets: int = 3, max_len: int = 200) -> tuple[str, list[str]]:
    soup = BeautifulSoup(html or "", "html.parser")
    title = ""
    if soup.title and soup.title.string:
        title = soup.title.string.strip()
    text = soup.get_text(" ", strip=True)
    text = re.sub(r"\s+", " ", text).strip()
    if not text:
        return title, []
    parts = re.split(r"(?<=[.!?])\s+", text)
    snippets: list[str] = []
    for part in parts:
        clean = (part or "").strip()
        if not clean:
            continue
        snippets.append(clean[:max_len])
        if len(snippets) >= max_snippets:
            break
    if not snippets:
        snippets = [text[:max_len]]
    return title, snippets


def _attr_to_str(value: object) -> str | None:
    if isinstance(value, str):
        return value
    return None


def _select_evidence_urls(homepage: str, discovered_urls: list[str], max_extra: int = 4) -> list[str]:
    keywords = ("contact", "contacteaza", "programare", "oferta", "solicita", "booking", "appointment", "rezerv")
    base = _site_root(homepage)
    seen: set[str] = set()
    chosen: list[str] = []

    def eligible(url: str) -> bool:
        if not url or url == homepage:
            return False
        if url in seen:
            return False
        if not _same_host(url, base):
            return False
        if not _is_html_candidate(url):
            return False
        return True

    for url in discovered_urls:
        if len(chosen) >= max_extra:
            break
        if not eligible(url):
            continue
            
        # Use robust signal detection
        signals = signal_detector.detect_url_signals(url)
        if signals.get("found_any"):
            chosen.append(url)
            seen.add(url)

    if len(chosen) < max_extra:
        for url in discovered_urls:
            if len(chosen) >= max_extra:
                break
            if not eligible(url):
                continue
            chosen.append(url)
            seen.add(url)

    return chosen


def _save_evidence_pages(evidence_dir: str, homepage: str, extra_urls: list[str]) -> None:
    os.makedirs(evidence_dir, exist_ok=True)
    pages_meta: list[dict] = []

    def write_page(url: str, filename: str) -> None:
        html = ""
        if url:
            status, body, _, headers, error = _fetch(url, max_bytes=MAX_HTML_BYTES)
            content_type = (headers.get("Content-Type") or headers.get("content-type") or "").lower()
            if not error and status is not None and "text/html" in content_type:
                html = body or ""
        out_path = os.path.join(evidence_dir, filename)
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(html or "")
        pages_meta.append({"url": url, "file": filename})

    write_page(homepage, "home.html")
    
    # NEW: Capture visual evidence (Screenshot) for the homepage
    # NEW: Capture visual evidence (Desktop & Mobile)
    # NEW: Capture visual evidence (Desktop & Mobile) using persistent browser
    try:
        from pathlib import Path
        from visual_check import VisualVerifier
        
        with VisualVerifier() as vv:
            # Desktop
            desktop_path = os.path.join(evidence_dir, "home.png")
            desktop_res = vv.capture(homepage, Path(desktop_path), device_type="desktop")
            
            # Mobile
            mobile_path = os.path.join(evidence_dir, "home_mobile.png")
            mobile_res = vv.capture(homepage, Path(mobile_path), device_type="mobile")
            
            # Record Desktop file
            if desktop_res.get("ok"):
                 pages_meta.append({
                     "url": homepage, 
                     "file": "home.png", 
                     "type": "screenshot",
                     "device": "desktop",
                     "metrics": desktop_res.get("metrics")
                 })

            # Record Mobile file
            if mobile_res.get("ok"):
                 pages_meta.append({
                     "url": homepage, 
                     "file": "home_mobile.png", 
                     "type": "screenshot",
                     "device": "mobile",
                     "metrics": mobile_res.get("metrics")
                 })

            # Save Performance Metrics separately for easy parsing
            perf_data = {
                "desktop": desktop_res.get("metrics") if desktop_res.get("ok") else {},
                "mobile": mobile_res.get("metrics") if mobile_res.get("ok") else {},
            }
            with open(os.path.join(evidence_dir, "performance.json"), "w", encoding="utf-8") as f:
                json.dump(perf_data, f, indent=2)

    except Exception as e:
        print(f"Visual check error: {e}") 
        pass

    for idx, url in enumerate(extra_urls[:4], start=1):
        write_page(url, f"page_{idx:02d}.html")

    pages_path = os.path.join(evidence_dir, "pages.json")
    with open(pages_path, "w", encoding="utf-8") as f:
        json.dump(pages_meta, f, ensure_ascii=False, indent=2)


def _fetch(url: str, max_bytes: int | None = MAX_HTML_BYTES) -> tuple[int | None, str, str, dict, str | None]:
    try:
        validate_url(url)
    except ValueError:
        return None, "", url, {}, "invalid_url"

    session = safe_session()
    session.max_redirects = MAX_REDIRECTS
    session.trust_env = False

    current_url = url
    redirects = 0
    while True:
        try:
            resp = session.get(
                current_url,
                headers=HEADERS,
                timeout=DEFAULT_TIMEOUT,
                stream=True,
                allow_redirects=False,
            )
        except requests.TooManyRedirects:
            return None, "", current_url, {}, "too_many_redirects"
        except ValueError:
            return None, "", current_url, {}, "invalid_url"
        except requests.exceptions.RequestException:
            return None, "", current_url, {}, "fetch_error"
        except Exception:
            return None, "", current_url, {}, "fetch_error"

        status = resp.status_code
        if status in (301, 302, 303, 307, 308):
            location = (resp.headers or {}).get("Location")
            if not location:
                return None, "", current_url, redact_headers(resp.headers or {}), "fetch_error"
            redirects += 1
            if redirects > MAX_REDIRECTS:
                return None, "", current_url, {}, "too_many_redirects"
            next_url = urljoin(current_url, location)
            try:
                validate_url(next_url)
            except ValueError:
                return None, "", next_url, {}, "invalid_url"
            current_url = next_url
            continue

        text, too_large = read_limited_text(resp, max_bytes)
        if too_large:
            return status, "", resp.url, redact_headers(resp.headers or {}), "too_large"
        return status, text or "", resp.url, redact_headers(resp.headers or {}), None


def _parse_robots_sitemaps(text: str) -> list[str]:
    sitemaps: list[str] = []
    for raw in (text or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        if "#" in line:
            line = line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.lower().startswith("sitemap:"):
            sm = line.split(":", 1)[1].strip()
            if sm:
                sitemaps.append(sm)
    return sitemaps


def _build_robots_policy(site_root: str) -> dict:
    robots_url = urljoin(site_root + "/", "robots.txt") if site_root else ""
    policy = {
        "url": robots_url,
        "http_status": None,
        "error": None,
        "rules": {},
        "body": "",
        "policy": "respect",
        "reason": "",
        "ignored": False,
    }
    if not robots_url:
        policy["policy"] = "allow"
        policy["reason"] = "robots_missing_base"
        return policy
    if ignore_robots():
        policy["policy"] = "ignore"
        policy["reason"] = "robots_ignored"
        policy["ignored"] = True
    status, body, _, _, error = _fetch(robots_url, max_bytes=MAX_HTML_BYTES)
    policy["http_status"] = status
    policy["error"] = error
    if policy.get("ignored"):
        policy["body"] = body or ""
        if status == 200 and body:
            policy["rules"] = parse_robots(body)
        return policy
    if status == 200 and body:
        policy["body"] = body
        policy["rules"] = parse_robots(body)
    policy["policy"] = "allow"
    policy["reason"] = "robots_unreachable_allow"
    return policy


def _robots_allows(url: str, policy: dict) -> tuple[bool, str | None]:
    if policy.get("ignored"):
        return True, None
    if policy.get("policy") == "allow" and policy.get("reason") == "robots_unreachable_allow":
        return True, None
    rules = policy.get("rules") or {}
    disallowed, rule = robots_disallows(url, rules)
    if disallowed:
        return False, rule
    return True, None


def _parse_sitemap_xml(body: str) -> tuple[list[str], str]:
    root = ET.fromstring(body)
    tag = root.tag.lower()
    kind = "urlset"
    if "sitemapindex" in tag:
        kind = "sitemapindex"
    urls: list[str] = []
    for elem in root.iter():
        if elem.tag.lower().endswith("loc") and elem.text:
            urls.append(elem.text.strip())
    return urls, kind


def _discover_urls_with_sources(site_root: str) -> tuple[list[str], dict, dict]:
    discovered: list[str] = []
    seen: set[str] = set()
    sources: dict = {
        "robots": {"url": "", "status": None},
        "sitemaps": {"declared": [], "fetched": [], "urls_added": 0},
        "bfs": {"fetched_pages": 0, "urls_added": 0},
        "playwright": {"used": False, "urls_added": 0, "error": ""},
    }

    base = _site_root(site_root) or site_root
    homepage = _normalize_url(site_root, site_root)
    if homepage and "/cdn-cgi/" not in homepage:
        discovered.append(homepage)
        seen.add(homepage)

    robots_policy = _build_robots_policy(base)
    robots_url = robots_policy.get("url") or ""
    sources["robots"]["url"] = robots_url
    sources["robots"]["status"] = robots_policy.get("http_status")
    sources["robots"]["error"] = robots_policy.get("error")
    sources["robots"]["policy"] = robots_policy.get("policy")
    if robots_policy.get("reason"):
        sources["robots"]["reason"] = robots_policy.get("reason")
    declared_sitemaps: list[str] = []
    if robots_policy.get("http_status") == 200 and robots_policy.get("body"):
        declared_sitemaps = _parse_robots_sitemaps(robots_policy.get("body") or "")

    if not declared_sitemaps and base:
        declared_sitemaps = [
            urljoin(base + "/", "sitemap.xml"),
            urljoin(base + "/", "sitemap_index.xml"),
        ]

    sources["sitemaps"]["declared"] = declared_sitemaps[:]

    sitemap_queue = deque(declared_sitemaps)
    fetched_sitemaps: set[str] = set()
    while sitemap_queue and len(discovered) < HARD_CAP_DISCOVERED:
        sm_url_raw = sitemap_queue.popleft()
        sm_url = _normalize_url(sm_url_raw, base) if base else _normalize_url(sm_url_raw, sm_url_raw)
        if not sm_url or sm_url in fetched_sitemaps:
            continue
        fetched_sitemaps.add(sm_url)
        status, body, _, _, error = _fetch(sm_url)
        sources["sitemaps"]["fetched"].append({"url": sm_url, "status": status})
        if error or status != 200 or not body:
            continue
        try:
            urls, kind = _parse_sitemap_xml(body)
        except Exception:
            continue
        if kind == "sitemapindex":
            for child in urls:
                if len(discovered) >= HARD_CAP_DISCOVERED:
                    break
                sitemap_queue.append(child)
            continue
        for loc in urls:
            if len(discovered) >= HARD_CAP_DISCOVERED:
                break
            normalized = _normalize_url(loc, base or loc)
            if not normalized:
                continue
            if not _same_host(normalized, base):
                continue
            if "/cdn-cgi/" in normalized:
                continue
            if not _is_html_candidate(normalized):
                continue
            if normalized in seen:
                continue
            discovered.append(normalized)
            seen.add(normalized)
            sources["sitemaps"]["urls_added"] += 1

    queue = deque([homepage]) if homepage else deque()
    while queue and len(discovered) < HARD_CAP_DISCOVERED:
        current = queue.popleft()
        allowed, _ = _robots_allows(current, robots_policy)
        if not allowed:
            continue
        status, html, final_url, headers, error = _fetch(current, max_bytes=MAX_HTML_BYTES)
        sources["bfs"]["fetched_pages"] += 1
        if error or not html or status is None:
            continue
        content_type = (headers.get("Content-Type") or headers.get("content-type") or "").lower()
        if content_type and "text/html" not in content_type:
            continue
        soup = BeautifulSoup(html, "html.parser")
        for a in soup.find_all("a"):
            if len(discovered) >= HARD_CAP_DISCOVERED:
                break
            href = _attr_to_str(a.get("href"))
            normalized = _normalize_url(href or "", final_url or current)
            if not normalized:
                continue
            if not _same_host(normalized, base):
                continue
            if "/cdn-cgi/" in normalized:
                continue
            if not _is_html_candidate(normalized):
                continue
            if normalized in seen:
                continue
            discovered.append(normalized)
            seen.add(normalized)
            queue.append(normalized)
            sources["bfs"]["urls_added"] += 1

    return discovered, sources, robots_policy


def discover_urls(site_root: str) -> list[str]:
    urls, _, _ = _discover_urls_with_sources(site_root)
    return urls


def select_urls(
    discovered_urls: list[str],
    max_pages: int,
    caps: dict | None = None,
    site_root: str | None = None,
) -> list[str]:
    caps = caps or {}
    hard_cap_analyzed = int(caps.get("hard_cap_analyzed", HARD_CAP_ANALYZED))
    max_pages = int(max_pages or TARGET_ANALYZED)
    max_pages = min(max_pages, hard_cap_analyzed)
    if max_pages <= 0:
        return []

    def is_analyzable(url: str) -> bool:
        if not url or "/cdn-cgi/" in url:
            return False
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https"):
            return False
        if not parsed.netloc:
            return False
        if parsed.fragment:
            return False
        if not _is_html_candidate(url):
            return False
        return True

    def canonical_homepage(value: str | None) -> str:
        if not value:
            return ""
        parsed = urlparse(value)
        if parsed.scheme not in ("http", "https"):
            return ""
        if not parsed.netloc:
            return ""
        return f"{parsed.scheme}://{parsed.netloc}/"

    def canonicalize_for_dedupe(url: str) -> str:
        parsed = urlparse(url)
        scheme = (parsed.scheme or "").lower()
        host = (parsed.netloc or "").lower()
        path = parsed.path or "/"
        if path != "/":
            path = path.rstrip("/")
            if not path:
                path = "/"
        query = parsed.query or ""
        return f"{scheme}://{host}{path}?{query}"

    selected: list[str] = []
    seen_keys: set[str] = set()

    def add_url(url: str) -> None:
        if not is_analyzable(url):
            return
        key = canonicalize_for_dedupe(url)
        if key in seen_keys:
            return
        seen_keys.add(key)
        selected.append(url)

    homepage = canonical_homepage(site_root)
    if homepage:
        add_url(homepage)

    for url in discovered_urls:
        if len(selected) >= max_pages:
            break
        add_url(url)

    return selected[:max_pages]


def fetch_pages(urls: list[str], robots_policy: dict | None = None) -> list[dict]:
    pages: list[dict] = []
    robots_policy = robots_policy or {}
    for url in urls:
        if "/cdn-cgi/" in url:
            continue
        allowed, _ = _robots_allows(url, robots_policy)
        if not allowed:
            pages.append({
                "url": url,
                "status": None,
                "title": None,
                "snippets": [],
                "error": "robots_disallowed",
            })
            continue
        status = None
        html = ""
        try:
            session = safe_session()
            session.max_redirects = MAX_REDIRECTS
            req_headers = HEADERS
            # validate_url(url) - safe_session handles this
            resp = session.get(
                url,
                headers=req_headers,
                timeout=DEFAULT_TIMEOUT,
                allow_redirects=True, # safe_session pins IP for every redirect
                stream=True,
            )
            status = resp.status_code
            content_type = resp.headers.get("Content-Type", "") or ""
            if "text/html" not in content_type:
                pages.append({
                    "url": url,
                    "status": status,
                    "title": None,
                    "snippets": [],
                    "error": "non_html",
                    "content_type": content_type,
                })
                continue
            html, too_large = read_limited_text(resp, MAX_HTML_BYTES)
            if too_large:
                pages.append({
                    "url": url,
                    "status": status,
                    "title": None,
                    "snippets": [],
                    "error": "too_large",
                    "content_type": content_type,
                })
                continue
        except requests.TooManyRedirects:
            pages.append({
                "url": url,
                "status": None,
                "title": None,
                "snippets": [],
                "error": "too_many_redirects",
            })
            continue
        except ValueError: # Validation failed
            pages.append({
                "url": url,
                "status": None,
                "title": None,
                "snippets": [],
                "error": "invalid_url",
            })
            continue
        except Exception:
            html = ""
        title, snippets = _extract_title_snippets(html)
        pages.append({
            "url": url,
            "status": status,
            "title": title,
            "snippets": snippets,
        })
    return pages


def _is_html_page(page: dict) -> bool:
    if not isinstance(page, dict):
        return False
    if page.get("error"):
        return False
    content_type = str(page.get("content_type") or "").lower()
    if content_type and "text/html" not in content_type:
        return False
    return True


def _count_analyzed_html(pages: list[dict]) -> int:
    return sum(1 for page in pages if _is_html_page(page))


def _extract_onclick_urls(onclick: str) -> list[str]:
    if not onclick:
        return []
    pattern = re.compile(
        r"(?:location\\.href|window\\.location|document\\.location)\\s*=\\s*['\\\"]([^'\\\"]+)['\\\"]"
    )
    return [m.group(1) for m in pattern.finditer(onclick)]


def _playwright_discover_urls(start_url: str, max_urls: int = 50) -> tuple[list[str], str | None]:
    try:
        from playwright.sync_api import sync_playwright  # type: ignore
    except Exception as exc:
        return [], str(exc)

    base = urlparse(start_url)
    if not base.scheme or not base.netloc:
        return [], "invalid_start_url"

    hrefs: list[str] = []
    error: str | None = None
    browser = None
    context = None
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            context = browser.new_context()
            page = context.new_page()
            page.goto(start_url, wait_until="networkidle", timeout=10000)
            page.wait_for_timeout(1000)
            selectors = ["nav a[href]", "header a[href]", "footer a[href]", "main a[href]"]
            for selector in selectors:
                items = page.eval_on_selector_all(
                    selector,
                    "els => els.map(e => e.getAttribute('href')).filter(Boolean)",
                )
                if isinstance(items, list):
                    hrefs.extend([str(item) for item in items if item])
    except Exception as exc:
        error = str(exc)
    finally:
        try:
            if context is not None:
                context.close()
        except Exception:
            pass
        try:
            if browser is not None:
                browser.close()
        except Exception:
            pass

    if error:
        return [], error

    filtered: list[str] = []
    seen: set[str] = set()
    for raw in hrefs:
        normalized = _normalize_url(raw, start_url)
        if not normalized:
            continue
        parsed = urlparse(normalized)
        if parsed.scheme != base.scheme or parsed.netloc != base.netloc:
            continue
        if not _is_html_candidate(normalized):
            continue
        if normalized in seen:
            continue
        seen.add(normalized)
        filtered.append(normalized)

    filtered = sorted(filtered)
    return filtered[:max_urls], None


def _playwright_discover(homepage_url: str) -> tuple[list[str], dict, str]:
    try:
        from playwright.sync_api import sync_playwright  # type: ignore
    except Exception as exc:
        return [], {"from_href": 0, "from_data": 0, "from_onclick": 0, "from_network": 0}, str(exc)

    urls: list[str] = []
    error = ""
    counts = {"from_href": 0, "from_data": 0, "from_onclick": 0, "from_network": 0}
    href_candidates: list[str] = []
    data_candidates: list[str] = []
    onclick_candidates: list[str] = []
    network_candidates: list[str] = []
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page()
            page.on("request", lambda req: network_candidates.append(req.url))
            page.goto(homepage_url, wait_until="domcontentloaded", timeout=8000)
            page.wait_for_timeout(1500)
            html = page.content()
            browser.close()
        soup = BeautifulSoup(html or "", "html.parser")
        for el in soup.find_all(True):
            if el.name == "a":
                href = _attr_to_str(el.get("href"))
                if href:
                    href_candidates.append(href)
            for attr in ("data-href", "data-url", "data-link"):
                val = _attr_to_str(el.get(attr))
                if val:
                    data_candidates.append(val)
            onclick = _attr_to_str(el.get("onclick"))
            if onclick:
                onclick_candidates.extend(_extract_onclick_urls(onclick))
        urls = href_candidates + data_candidates + onclick_candidates
    except Exception as exc:
        error = str(exc)

    filtered: list[str] = []
    seen: set[str] = set()
    base = _site_root(homepage_url)

    def add_urls(candidates: list[str], key: str) -> None:
        for raw in candidates:
            normalized = _normalize_url(raw, homepage_url)
            if not normalized:
                continue
            if "/cdn-cgi/" in normalized:
                continue
            if not _same_host(normalized, base):
                continue
            if not _is_html_candidate(normalized):
                continue
            if normalized in seen:
                continue
            seen.add(normalized)
            filtered.append(normalized)
            counts[key] += 1

    add_urls(href_candidates, "from_href")
    add_urls(data_candidates, "from_data")
    add_urls(onclick_candidates, "from_onclick")
    add_urls(network_candidates, "from_network")

    return filtered, counts, error


def _merge_pages(existing: list[dict], new_pages: list[dict]) -> list[dict]:
    out = list(existing)
    index: dict[str, int] = {}
    for i, page in enumerate(out):
        if isinstance(page, dict):
            url = page.get("url")
            if isinstance(url, str) and url:
                index[url] = i
    for page in new_pages:
        if not isinstance(page, dict):
            continue
        url = page.get("url")
        if not isinstance(url, str) or not url:
            continue
        if url not in index:
            index[url] = len(out)
            out.append(page)
            continue
        current = out[index[url]]
        if _is_html_page(current):
            continue
        if _is_html_page(page):
            out[index[url]] = page
    return out


def crawl_site(site_root: str, max_pages: int = TARGET_ANALYZED, analysis_mode: str = "standard") -> dict:
    mode = (analysis_mode or "standard").strip().lower()
    if mode not in ("standard", "extended"):
        mode = "standard"

    discovered_urls, sources, robots_policy = _discover_urls_with_sources(site_root)
    used_playwright = False
    playwright_attempted = False
    playwright_reason = ""
    fallback_triggered = False
    fallback_threshold = 5

    analyzed_urls = select_urls(
        discovered_urls,
        max_pages=max_pages,
        caps={"hard_cap_analyzed": HARD_CAP_ANALYZED},
        site_root=site_root,
    )
    pages = fetch_pages(analyzed_urls, robots_policy=robots_policy)
    analyzed_html_count = _count_analyzed_html(pages)

    if mode == "extended" and analyzed_html_count < fallback_threshold and site_root:
        fallback_triggered = True
        playwright_attempted = True
        extra_urls, counts, error = _playwright_discover(site_root)
        sources["playwright"]["used"] = not bool(error)
        sources["playwright"]["error"] = error or ""
        sources["playwright"]["from_href"] = counts.get("from_href", 0)
        sources["playwright"]["from_data"] = counts.get("from_data", 0)
        sources["playwright"]["from_onclick"] = counts.get("from_onclick", 0)
        sources["playwright"]["from_network"] = counts.get("from_network", 0)
        if error:
            used_playwright = False
            playwright_reason = error
        else:
            already = set(discovered_urls)
            sorted_candidates = sorted(extra_urls)[:50]
            new_candidates = [u for u in sorted_candidates if u not in already]
            added = 0
            for url in new_candidates:
                if len(discovered_urls) >= HARD_CAP_DISCOVERED:
                    break
                discovered_urls.append(url)
                already.add(url)
                added += 1
            if added == 0:
                html = ""
                allowed, _ = _robots_allows(site_root, robots_policy)
                if allowed:
                    status, fetched_html, _, _, error = _fetch(site_root, max_bytes=MAX_HTML_BYTES)
                    if not error and status is not None:
                        html = fetched_html or ""
                if html:
                    soup = BeautifulSoup(html, "html.parser")
                    html_hrefs: list[str] = []
                    for a in soup.find_all("a"):
                        href = _attr_to_str(a.get("href"))
                        if href:
                            html_hrefs.append(href)
                    html_candidates: list[str] = []
                    seen_html: set[str] = set()
                    base = _site_root(site_root)
                    for raw in html_hrefs:
                        normalized = _normalize_url(raw, site_root)
                        if not normalized:
                            continue
                        if not _same_host(normalized, base):
                            continue
                        if not _is_html_candidate(normalized):
                            continue
                        if normalized in seen_html:
                            continue
                        seen_html.add(normalized)
                        html_candidates.append(normalized)
                    for url in sorted(html_candidates)[:50]:
                        if url in already:
                            continue
                        if len(discovered_urls) >= HARD_CAP_DISCOVERED:
                            break
                        discovered_urls.append(url)
                        already.add(url)
                        added += 1
            sources["playwright"]["urls_added"] = added
            used_playwright = added > 0
            if not used_playwright:
                playwright_reason = "no_new_urls"
            analyzed_urls = select_urls(
                discovered_urls,
                max_pages=max_pages,
                caps={"hard_cap_analyzed": HARD_CAP_ANALYZED},
                site_root=site_root,
            )
            existing_urls = {p.get("url") for p in pages if isinstance(p, dict)}
            additional_urls = [u for u in analyzed_urls if u not in existing_urls]
            if additional_urls:
                additional_pages = fetch_pages(additional_urls)
                pages = _merge_pages(pages, additional_pages)
            analyzed_html_count = _count_analyzed_html(pages)

    evidence_dir = os.environ.get("SCOPE_EVIDENCE_DIR") or ""
    if evidence_dir:
        homepage = discovered_urls[0] if discovered_urls else _normalize_url(site_root, site_root)
        extra_urls = _select_evidence_urls(homepage, discovered_urls, max_extra=4)
        _save_evidence_pages(evidence_dir, homepage, extra_urls)

    return {
        "analysis_mode": mode,
        "discovered_count": len(discovered_urls),
        "discovered_urls": discovered_urls,
        "analyzed_count": analyzed_html_count,
        "pages": pages,
        "sources": sources,
        "robots": {
            "url": robots_policy.get("url"),
            "http_status": robots_policy.get("http_status"),
            "error": robots_policy.get("error"),
            "policy": robots_policy.get("policy"),
            "reason": robots_policy.get("reason"),
        },
        "playwright_attempted": playwright_attempted,
        "used_playwright": used_playwright,
        "playwright_reason": playwright_reason or None,
        "fallback_triggered": fallback_triggered,
        "fallback_threshold": fallback_threshold,
    }
