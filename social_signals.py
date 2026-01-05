# social_signals.py
from __future__ import annotations

from bs4 import BeautifulSoup

# Deterministic: no API calls, no follower counts, no "social ranking" claims.
# We only detect presence of links to common social/contact channels in <a href="...">.

SOCIAL_DOMAINS = {
    "instagram": ["instagram.com"],
    "facebook": ["facebook.com", "fb.com"],
    "tiktok": ["tiktok.com"],
    "whatsapp": ["wa.me", "api.whatsapp.com", "whatsapp.com"],
    "linkedin": ["linkedin.com"],
    "youtube": ["youtube.com", "youtu.be"],
    "x": ["x.com", "twitter.com"],
}

# Common share/intent endpoints that should NOT count as "official profile linked"
SHARE_PATTERNS = [
    "sharer.php",
    "/share",
    "/intent/",
    "sharearticle",
    "share?",  # generic
]


def _is_share_link(href: str) -> bool:
    h = (href or "").lower()
    return any(p in h for p in SHARE_PATTERNS)


def extract_social_signals(html: str) -> dict:
    soup = BeautifulSoup(html or "", "html.parser")

    found: dict[str, list[str]] = {k: [] for k in SOCIAL_DOMAINS}

    for a in soup.find_all("a"):
        raw_href = a.get("href")
        if not isinstance(raw_href, str):
            continue

        href = raw_href.strip()
        if not href:
            continue

        href_l = href.lower()

        # Ignore non-links
        if href_l.startswith("#") or href_l.startswith("javascript:"):
            continue

        # Ignore share/intent URLs
        if _is_share_link(href_l):
            continue

        for platform, domains in SOCIAL_DOMAINS.items():
            if any(d in href_l for d in domains):
                found[platform].append(href)

    # Deduplicate while preserving order
    for k, urls in found.items():
        seen = set()
        deduped = []
        for u in urls:
            if u in seen:
                continue
            seen.add(u)
            deduped.append(u)
        found[k] = deduped

    result: dict[str, object] = {}
    for platform, urls in found.items():
        result[f"{platform}_linked"] = bool(urls)
        result[f"{platform}_urls"] = urls

    return result
