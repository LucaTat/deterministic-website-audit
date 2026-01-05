# social_findings.py
from __future__ import annotations

from typing import Any

SOCIAL_PLATFORMS = ["instagram", "facebook", "linkedin", "tiktok", "youtube", "x"]
# WhatsApp is contact-like; we treat it separately.
CONTACT_PLATFORMS = ["whatsapp"]


def build_social_findings(signals: dict) -> list[dict[str, Any]]:
    """
    Convert deterministic social signals into agency-friendly Findings.

    This does NOT guess follower counts, engagement, or SEO impact.
    It only reports observable site-level issues that can affect:
    - brand consistency
    - trust
    - share readiness (later)
    """

    findings: list[dict[str, Any]] = []

    # If extraction errored, report it (but don't fail the whole audit).
    err = signals.get("social_extraction_error")
    if err:
        findings.append({
            "id": "SOCIAL_EXTRACTION_ERROR",
            "category": "social",
            "severity": "warning",
            "title_en": "Social link detection had an error",
            "title_ro": "Detectarea linkurilor sociale a întâmpinat o eroare",
            "description_en": "Social link detection could not be completed reliably for this page.",
            "description_ro": "Detectarea linkurilor sociale nu a putut fi finalizată în mod fiabil pentru această pagină.",
            "recommendation_en": "Re-run the audit. If the error persists, check HTML validity or unusual markup.",
            "recommendation_ro": "Rulați din nou auditul. Dacă eroarea persistă, verificați HTML-ul sau markup-ul neobișnuit.",
            "evidence": {"error": str(err)},
        })

    # Collect presence per platform
    platform_urls: dict[str, list[str]] = {}
    any_profile = False
    for p in SOCIAL_PLATFORMS:
        urls = signals.get(f"{p}_urls") or []
        if isinstance(urls, list) and urls:
            any_profile = True
            platform_urls[p] = urls

    whatsapp_urls = signals.get("whatsapp_urls") or []
    has_whatsapp = isinstance(whatsapp_urls, list) and bool(whatsapp_urls)

    if not any_profile:
        # No social profiles linked on homepage
        findings.append({
            "id": "SOCIAL_NO_PROFILES_DETECTED",
            "category": "social",
            "severity": "warning",
            "title_en": "No social profiles detected on the homepage",
            "title_ro": "Nu am detectat profiluri sociale pe homepage",
            "description_en": "We did not find links to common social profiles (Instagram/Facebook/LinkedIn/TikTok/YouTube/X) on the homepage.",
            "description_ro": "Nu am găsit linkuri către profiluri sociale uzuale (Instagram/Facebook/LinkedIn/TikTok/YouTube/X) pe homepage.",
            "recommendation_en": "Add links to official social profiles in the header or footer, and keep them consistent across the site.",
            "recommendation_ro": "Adăugați linkuri către profilurile sociale oficiale în header sau footer și păstrați-le consecvente pe site.",
            "evidence": {"detected": platform_urls, "whatsapp_urls": whatsapp_urls if has_whatsapp else []},
        })

        if has_whatsapp:
            findings.append({
                "id": "SOCIAL_ONLY_WHATSAPP_PRESENT",
                "category": "social",
                "severity": "info",
                "title_en": "WhatsApp link detected (no other social profiles found)",
                "title_ro": "Link WhatsApp detectat (fără alte profiluri sociale)",
                "description_en": "A WhatsApp contact link is present, but no other social profile links were detected on the homepage.",
                "description_ro": "Există un link de contact WhatsApp, dar nu au fost detectate alte profiluri sociale pe homepage.",
                "recommendation_en": "If you actively use social platforms, add those official profile links as well.",
                "recommendation_ro": "Dacă folosiți activ rețele sociale, adăugați și linkurile către profilurile oficiale.",
                "evidence": {"whatsapp_urls": whatsapp_urls},
            })

    # Multiple profiles per platform can confuse visitors (defensible, conservative wording).
    for p, urls in platform_urls.items():
        if len(urls) >= 2:
            findings.append({
                "id": f"SOCIAL_MULTIPLE_{p.upper()}_LINKS",
                "category": "social",
                "severity": "warning",
                "title_en": f"Multiple {p.capitalize()} links detected",
                "title_ro": f"Mai multe linkuri {p.capitalize()} detectate",
                "description_en": f"The homepage links to multiple {p.capitalize()} URLs. This can confuse visitors and dilute brand consistency.",
                "description_ro": f"Homepage-ul conține mai multe URL-uri de {p.capitalize()}. Acest lucru poate crea confuzie și poate dilua consistența brandului.",
                "recommendation_en": "Keep one primary official profile per platform (or clearly label brand vs. locations).",
                "recommendation_ro": "Păstrați un singur profil oficial principal per platformă (sau etichetați clar brand vs. locații).",
                "evidence": {"platform": p, "urls": urls},
            })

    # Positive note (optional): if profiles exist, add an info finding (useful for completeness in PDF).
    if any_profile:
        findings.append({
            "id": "SOCIAL_PROFILES_PRESENT",
            "category": "social",
            "severity": "info",
            "title_en": "Social profile links detected",
            "title_ro": "Linkuri către profiluri sociale detectate",
            "description_en": "The homepage links to at least one social profile.",
            "description_ro": "Homepage-ul conține cel puțin un link către un profil social.",
            "recommendation_en": "Ensure profile links are correct, up to date, and consistent across the site.",
            "recommendation_ro": "Asigurați-vă că linkurile sunt corecte, actuale și consecvente pe întreg site-ul.",
            "evidence": {"profiles": platform_urls, "whatsapp_urls": whatsapp_urls if has_whatsapp else []},
        })

    return findings
