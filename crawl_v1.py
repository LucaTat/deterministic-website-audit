from __future__ import annotations

from collections import deque
import os
import re
from urllib.parse import urljoin, urlparse, urlunparse
import xml.etree.ElementTree as ET

import requests
from bs4 import BeautifulSoup

HEADERS = {"User-Agent": "Mozilla/5.0"}

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


def _fetch(url: str) -> tuple[int | None, str, str, dict]:
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        return resp.status_code, resp.text or "", resp.url or url, dict(resp.headers or {})
    except Exception:
        return None, "", url, {}


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


def _discover_urls_with_sources(site_root: str) -> tuple[list[str], dict]:
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

    robots_url = urljoin(base + "/", "robots.txt") if base else ""
    sources["robots"]["url"] = robots_url
    declared_sitemaps: list[str] = []
    if robots_url:
        status, body, _, _ = _fetch(robots_url)
        sources["robots"]["status"] = status
        if status == 200 and body:
            declared_sitemaps = _parse_robots_sitemaps(body)

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
        status, body, _, _ = _fetch(sm_url)
        sources["sitemaps"]["fetched"].append({"url": sm_url, "status": status})
        if status != 200 or not body:
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
        status, html, final_url, headers = _fetch(current)
        sources["bfs"]["fetched_pages"] += 1
        if not html or status is None:
            continue
        content_type = (headers.get("Content-Type") or headers.get("content-type") or "").lower()
        if content_type and "text/html" not in content_type:
            continue
        soup = BeautifulSoup(html, "html.parser")
        for a in soup.find_all("a"):
            if len(discovered) >= HARD_CAP_DISCOVERED:
                break
            href = a.get("href")
            normalized = _normalize_url(href, final_url or current)
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

    return discovered, sources


def discover_urls(site_root: str) -> list[str]:
    urls, _ = _discover_urls_with_sources(site_root)
    return urls


def select_urls(discovered_urls: list[str], max_pages: int, caps: dict | None = None) -> list[str]:
    caps = caps or {}
    hard_cap_analyzed = int(caps.get("hard_cap_analyzed", HARD_CAP_ANALYZED))
    max_pages = int(max_pages or TARGET_ANALYZED)
    filtered = [u for u in discovered_urls if "/cdn-cgi/" not in u]
    if len(filtered) <= hard_cap_analyzed:
        return filtered[:hard_cap_analyzed]
    max_pages = min(max_pages, hard_cap_analyzed)
    if not filtered:
        return []
    selected = [filtered[0]]
    for url in filtered[1:]:
        if len(selected) >= max_pages:
            break
        selected.append(url)
    return selected


def fetch_pages(urls: list[str]) -> list[dict]:
    pages: list[dict] = []
    for url in urls:
        if "/cdn-cgi/" in url:
            continue
        status = None
        html = ""
        try:
            resp = requests.get(url, headers=HEADERS, timeout=15)
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
            html = resp.text or ""
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
    if page.get("error") == "non_html":
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
                href = el.get("href")
                if href:
                    href_candidates.append(href)
            for attr in ("data-href", "data-url", "data-link"):
                val = el.get(attr)
                if val:
                    data_candidates.append(val)
            onclick = el.get("onclick")
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

    discovered_urls, sources = _discover_urls_with_sources(site_root)
    used_playwright = False
    playwright_reason = ""
    fallback_triggered = False
    fallback_threshold = 5

    analyzed_urls = select_urls(
        discovered_urls,
        max_pages=max_pages,
        caps={"hard_cap_analyzed": HARD_CAP_ANALYZED},
    )
    pages = fetch_pages(analyzed_urls)
    analyzed_html_count = _count_analyzed_html(pages)

    if mode == "extended" and analyzed_html_count < fallback_threshold and site_root:
        fallback_triggered = True
        extra_urls, error = _playwright_discover_urls(site_root, max_urls=50)
        sources["playwright"]["used"] = not bool(error)
        sources["playwright"]["error"] = error or ""
        if error:
            used_playwright = False
            playwright_reason = error
        else:
            used_playwright = True
            already = set(discovered_urls)
            new_candidates = [u for u in extra_urls if u not in already]
            new_candidates = sorted(new_candidates)
            added = 0
            for url in new_candidates:
                if len(discovered_urls) >= HARD_CAP_DISCOVERED:
                    break
                discovered_urls.append(url)
                already.add(url)
                added += 1
            sources["playwright"]["urls_added"] = added
            analyzed_urls = select_urls(
                discovered_urls,
                max_pages=max_pages,
                caps={"hard_cap_analyzed": HARD_CAP_ANALYZED},
            )
            existing_urls = {p.get("url") for p in pages if isinstance(p, dict)}
            additional_urls = [u for u in analyzed_urls if u not in existing_urls]
            if additional_urls:
                additional_pages = fetch_pages(additional_urls)
                pages = _merge_pages(pages, additional_pages)
            analyzed_html_count = _count_analyzed_html(pages)

    return {
        "analysis_mode": mode,
        "discovered_count": len(discovered_urls),
        "discovered_urls": discovered_urls,
        "analyzed_count": analyzed_html_count,
        "pages": pages,
        "sources": sources,
        "used_playwright": used_playwright,
        "playwright_reason": playwright_reason or None,
        "fallback_triggered": fallback_triggered,
        "fallback_threshold": fallback_threshold,
    }
