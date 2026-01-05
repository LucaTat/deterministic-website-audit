# share_meta_findings.py
from __future__ import annotations

from typing import Any


CORE_OG = ["og:title", "og:description", "og:image", "og:url"]
CORE_TW = ["twitter:card"]

ALLOWED_TW_CARDS = {"summary", "summary_large_image", "app", "player"}


def _has_values(meta_map: dict[str, list[str]], key: str) -> bool:
    v = meta_map.get(key) or []
    return isinstance(v, list) and len(v) > 0


def _first(meta_first: dict[str, str], key: str) -> str:
    v = meta_first.get(key)
    return v if isinstance(v, str) else ""


def build_share_meta_findings(signals: dict) -> list[dict[str, Any]]:
    """Create Findings related to share previews (Open Graph + Twitter cards).

    Deterministic, evidence-based.

    Notes on severity:
    - Missing core OG tags: warning (impacts link previews/CTR)
    - Image URL clearly 404/410: fail
    - Image check network errors: warning (could not verify)
    - Missing Twitter card: info (many sites rely only on OG)
    """

    findings: list[dict[str, Any]] = []

    share = signals.get("share_meta") or {}
    if not isinstance(share, dict) or not share:
        return findings

    if share.get("error"):
        findings.append({
            "id": "SHARE_META_EXTRACTION_ERROR",
            "category": "share_meta",
            "severity": "warning",
            "title_en": "Share metadata extraction had an error",
            "title_ro": "Extracția metadatelor de share a întâmpinat o eroare",
            "description_en": "Open Graph/Twitter metadata could not be extracted reliably for this page.",
            "description_ro": "Metadatele Open Graph/Twitter nu au putut fi extrase în mod fiabil pentru această pagină.",
            "recommendation_en": "Re-run the audit. If the error persists, check HTML validity or unusual head markup.",
            "recommendation_ro": "Rulați din nou auditul. Dacă eroarea persistă, verificați HTML-ul sau markup-ul neobișnuit din <head>.",
            "evidence": {"error": str(share.get("error"))},
        })
        return findings

    og = share.get("og") or {}
    tw = share.get("twitter") or {}
    og_first = share.get("og_first") or {}
    tw_first = share.get("twitter_first") or {}

    # Missing OG core tags
    missing_og = [k for k in CORE_OG if not _has_values(og, k)]
    if missing_og:
        findings.append({
            "id": "SOCIAL_OG_MISSING_CORE_TAGS",
            "category": "share_meta",
            "severity": "warning",
            "title_en": "Open Graph tags are missing",
            "title_ro": "Lipsesc tag-uri Open Graph",
            "description_en": "Some core Open Graph tags are missing, which can reduce the quality of link previews on social platforms.",
            "description_ro": "Lipsesc unele tag-uri Open Graph de bază, ceea ce poate reduce calitatea previzualizării linkului pe platformele sociale.",
            "recommendation_en": "Add the missing Open Graph tags on the homepage (title, description, image, url).",
            "recommendation_ro": "Adăugați tag-urile Open Graph lipsă pe homepage (title, description, image, url).",
            "evidence": {"missing": missing_og, "og_first": og_first},
        })

    # Duplicate OG tags
    dup_og = {k: v for k, v in og.items() if isinstance(v, list) and len(v) >= 2}
    if dup_og:
        findings.append({
            "id": "SOCIAL_DUPLICATE_OG_TAGS",
            "category": "share_meta",
            "severity": "warning",
            "title_en": "Duplicate Open Graph tags detected",
            "title_ro": "Tag-uri Open Graph duplicate detectate",
            "description_en": "Multiple values were found for one or more Open Graph tags. Social platforms may pick the wrong one.",
            "description_ro": "Au fost găsite mai multe valori pentru unul sau mai multe tag-uri Open Graph. Platformele sociale pot alege valoarea greșită.",
            "recommendation_en": "Keep a single value per Open Graph tag (especially title, description, image, url).",
            "recommendation_ro": "Păstrați o singură valoare per tag Open Graph (mai ales title, description, image, url).",
            "evidence": {"duplicates": dup_og},
        })

    # og:url vs canonical mismatch
    canonical = share.get("canonical_url") or ""
    og_url = _first(og_first, "og:url")
    if canonical and og_url and canonical.strip() != og_url.strip():
        findings.append({
            "id": "SOCIAL_OG_URL_MISMATCH_CANONICAL",
            "category": "share_meta",
            "severity": "warning",
            "title_en": "og:url does not match canonical",
            "title_ro": "og:url nu se potrivește cu canonical",
            "description_en": "The page canonical URL differs from og:url. This can cause inconsistent link previews or duplicate share counters.",
            "description_ro": "URL-ul canonical diferă de og:url. Acest lucru poate duce la previzualizări inconsistente sau contorizări diferite la share.",
            "recommendation_en": "Align og:url with the canonical URL for the homepage.",
            "recommendation_ro": "Aliniați og:url cu URL-ul canonical al homepage-ului.",
            "evidence": {"canonical_url": canonical, "og:url": og_url},
        })

    # og:image checks
    og_image = _first(og_first, "og:image")
    og_image_abs = share.get("og_image_absolute") or ""
    og_check = share.get("og_image_check") or {}

    if og_image and og_image_abs:
        findings.append({
            "id": "SOCIAL_OG_IMAGE_RELATIVE_URL",
            "category": "share_meta",
            "severity": "warning",
            "title_en": "og:image uses a relative URL",
            "title_ro": "og:image folosește un URL relativ",
            "description_en": "The og:image value appears to be relative. Some platforms require absolute URLs for consistent previews.",
            "description_ro": "Valoarea og:image pare relativă. Unele platforme necesită URL-uri absolute pentru previzualizări consistente.",
            "recommendation_en": "Use an absolute URL for og:image.",
            "recommendation_ro": "Folosiți un URL absolut pentru og:image.",
            "evidence": {"og:image": og_image, "resolved": og_image_abs},
        })

    # Determine image fetchability severity conservatively
    if og_image:
        if isinstance(og_check, dict) and og_check:
            if og_check.get("ok") is False:
                findings.append({
                    "id": "SOCIAL_OG_IMAGE_NOT_VERIFIED",
                    "category": "share_meta",
                    "severity": "warning",
                    "title_en": "og:image could not be verified",
                    "title_ro": "og:image nu a putut fi verificat",
                    "description_en": "We could not verify that og:image is reachable (network error or blocked request).",
                    "description_ro": "Nu am putut verifica dacă og:image este accesibil (eroare de rețea sau cerere blocată).",
                    "recommendation_en": "Manually check that the image URL loads publicly (no auth, no blocking) and returns HTTP 200.",
                    "recommendation_ro": "Verificați manual că URL-ul imaginii se încarcă public (fără autentificare, fără blocări) și returnează HTTP 200.",
                    "evidence": {"url": og_image_abs or og_image, "check": og_check},
                })
            else:
                code = int(og_check.get("status_code") or 0)
                if code in (404, 410):
                    sev = "fail"
                    fid = "SOCIAL_OG_IMAGE_NOT_FETCHABLE"
                elif code >= 400 and code != 0:
                    sev = "warning"
                    fid = "SOCIAL_OG_IMAGE_PROBLEM"
                else:
                    sev = ""  # no issue
                    fid = ""

                if fid:
                    findings.append({
                        "id": fid,
                        "category": "share_meta",
                        "severity": sev,
                        "title_en": "og:image is not reachable" if sev != "fail" else "og:image returns 404/410",
                        "title_ro": "og:image nu este accesibil" if sev != "fail" else "og:image returnează 404/410",
                        "description_en": "The image URL used for social previews does not return a successful response.",
                        "description_ro": "URL-ul imaginii folosit pentru previzualizare socială nu returnează un răspuns de succes.",
                        "recommendation_en": "Fix og:image to point to a publicly reachable image URL (HTTP 200).",
                        "recommendation_ro": "Corectați og:image astfel încât să indice către o imagine accesibilă public (HTTP 200).",
                        "evidence": {"url": og_image_abs or og_image, "check": og_check},
                    })

    # Twitter card
    missing_tw = [k for k in CORE_TW if not _has_values(tw, k)]
    if missing_tw:
        findings.append({
            "id": "SOCIAL_TWITTER_CARD_MISSING",
            "category": "share_meta",
            "severity": "info",
            "title_en": "Twitter card metadata is missing",
            "title_ro": "Lipsesc metadatele Twitter Card",
            "description_en": "twitter:card is not present. Many platforms use Open Graph, but Twitter/X uses Twitter card metadata.",
            "description_ro": "twitter:card lipsește. Multe platforme folosesc Open Graph, dar Twitter/X folosește metadate Twitter Card.",
            "recommendation_en": "Add twitter:card (and twitter:title/description/image) for consistent previews on Twitter/X.",
            "recommendation_ro": "Adăugați twitter:card (și twitter:title/description/image) pentru previzualizări consistente pe Twitter/X.",
            "evidence": {"twitter_first": tw_first},
        })
    else:
        card = _first(tw_first, "twitter:card").strip().lower()
        if card and card not in ALLOWED_TW_CARDS:
            findings.append({
                "id": "SOCIAL_TWITTER_CARD_UNUSUAL",
                "category": "share_meta",
                "severity": "warning",
                "title_en": "Unusual twitter:card value",
                "title_ro": "Valoare neobișnuită pentru twitter:card",
                "description_en": "twitter:card has a value that is not commonly used. This can lead to unexpected preview behavior.",
                "description_ro": "twitter:card are o valoare rar folosită. Acest lucru poate duce la previzualizări neașteptate.",
                "recommendation_en": "Use a standard value like summary or summary_large_image.",
                "recommendation_ro": "Folosiți o valoare standard, precum summary sau summary_large_image.",
                "evidence": {"twitter:card": card},
            })

    # Duplicate Twitter tags (optional)
    dup_tw = {k: v for k, v in tw.items() if isinstance(v, list) and len(v) >= 2}
    if dup_tw:
        findings.append({
            "id": "SOCIAL_DUPLICATE_TWITTER_TAGS",
            "category": "share_meta",
            "severity": "warning",
            "title_en": "Duplicate Twitter card tags detected",
            "title_ro": "Tag-uri Twitter Card duplicate detectate",
            "description_en": "Multiple values were found for one or more Twitter card tags. Twitter/X may choose the wrong one.",
            "description_ro": "Au fost găsite mai multe valori pentru unul sau mai multe tag-uri Twitter Card. Twitter/X poate alege valoarea greșită.",
            "recommendation_en": "Keep a single value per Twitter card tag (especially twitter:card, title, description, image).",
            "recommendation_ro": "Păstrați o singură valoare per tag Twitter Card (mai ales twitter:card, title, description, image).",
            "evidence": {"duplicates": dup_tw},
        })

    # Positive note (optional)
    if not missing_og and not missing_tw:
        findings.append({
            "id": "SOCIAL_SHARE_META_PRESENT",
            "category": "share_meta",
            "severity": "info",
            "title_en": "Share preview metadata detected",
            "title_ro": "Metadate pentru previzualizare detectate",
            "description_en": "Open Graph and Twitter card metadata are present on the homepage.",
            "description_ro": "Metadatele Open Graph și Twitter Card sunt prezente pe homepage.",
            "recommendation_en": "Periodically check that previews render correctly on Facebook/LinkedIn/WhatsApp and Twitter/X.",
            "recommendation_ro": "Verificați periodic că previzualizările se redau corect pe Facebook/LinkedIn/WhatsApp și Twitter/X.",
            "evidence": {"og_first": og_first, "twitter_first": tw_first},
        })

    return findings
