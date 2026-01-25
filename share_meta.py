# share_meta.py
from __future__ import annotations

from typing import Any
from urllib.parse import urljoin

import requests
from bs4 import BeautifulSoup

from net_guardrails import DEFAULT_HEADERS, DEFAULT_TIMEOUT, MAX_REDIRECTS

HEADERS = DEFAULT_HEADERS


def _collect_meta_values(soup: BeautifulSoup, key_attr: str, key_value: str) -> list[str]:
    vals: list[str] = []
    for meta in soup.find_all("meta"):
        k = meta.get(key_attr)
        if not isinstance(k, str):
            continue
        if k.strip().lower() != key_value:
            continue
        content = meta.get("content")
        if isinstance(content, str):
            c = content.strip()
            if c:
                vals.append(c)
    return vals


def _first_or_empty(values: list[str]) -> str:
    return values[0] if values else ""


def _is_absolute_url(u: str) -> bool:
    return u.startswith("http://") or u.startswith("https://")


def _head_status(url: str, timeout: int = DEFAULT_TIMEOUT) -> dict[str, Any]:
    """Best-effort HEAD request to validate a URL.

    Deterministic logic, but network availability can vary.
    We return structured evidence instead of asserting certainty.
    """
    try:
        session = requests.Session()
        session.max_redirects = MAX_REDIRECTS
        r = session.head(url, headers=HEADERS, timeout=timeout, allow_redirects=True)
        return {
            "ok": True,
            "status_code": int(r.status_code),
            "final_url": str(r.url),
        }
    except requests.TooManyRedirects:
        return {
            "ok": False,
            "error": "too_many_redirects",
        }
    except Exception as e:
        return {
            "ok": False,
            "error": str(e),
        }


def extract_share_meta(html: str, page_url: str | None = None) -> dict[str, Any]:
    """Extract Open Graph and Twitter card metadata from a page.

    This is deterministic extraction from HTML. Optionally uses a best-effort HEAD
    request for og:image/twitter:image validation.

    Returns a nested dict suitable to store in audit.json under signals["share_meta"].
    """

    soup = BeautifulSoup(html or "", "html.parser")

    # Canonical
    canonical_url = ""
    link = soup.find("link", rel=lambda x: isinstance(x, str) and x.lower() == "canonical")
    if link is not None:
        href = link.get("href")
        if isinstance(href, str):
            canonical_url = href.strip()

    base_for_relative = canonical_url or (page_url or "")

    og_keys = [
        "og:title",
        "og:description",
        "og:image",
        "og:url",
        "og:type",
    ]

    twitter_keys = [
        "twitter:card",
        "twitter:title",
        "twitter:description",
        "twitter:image",
    ]

    og: dict[str, list[str]] = {k: _collect_meta_values(soup, "property", k) for k in og_keys}
    tw: dict[str, list[str]] = {k: _collect_meta_values(soup, "name", k) for k in twitter_keys}

    # Normalized single values (first) for convenience
    og_first = {k: _first_or_empty(v) for k, v in og.items()}
    tw_first = {k: _first_or_empty(v) for k, v in tw.items()}

    # Image URL normalization (do NOT force absolute, only report)
    og_image = og_first.get("og:image", "")
    tw_image = tw_first.get("twitter:image", "")

    og_image_absolute = ""
    if og_image and base_for_relative and not _is_absolute_url(og_image):
        og_image_absolute = urljoin(base_for_relative, og_image)

    tw_image_absolute = ""
    if tw_image and base_for_relative and not _is_absolute_url(tw_image):
        tw_image_absolute = urljoin(base_for_relative, tw_image)

    # Best-effort checks (evidence only)
    og_image_check = _head_status(og_image_absolute or og_image) if (og_image_absolute or og_image) else {}
    tw_image_check = _head_status(tw_image_absolute or tw_image) if (tw_image_absolute or tw_image) else {}

    return {
        "canonical_url": canonical_url,
        "page_url": page_url or "",
        "og": og,
        "twitter": tw,
        "og_first": og_first,
        "twitter_first": tw_first,
        "og_image_absolute": og_image_absolute,
        "twitter_image_absolute": tw_image_absolute,
        "og_image_check": og_image_check,
        "twitter_image_check": tw_image_check,
    }
