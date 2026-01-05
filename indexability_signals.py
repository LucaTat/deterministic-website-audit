# indexability_signals.py
from __future__ import annotations

from typing import Any
from urllib.parse import urljoin, urlparse
import xml.etree.ElementTree as ET

import requests
from bs4 import BeautifulSoup

from audit import HEADERS, BOOKING_KEYWORDS, CONTACT_KEYWORDS, normalize_text

INDEXABILITY_PACK_VERSION = "v1"

SERVICES_KEYWORDS = [
    "services", "servicii", "tuns", "vopsit",
    "manichiura", "manichiură",
    "pedichiura", "pedichiură",
    "coafat", "tratament",
    "abonament", "abonamente", "membership",
]

PRICING_KEYWORDS = [
    "lei", "ron", "€", "eur",
    "price", "pret", "preț",
    "preturi", "prețuri", "tarif", "tarife",
]


def extract_indexability_signals(url: str, html: str, signals: dict[str, Any]) -> dict[str, Any]:
    """
    Deterministic indexability & technical access signals.
    - No crawling: only homepage + important_urls + robots + sitemap URLs + sitemap sample N=20
    """
    homepage_fetch = _fetch_with_redirects(url, method="GET")
    homepage_final_url = homepage_fetch.get("final_url") or url
    homepage_html = homepage_fetch.get("text") or html or ""
    site_root = _site_root(homepage_final_url)

    important_urls, important_groups = _build_important_urls(homepage_final_url, homepage_html)

    # Per-page signals for important URLs only
    pages: dict[str, Any] = {}
    for page_url in important_urls:
        page_fetch = _fetch_with_redirects(page_url, method="GET")
        page_html = page_fetch.get("text") or ""
        meta = _extract_meta_directives(page_html)
        canonical = _extract_canonical(page_html, base_url=page_fetch.get("final_url") or page_url)

        headers = {
            "x-robots-tag": (page_fetch.get("headers", {}) or {}).get("x-robots-tag", ""),
        }

        # Canonical target fetch: only when canonical resolves to a different host/path than final URL.
        # (Conservative; avoids extra fetches.)
        if canonical.get("resolved"):
            canon_url = canonical.get("resolved")
            if canon_url and not _urls_equivalent(canon_url, page_fetch.get("final_url")):
                canonical_fetch = _fetch_with_redirects(canon_url, method="GET")
                canonical["target_fetch"] = _fetch_summary(canonical_fetch)
            else:
                canonical["target_fetch"] = None

        pages[page_url] = {
            "fetch": _fetch_summary(page_fetch),
            "headers": headers,
            "meta": meta,
            "canonical": canonical,
        }

    robots = _fetch_robots(site_root)
    sitemaps = _discover_sitemaps(site_root, robots)

    return {
        "pack_version": INDEXABILITY_PACK_VERSION,
        "site_root": site_root,
        "homepage_final_url": homepage_final_url,
        "important_urls": important_urls,
        "important_url_groups": important_groups,
        "robots": robots,
        "pages": pages,
        "sitemaps": sitemaps,
    }


def _fetch_with_redirects(url: str, method: str = "GET", max_hops: int = 8) -> dict[str, Any]:
    session = requests.Session()
    visited: list[str] = []
    redirect_chain: list[dict[str, Any]] = []
    current_url = url

    error: str | None = None
    final_status: int | None = None
    final_url: str | None = None
    text = ""
    headers: dict[str, str] = {}
    loop = False
    too_many = False

    for _ in range(max_hops + 1):
        try:
            resp = session.request(
                method,
                current_url,
                headers=HEADERS,
                timeout=15,
                allow_redirects=False,
            )
        except Exception as exc:
            error = str(exc)
            final_url = current_url
            break

        status = resp.status_code
        location = resp.headers.get("Location", "")
        if status in (301, 302, 303, 307, 308) and location:
            redirect_chain.append({"url": current_url, "status": status, "location": location})
            next_url = urljoin(current_url, location)
            if next_url in visited:
                loop = True
                final_url = next_url
                final_status = status
                break
            visited.append(next_url)
            current_url = next_url
            if len(redirect_chain) > max_hops - 1:
                too_many = True
                final_url = next_url
                final_status = status
                break
            continue

        final_status = status
        final_url = current_url
        headers = {k.lower(): v for k, v in resp.headers.items()}
        if method.upper() == "GET":
            try:
                text = resp.text
            except Exception:
                text = ""
        break

    return {
        "requested_url": url,
        "final_url": final_url or url,
        "final_status": final_status,
        "redirect_chain": redirect_chain,
        "error": error,
        "loop": loop,
        "too_many": too_many,
        "text": text,
        "headers": headers,
    }


def _fetch_summary(fetch: dict[str, Any], requested: str | None = None) -> dict[str, Any]:
    return {
        "requested_url": requested or fetch.get("requested_url"),
        "final_url": fetch.get("final_url"),
        "final_status": fetch.get("final_status"),
        "redirect_chain": fetch.get("redirect_chain") or [],
        "error": fetch.get("error"),
        "loop": bool(fetch.get("loop")),
        "too_many": bool(fetch.get("too_many")),
    }


def _site_root(url: str) -> str:
    parsed = urlparse(url)
    scheme = parsed.scheme or "https"
    netloc = parsed.netloc or parsed.path
    return f"{scheme}://{netloc}".rstrip("/")


def _build_important_urls(homepage_url: str, html: str) -> tuple[list[str], dict[str, list[str]]]:
    soup = BeautifulSoup(html or "", "html.parser")
    links: list[dict[str, Any]] = []
    order = 0
    for a in soup.find_all("a"):
        href = str(a.get("href") or "").strip()
        if not href or href.startswith("#"):
            continue
        if href.startswith(("mailto:", "tel:", "javascript:")):
            continue
        text = normalize_text(a.get_text(" ", strip=True))
        abs_url = urljoin(homepage_url, href)
        links.append({
            "href": abs_url.split("#", 1)[0],
            "text": text,
            "order": order,
        })
        order += 1

    def is_internal(link: str) -> bool:
        return urlparse(link).netloc == urlparse(homepage_url).netloc

    internal_links = [l for l in links if is_internal(l["href"])]

    booking = _pick_first_keyword_links(internal_links, BOOKING_KEYWORDS)
    contact = _pick_first_keyword_links(internal_links, CONTACT_KEYWORDS)
    pricing = _pick_first_keyword_links(internal_links, PRICING_KEYWORDS)
    services = _pick_service_links(internal_links, max_items=5)

    ordered: list[str] = []
    seen: set[str] = set()
    for u in [homepage_url] + booking + contact + services + pricing:
        if not u or u in seen:
            continue
        seen.add(u)
        ordered.append(u)

    groups = {
        "homepage": [homepage_url],
        "booking": booking,
        "contact": contact,
        "services": services,
        "pricing": pricing,
    }

    return ordered or [homepage_url], groups


def _pick_first_keyword_links(links: list[dict[str, Any]], keywords: list[str]) -> list[str]:
    for item in links:
        text = item.get("text") or ""
        href = (item.get("href") or "").lower()
        haystack = f"{text} {href}"
        if any(k in haystack for k in keywords):
            return [item["href"]]
    return []


def _pick_service_links(links: list[dict[str, Any]], max_items: int = 5) -> list[str]:
    candidates: list[tuple[int, int, str]] = []
    for item in links:
        text = item.get("text") or ""
        href = (item.get("href") or "").lower()
        if any(k in text for k in SERVICES_KEYWORDS) or any(k in href for k in SERVICES_KEYWORDS):
            parsed = urlparse(item["href"])
            depth = len([p for p in parsed.path.split("/") if p])
            candidates.append((depth, int(item.get("order", 0) or 0), item["href"]))

    candidates.sort(key=lambda x: (x[0], x[1]))
    out: list[str] = []
    seen: set[str] = set()
    for _, _, href in candidates:
        if href in seen:
            continue
        seen.add(href)
        out.append(href)
        if len(out) >= max_items:
            break
    return out


def _extract_meta_directives(html: str) -> dict[str, Any]:
    soup = BeautifulSoup(html or "", "html.parser")
    meta: dict[str, list[dict[str, Any]]] = {"robots": [], "googlebot": []}
    for tag in soup.find_all("meta"):
        name = str(tag.get("name") or "").strip().lower()
        if name in ("robots", "googlebot"):
            content = str(tag.get("content") or "").strip()
            meta[name].append({
                "content": content,
                "snippet": str(tag)[:300],
                "attrs": dict(tag.attrs),
            })
    return meta


def _extract_canonical(html: str, base_url: str) -> dict[str, Any]:
    soup = BeautifulSoup(html or "", "html.parser")
    tags: list[dict[str, Any]] = []
    for tag in soup.find_all("link"):
        rel = tag.get("rel") or []
        rel_vals = [r.lower() for r in rel] if isinstance(rel, list) else [str(rel).lower()]
        if "canonical" in rel_vals:
            href = str(tag.get("href") or "").strip()
            tags.append({
                "href": href,
                "resolved": urljoin(base_url, href) if href else "",
                "snippet": str(tag)[:300],
            })
    return {
        "found_count": len(tags),
        "tags": tags,
        "href": tags[0]["href"] if tags else "",
        "resolved": tags[0]["resolved"] if tags else "",
        "target_fetch": None,
    }


def _fetch_robots(site_root: str) -> dict[str, Any]:
    """
    Fetch robots.txt deterministically.
    IMPORTANT: do not invent status codes. status is only set from the HTTP response.
    """
    robots_url = urljoin(site_root + "/", "robots.txt")
    text = ""
    status: int | None = None
    error: str | None = None

    try:
        resp = requests.get(robots_url, headers=HEADERS, timeout=15)
        status = resp.status_code
        try:
            text = resp.text or ""
        except Exception:
            text = ""
    except Exception as exc:
        error = str(exc)

    ua_rules: dict[str, list[str]] = {}
    sitemaps: list[str] = []
    if status == 200 and text:
        ua_rules, sitemaps = _parse_robots(text)

    if status is None and error is None:
        error = "robots_fetch_failed_unknown"

    return {
        "url": robots_url,
        "http_status": status,
        "error": error,
        "body_snippet": (text[:800] if text else None),
        "ua_rules": ua_rules,
        "rules_summary": ua_rules,
        "sitemaps": sitemaps,
    }


def _parse_robots(text: str) -> tuple[dict[str, list[str]], list[str]]:
    ua_rules: dict[str, list[str]] = {}
    sitemaps: list[str] = []
    current_uas: list[str] = []

    for raw in (text or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        if "#" in line:
            line = line.split("#", 1)[0].strip()
        if not line:
            continue

        lower = line.lower()
        if lower.startswith("user-agent:"):
            ua = line.split(":", 1)[1].strip().lower()
            current_uas = [ua]
            ua_rules.setdefault(ua, [])
            continue

        if lower.startswith("disallow:"):
            rule = line.split(":", 1)[1].strip()
            if not current_uas:
                current_uas = ["*"]
            for ua in current_uas:
                ua_rules.setdefault(ua, []).append(rule)
            continue

        if lower.startswith("sitemap:"):
            sm = line.split(":", 1)[1].strip()
            if sm:
                sitemaps.append(sm)

    return ua_rules, sitemaps


def _discover_sitemaps(site_root: str, robots: dict[str, Any]) -> dict[str, Any]:
    declared = robots.get("sitemaps") or []
    probes = [
        urljoin(site_root + "/", "sitemap.xml"),
        urljoin(site_root + "/", "sitemap_index.xml"),
    ]

    probed_results: list[dict[str, Any]] = []
    fetched: dict[str, Any] = {}

    # Fetch declared sitemap URLs first (in robots order)
    for sm_url in declared:
        if sm_url in fetched:
            continue
        status, error, body = _fetch_url(sm_url)
        fetched[sm_url] = _parse_sitemap_fetch(status, error, body)

    # Fetch probes (always)
    for probe in probes:
        status, error, body = _fetch_url(probe)
        probed_results.append({"url": probe, "status": status, "error": error})
        fetched[probe] = _parse_sitemap_fetch(status, error, body)

    # Deterministic sample (first-N in doc order)
    sample = _sample_sitemap_urls(fetched, max_urls=20)

    discovered_urls = list(dict.fromkeys(declared + probes))

    return {
        "declared": declared,
        "probed": probed_results,
        "fetched": fetched,
        "discovered_urls": discovered_urls,
        "sample": sample,
        "robots_snippet": robots.get("body_snippet") or "",
    }


def _fetch_url(url: str) -> tuple[int | None, str | None, str]:
    try:
        resp = requests.get(url, headers=HEADERS, timeout=15)
        return resp.status_code, None, resp.text or ""
    except Exception as exc:
        return None, str(exc), ""


def _parse_sitemap_fetch(status: int | None, error: str | None, body: str) -> dict[str, Any]:
    entry = {
        "status": status,
        "error": error,
        "body_snippet": (body[:800] if body else None),
        "parse_error": None,
        "urls": [],
        "kind": "",
    }
    if status != 200 or error:
        return entry
    try:
        urls, kind = _parse_sitemap_xml(body)
        entry["urls"] = urls
        entry["kind"] = kind
    except Exception as exc:
        entry["parse_error"] = str(exc)
    return entry


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


def _sample_sitemap_urls(fetched: dict[str, Any], max_urls: int = 20) -> dict[str, Any]:
    """
    Deterministic sampling strategy:
    - first-N URLs in document order across fetched sitemaps
    - expands sitemapindex entries (fetches child sitemaps) until enough URLs collected
    """
    collected: list[str] = []

    def add_loc(loc: str) -> None:
        if not loc:
            return
        if loc not in collected:
            collected.append(loc)

    # Iterate in insertion order of 'fetched' (declared first, then probes)
    for _, entry in list(fetched.items()):
        if entry.get("status") != 200 or entry.get("parse_error") or not entry.get("urls"):
            continue

        if entry.get("kind") == "sitemapindex":
            for sitemap_url in entry.get("urls", []):
                if len(collected) >= max_urls:
                    break
                if sitemap_url not in fetched:
                    sub_status, sub_error, sub_body = _fetch_url(sitemap_url)
                    fetched[sitemap_url] = _parse_sitemap_fetch(sub_status, sub_error, sub_body)

                sub_entry = fetched.get(sitemap_url) or {}
                if sub_entry.get("status") == 200 and not sub_entry.get("parse_error"):
                    for loc in sub_entry.get("urls", []):
                        add_loc(loc)
                        if len(collected) >= max_urls:
                            break
        else:
            for loc in entry.get("urls", []):
                add_loc(loc)
                if len(collected) >= max_urls:
                    break

        if len(collected) >= max_urls:
            break

    results: list[dict[str, Any]] = []
    for loc in collected[:max_urls]:
        fetch = _fetch_with_redirects(loc, method="GET", max_hops=8)
        results.append({
            "url": loc,
            "status": fetch.get("final_status"),
            "final_url": fetch.get("final_url"),
            "error": fetch.get("error"),
        })

    return {
        "strategy": "first-N-in-document-order",
        "n": max_urls,
        "results": results,
    }


def _urls_equivalent(a: str | None, b: str | None) -> bool:
    if not a or not b:
        return False
    pa = urlparse(a)
    pb = urlparse(b)
    return (pa.netloc.lower(), (pa.path or "/").rstrip("/")) == (pb.netloc.lower(), (pb.path or "/").rstrip("/"))
