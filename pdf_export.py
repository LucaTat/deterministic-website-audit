# pdf_export.py
import os
import datetime as dt
import unicodedata
from typing import Any, TypeAlias
from urllib.parse import urlparse
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    HRFlowable,
    ListFlowable,
    KeepTogether,
    PageBreak,
    Flowable,
    CondPageBreak,
)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

AGENCY_NAME = "Digital Audit Studio"
AGENCY_CONTACT = "contact@digitalaudit.ro"
BODY_FONT = "DejaVuSans"
BOLD_FONT = "DejaVuSans-Bold"

TableData: TypeAlias = list[list[Any]]


def _register_fonts() -> tuple[str, str]:
    global BODY_FONT, BOLD_FONT
    here = os.path.dirname(os.path.abspath(__file__))
    font_dir = os.path.join(here, "assets", "fonts")
    body_path = os.path.join(font_dir, "DejaVuSans.ttf")
    bold_path = os.path.join(font_dir, "DejaVuSans-Bold.ttf")

    if os.path.exists(body_path) and os.path.exists(bold_path):
        pdfmetrics.registerFont(TTFont(BODY_FONT, body_path))
        pdfmetrics.registerFont(TTFont(BOLD_FONT, bold_path))
        pdfmetrics.registerFontFamily(
            BODY_FONT,
            normal=BODY_FONT,
            bold=BOLD_FONT,
            italic=BODY_FONT,
            boldItalic=BOLD_FONT,
        )
        return BODY_FONT, BOLD_FONT

    BODY_FONT = "Helvetica"
    BOLD_FONT = "Helvetica-Bold"
    return BODY_FONT, BOLD_FONT


def quick_wins_en(mode: str, signals: dict) -> list[str]:
    if mode != "ok":
        return []
    wins = []
    if not signals.get("booking_detected"):
        wins.append("Add a clear primary call-to-action above the fold (Book / Request appointment / Request quote).")
    if not signals.get("contact_detected"):
        wins.append("Make contact details obvious: phone + address + hours in header/footer and a clear Contact page link.")
    if not signals.get("services_keywords_detected"):
        wins.append("Clarify the offer: a short, scannable list of services with outcomes (what the customer gets).")
    if not signals.get("pricing_keywords_detected"):
        wins.append("Add pricing ranges or starting prices (\"from…\", packages) to reduce hesitation and increase trust.")
    if not wins:
        wins.append("No major gaps detected in these basic checks.")
    return wins[:3]


def quick_wins_ro(mode: str, signals: dict) -> list[str]:
    if mode != "ok":
        return []
    wins = []
    if not signals.get("booking_detected"):
        wins.append("Adăugați un buton „Programează-te” vizibil (sus în pagină) + link către formular/telefon/WhatsApp.")
    if not signals.get("contact_detected"):
        wins.append("Faceți datele de contact ușor de găsit: telefon + adresă + program în header/footer și pe o pagină Contact.")
    if not signals.get("services_keywords_detected"):
        wins.append("Clarificați oferta: listă scurtă cu servicii principale + beneficii (primele 10 secunde pe pagină).")
    if not signals.get("pricing_keywords_detected"):
        wins.append("Adăugați prețuri orientative sau intervale („de la…”, pachete) pentru a crește încrederea și conversia.")
    if not wins:
        wins.append("Nu am detectat lipsuri majore la aceste verificări de bază.")
    return wins[:3]


def _get_crawl_v1(audit_result: dict) -> dict:
    crawl = audit_result.get("crawl_v1")
    if isinstance(crawl, dict):
        return crawl
    signals = audit_result.get("signals", {}) or {}
    crawl = signals.get("crawl_v1")
    return crawl if isinstance(crawl, dict) else {}


def _select_crawl_evidence(crawl_v1: dict, max_items: int = 4) -> list[dict]:
    pages = crawl_v1.get("pages") or []
    evidence: list[dict] = []
    homepage_idx = None

    def _is_homepage(url: str) -> bool:
        try:
            path = urlparse(url).path
        except Exception:
            return False
        return path in ("", "/")

    def _first_snippet(page: dict) -> str:
        snippets = page.get("snippets") or []
        if not snippets:
            return ""
        return str(snippets[0] or "").strip()

    for i, page in enumerate(pages):
        url = str(page.get("url") or "").strip()
        if not url:
            continue
        if _is_homepage(url):
            snippet = _first_snippet(page)
            if snippet:
                evidence.append({"url": url, "snippet": snippet[:180]})
                homepage_idx = i
            break

    for i, page in enumerate(pages):
        if len(evidence) >= max_items:
            break
        if homepage_idx is not None and i == homepage_idx:
            continue
        url = str(page.get("url") or "").strip()
        if not url:
            continue
        if _is_homepage(url) and homepage_idx is None:
            snippet = _first_snippet(page)
            if snippet:
                evidence.append({"url": url, "snippet": snippet[:180]})
                homepage_idx = i
            continue
        snippet = _first_snippet(page)
        if not snippet:
            continue
        evidence.append({"url": url, "snippet": snippet[:180]})

    return evidence[:max_items]


def _impact_label(score: int, lang: str) -> str:
    is_ro = (lang or "").lower().strip() == "ro"
    if score < 70:
        label = "ridicat" if is_ro else "high"
    elif score < 90:
        label = "mediu" if is_ro else "medium"
    else:
        label = "scăzut" if is_ro else "low"
    return f"Impact probabil: {label}" if is_ro else f"Likely impact: {label}"


def humanize_fetch_error_label(reason: str, lang: str = "en") -> str:
    text = (reason or "").lower()
    is_ro = (lang or "").lower().strip() == "ro"
    if "ssl" in text or "certificate" in text or "cert" in text:
        return "Problemă SSL: certificatul nu este valid." if is_ro else "SSL issue: certificate is not valid."
    if "dns" in text or "name or service not known" in text or "nodename nor servname" in text:
        return "Problemă DNS: domeniul nu este configurat corect." if is_ro else "DNS issue: domain is not configured correctly."
    if "timeout" in text or "timed out" in text:
        return "Încărcarea site-ului a expirat (timeout)." if is_ro else "The site load timed out."
    if "forbidden" in text or "403" in text:
        return "Acces restricționat (posibile protecții/filtrare)." if is_ro else "Access restricted (possible protection/filtering)."
    if "connection" in text or "refused" in text:
        return "Conexiunea către site a eșuat." if is_ro else "Connection to the site failed."
    if "404" in text or "not found" in text:
        return "Pagina nu a fost găsită (404)." if is_ro else "Page not found (404)."
    if ("http" in text and "5" in text) or "server error" in text:
        return "Eroare de server (5xx)." if is_ro else "Server error (5xx)."
    return "Site-ul nu a putut fi accesat." if is_ro else "The website could not be reached."


def get_primary_score(audit_result: dict) -> int:
    signals = audit_result.get("signals", {}) or {}
    raw_score = audit_result.get("clarity_score")
    if raw_score is None:
        raw_score = signals.get("clarity_score")
    if raw_score is None:
        raw_score = signals.get("score")
    if raw_score is None:
        raw_score = audit_result.get("score")

    try:
        return int(raw_score or 0)
    except (TypeError, ValueError):
        return 0


def score_to_risk_label(score: int, lang: str) -> str:
    is_ro = (lang or "").lower().strip() == "ro"
    if score < 40:
        return "RIDICAT" if is_ro else "HIGH"
    if score < 70:
        return "MEDIU" if is_ro else "MEDIUM"
    return "SCĂZUT" if is_ro else "LOW"


def status_label(audit_result: dict, lang: str) -> str:
    status = (audit_result.get("status") or audit_result.get("mode") or "").lower().strip()
    if status == "no_website":
        return "NO WEBSITE"
    return "BROKEN" if status == "broken" else "OK"


def _preferred_narrative(audit_result: dict) -> dict:
    ai_narrative = audit_result.get("ai_narrative")
    if isinstance(ai_narrative, dict) and ai_narrative:
        return ai_narrative
    positive_narrative = audit_result.get("positive_narrative")
    if isinstance(positive_narrative, dict) and positive_narrative:
        return positive_narrative
    return audit_result.get("client_narrative", {}) or {}


def certainty_label(audit_result: dict, lang: str) -> str:
    narrative = _preferred_narrative(audit_result)
    confidence = (narrative.get("confidence") or "").strip()
    if confidence:
        return confidence

    score = get_primary_score(audit_result)
    if (lang or "").lower().strip() == "ro":
        if score < 70:
            return "Ridicată"
        if score < 85:
            return "Medie"
        return "Scăzută"

    if score < 70:
        return "High"
    if score < 85:
        return "Medium"
    return "Low"


def decision_verdict(audit_result: dict, lang: str) -> str:
    labels = {
        "ro": {
            "worth_it": "MERITĂ",
            "caution": "ATENȚIE",
            "not_worth_it": "NU MERITĂ",
        },
        "en": {
            "worth_it": "WORTH IT",
            "caution": "CAUTION",
            "not_worth_it": "NOT WORTH IT",
        },
    }
    lang_key = (lang or "en").lower().strip()
    if lang_key not in labels:
        lang_key = "en"

    status = (audit_result.get("status") or audit_result.get("mode") or "").upper()
    if status == "BROKEN":
        return labels[lang_key]["not_worth_it"]

    score = get_primary_score(audit_result)

    if score < 40:
        return labels[lang_key]["not_worth_it"]
    if score < 70:
        return labels[lang_key]["caution"]
    return labels[lang_key]["worth_it"]


def draw_scorecard(c, audit_result: dict, lang: str, x: float, y: float) -> None:
    width = 78 * mm
    height = 28 * mm
    padding = 3 * mm
    row_height = 6 * mm
    label_col_width = 34 * mm
    font_size = 9

    labels = {
        "ro": ["CLARITATE", "RISC", "STATUS", "CERTITUDINE"],
        "en": ["CLARITY", "RISK", "STATUS", "CERTAINTY"],
    }
    lang_key = (lang or "en").lower().strip()
    if lang_key not in labels:
        lang_key = "en"

    def _truncate(text: str, max_chars: int) -> str:
        text = str(text or "")
        if len(text) <= max_chars:
            return text
        return text[: max_chars - 3] + "..."

    score = get_primary_score(audit_result)
    certainty = str(certainty_label(audit_result, lang_key)).upper()
    values = [
        f"{score}/100",
        score_to_risk_label(score, lang_key),
        status_label(audit_result, lang_key),
        certainty,
    ]

    c.saveState()
    c.setLineWidth(0.6)
    c.setStrokeColor(colors.HexColor("#e5e7eb"))
    c.rect(x, y, width, height, stroke=1, fill=0)

    row_top = y + height - padding
    for i, label in enumerate(labels[lang_key]):
        row_center = row_top - (i + 0.5) * row_height
        baseline = row_center - (font_size / 2)
        c.setFont(BOLD_FONT, font_size)
        c.setFillColor(colors.HexColor("#111827"))
        c.drawString(x + padding, baseline, label)

        c.setFont(BODY_FONT, font_size)
        c.setFillColor(colors.HexColor("#111827"))
        value = _truncate(values[i], 16)
        c.drawString(x + padding + label_col_width, baseline, value)

    c.restoreState()


class ScorecardFlowable(Flowable):
    def __init__(self, audit_result: dict, lang: str):
        super().__init__()
        self.audit_result = audit_result
        self.lang = lang
        self.width = 70 * mm
        self.height = 28 * mm

    def wrap(self, availWidth, availHeight):
        return self.width, self.height

    def draw(self):
        draw_scorecard(self.canv, self.audit_result, self.lang, 0, 0)


def export_audit_pdf(audit_result: dict, out_path: str, tool_version: str = "unknown") -> str:
    body_font, bold_font = _register_fonts()

    if not out_path.lower().endswith(".pdf"):
        out_path += ".pdf"

    lang = (audit_result.get("lang") or "en").lower().strip()
    if lang not in ("en", "ro"):
        lang = "en"

    display_tool_version = str(tool_version or "").strip()
    if not display_tool_version or display_tool_version.lower() == "unknown":
        display_tool_version = "v2.0.0"

    labels = {
        "en": {
            "title": "Website Audit",
            "cover_title": "Deterministic Website Audit",
            "cover_subtitle": "Decision-grade, client-safe",
            "cover_tagline": "Client-safe • Non-technical • Decision-grade",
            "cover_audited_domain": "Audited domain",
            "cover_campaign": "Campaign",
            "cover_executive_summary": "Executive summary",
            "cover_expert_interpretation": "Expert interpretation (context)",
            "cover_next_steps": "Next steps",
            "cover_next_steps_ok": [
                "Send this PDF to the client.",
                "Optional: address quick wins.",
            ],
            "cover_next_steps_issues": [
                "Address the highest-impact issues first.",
                "Re-run to confirm.",
            ],
            "cover_status_ok": "OK (Ready)",
            "cover_status_issues": "Issues found",
            "cover_status_raw_label": "Raw status",
            "cover_status_note": "Status reflects audit completeness, not website quality.",
            "date": "Date",
            "website": "Website",
            "status": "Status",
            "score": "Score",
            "overview": "Overview",
            "primary": "Primary issue",
            "secondary": "Secondary issues",
            "plan": "Recommended plan",
            "confidence": "Assessment confidence",
            "quickwins": "Top 3 quick wins",
            "checks": "Basic checks",
            "scope_limits": "Scope and limits",
            "social_findings": "Social signals",
            "share_meta_findings": "Share preview & social metadata",
            "indexability_findings": "Indexability & Technical Access",
            "conversion_loss_findings": "Estimated conversion impact",
            "ai_advisory": "AI advisory (experimental)",
            "ai_summary": "Executive summary",
            "ai_priorities": "Priorities",
            "ai_levels": {
                "fix_now": "Fix now",
                "fix_soon": "Fix soon",
                "monitor": "Monitor",
            },
            "ai_status": "AI status",
            "ai_fallback_note": "AI unavailable; fallback advisory generated.",
            "ai_disclaimer": "AI-generated advisory. Deterministic findings remain authoritative.",
            "severity": "Severity",
            "finding_col": "Finding",
            "recommendation_col": "Recommendation",
            "estimate_col": "Estimated impact",
            "confidence_col": "Assessment confidence",
            "booking": "Booking detected",
            "contact": "Contact detected",
            "services": "Services detected (keywords)",
            "pricing": "Pricing detected (keywords)",
            "yes": "Yes",
            "no": "No",
            "error_details": "Error details",
            "note": "Note: This report was generated automatically based on the content accessible at the time of the audit.",
            "status_map": {
                "no_website": "No website",
                "broken": "Website unreachable / broken",
                "ok": "Website reachable",
            },
            "audit_type": "Audit type",
            "audit_type_map": {
                "critical_risk": "Critical Risk Audit",
                "opportunity": "Opportunity Audit",
            },
            "banner_critical": "CRITICAL FAILURE DETECTED",
            "banner_ok": "NO CRITICAL FAILURES DETECTED",
            "banner_critical_sub": "This issue blocks meaningful traffic and conversions. Fix this before SEO or marketing work.",
            "banner_ok_sub": "No blocking failures detected. Focus on conversion and clarity opportunities.",
            "what_blocks": "What this blocks",
            "could_not_audit": "What could not be audited",
            "blocks_map": {
                "organic_search": "Google Search traffic",
                "google_business_profile": "Google Business Profile traffic",
                "direct_and_referral": "Direct and referral traffic",
                "user_trust_security": "User trust and security signals",
                "all_conversions": "Any conversion or lead generation",
                "audit_delivery": "Audit delivery",
                "audit_coverage": "Audit coverage",
                "client_reporting": "Client reporting",
            },
            "blocked_checks_map": {
                "indexability_and_crawlability": "Indexability and crawlability",
                "internal_linking": "Internal linking",
                "conversion_paths": "Conversion paths",
                "contact_and_booking_clarity": "Contact and booking clarity",
            },
            "date_fmt": lambda: dt.date.today().strftime("%Y-%m-%d"),
        },
        "ro": {
            "title": "Audit Website",
            "cover_title": "Deterministic Website Audit",
            "cover_subtitle": "Evaluare decizională, client-safe",
            "cover_tagline": "Client-safe • Non-tehnic • Pentru decizie",
            "cover_audited_domain": "Domeniu auditat",
            "cover_campaign": "Campanie",
            "cover_executive_summary": "Rezumat executiv",
            "cover_expert_interpretation": "Interpretare expert (context)",
            "cover_next_steps": "Pași următori",
            "cover_next_steps_ok": [
                "Trimite acest PDF clientului.",
                "Opțional: rezolvă quick wins.",
            ],
            "cover_next_steps_issues": [
                "Rezolvă întâi problemele cu impact mare.",
                "Rulează din nou pentru confirmare.",
            ],
            "cover_status_ok": "OK (Gata de trimis)",
            "cover_status_issues": "Probleme găsite",
            "cover_status_raw_label": "Status brut",
            "cover_status_note": "Statusul indică dacă auditul a rulat complet, nu calitatea website-ului.",
            "date": "Data",
            "website": "Website",
            "status": "Status",
            "score": "Scor claritate conversie",
            "overview": "Prezentare generală",
            "primary": "Problema principală",
            "secondary": "Probleme secundare",
            "plan": "Plan recomandat",
            "confidence": "Certitudine evaluare",
            "quickwins": "Top 3 „Quick Wins”",
            "checks": "Verificări de bază",
            "scope_limits": "Scop și limite",
            "social_findings": "Semnale sociale",
            "share_meta_findings": "Previzualizare share & metadate sociale",
            "indexability_findings": "Indexare & Acces Tehnic",
            "conversion_loss_findings": "Impact estimat asupra conversiilor",
            "ai_advisory": "Recomandări AI (experimental)",
            "ai_summary": "Rezumat executiv",
            "ai_priorities": "Priorități",
            "ai_levels": {
                "fix_now": "Fix acum",
                "fix_soon": "Fix curând",
                "monitor": "Monitorizare",
            },
            "ai_status": "Status AI",
            "ai_fallback_note": "AI indisponibil; s-a generat un rezumat de rezervă.",
            "ai_disclaimer": "Recomandări generate de AI. Constatările deterministice rămân autoritare.",
            "severity": "Severitate",
            "finding_col": "Constatare",
            "recommendation_col": "Recomandare",
            "estimate_col": "Impact estimat",
            "confidence_col": "Certitudine evaluare",
            "booking": "Booking detectat",
            "contact": "Contact detectat",
            "services": "Servicii detectate (keywords)",
            "pricing": "Prețuri detectate (keywords)",
            "yes": "Da",
            "no": "Nu",
            "error_details": "Detalii eroare",
            "note": "Notă: raport generat automat pe baza conținutului accesibil la momentul rulării.",
            "status_map": {
                "no_website": "Fără website",
                "broken": "Website nefuncțional / inaccesibil",
                "ok": "Website funcțional",
            },
            "audit_type": "Tip audit",
            "audit_type_map": {
                "critical_risk": "Audit de Risc Critic",
                "opportunity": "Audit de Oportunități",
            },
            "banner_critical": "PROBLEMĂ CRITICĂ DETECTATĂ",
            "banner_ok": "NU AU FOST DETECTATE PROBLEME CRITICE",
            "banner_critical_sub": "Această problemă blochează traficul și conversiile relevante. Rezolvați înainte de SEO/marketing.",
            "banner_ok_sub": "Nu au fost detectate blocaje majore. Concentrați-vă pe oportunități de conversie și claritate.",
            "what_blocks": "Ce blochează această problemă",
            "could_not_audit": "Ce nu s-a putut audita",
            "blocks_map": {
                "organic_search": "Trafic din Google Search",
                "google_business_profile": "Trafic din Google Business Profile",
                "direct_and_referral": "Trafic direct și din linkuri externe",
                "user_trust_security": "Încrederea utilizatorilor și semnalele de securitate",
                "all_conversions": "Orice conversie sau generare de lead-uri",
                "audit_delivery": "Livrarea auditului",
                "audit_coverage": "Acoperirea auditului",
                "client_reporting": "Raportare către client",
            },
            "blocked_checks_map": {
                "indexability_and_crawlability": "Indexare și crawlabilitate",
                "internal_linking": "Linkuri interne",
                "conversion_paths": "Fluxuri de conversie",
                "contact_and_booking_clarity": "Claritatea contactului și rezervării",
            },
            "date_fmt": lambda: dt.date.today().strftime("%d.%m.%Y"),
        },
    }[lang]

    doc = SimpleDocTemplate(
        out_path,
        pagesize=A4,
        leftMargin=18 * mm,
        rightMargin=18 * mm,
        topMargin=16 * mm,
        bottomMargin=16 * mm,
        title=labels["title"],
        author="Website Audit Tool",
    )

    styles = getSampleStyleSheet()

    for s in styles.byName.values():
        s.fontName = body_font

    styles.add(ParagraphStyle(
        name="H1",
        fontName=body_font,
        fontSize=18,
        leading=22,
        textColor=colors.HexColor("#111827"),
    ))

    styles.add(ParagraphStyle(
        name="H2",
        fontName=body_font,
        fontSize=14,
        leading=18,
        textColor=colors.HexColor("#111827"),
        spaceBefore=12,
        spaceAfter=4,
    ))

    styles.add(ParagraphStyle(
        name="Body",
        fontName=body_font,
        fontSize=10,
        leading=15,
        textColor=colors.HexColor("#111827"),
    ))

    styles.add(ParagraphStyle(
        name="Small",
        fontName=body_font,
        fontSize=9,
        leading=13,
        textColor=colors.HexColor("#374151"),
    ))
    styles.add(ParagraphStyle(
        name="Meta",
        fontName=body_font,
        fontSize=8,
        leading=10,
        textColor=colors.HexColor("#6b7280"),
    ))
    styles.add(ParagraphStyle(
        name="CardTitle",
        fontName=body_font,
        fontSize=15,
        leading=19,
        textColor=colors.HexColor("#111827"),
        spaceAfter=4,
    ))
    styles.add(ParagraphStyle(
        name="Verdict",
        fontName=bold_font,
        fontSize=11,
        leading=13,
        textColor=colors.HexColor("#111827"),
    ))

    url = audit_result.get("url", "")
    mode = audit_result.get("mode", "ok")
    signals = audit_result.get("signals", {}) or {}
    crawl_v1 = _get_crawl_v1(audit_result)
    client_narrative = _preferred_narrative(audit_result)
    findings = audit_result.get("findings", []) or []
    overview = client_narrative.get("overview", []) or []
    primary = client_narrative.get("primary_issue", {}) or {}
    secondary = client_narrative.get("secondary_issues", []) or []
    plan = client_narrative.get("plan", []) or []
    confidence = client_narrative.get("confidence", "") or ""
    p_title = primary.get("title", "")
    primary_title = p_title.strip() if isinstance(p_title, str) and p_title.strip() else "N/A"
    blockers_candidates = [
        audit_result.get("blockers"),
        (audit_result.get("verdict") or {}).get("blockers"),
        signals.get("blockers"),
        client_narrative.get("blockers"),
    ]
    blockers = []
    for candidate in blockers_candidates:
        if isinstance(candidate, list) and all(isinstance(item, str) for item in candidate):
            blockers = [item for item in candidate if item.strip()]
            break

    score = int(signals.get("score", 0) or 0)
    if mode in ("no_website", "broken"):
        score = 0
    evidence_items = _select_crawl_evidence(crawl_v1, max_items=4)
    pages = crawl_v1.get("pages") or []
    analyzed = crawl_v1.get("analyzed_count")
    if analyzed is None:
        analyzed = len(pages)
    discovered = crawl_v1.get("discovered_count")
    if discovered is None:
        discovered = len(crawl_v1.get("discovered_urls") or [])
    low_coverage = analyzed < 10
    confidence_display = confidence
    if low_coverage:
        confidence_display = "Medie (limitări de acoperire)" if lang == "ro" else "Medium (coverage limitations)"
    coverage_warning = (
        f"Certitudine scăzută: au fost analizate doar {analyzed} pagini (descoperite: {discovered}). "
        "Concluziile sunt limitate de accesibilitatea paginilor (ex: sitemap inaccesibil / conținut randat din JS)."
        if lang == "ro"
        else f"Low certainty: only {analyzed} pages were analyzed (discovered: {discovered}). "
             "Conclusions are limited by page accessibility (e.g., sitemap inaccessible / JS-rendered content)."
    )
    coverage_recommendation = (
        "Recomandare: activați fallback de randare (Playwright) sau corectați sitemap-ul pentru a permite analiză multi-page."
        if lang == "ro"
        else "Recommendation: enable a rendering fallback (Playwright) or fix the sitemap to allow multi-page analysis."
    )

    overview_keywords = ("noindex", "robots", "sitemap", "canonical", "meta robots")
    overview_filtered = []
    overview_technical = []
    for item in overview:
        text = str(item or "").lower()
        if any(keyword in text for keyword in overview_keywords):
            overview_technical.append(item)
        else:
            overview_filtered.append(item)

    story: list[Flowable] = []

    def _style_table(tbl: Table, rows: TableData, header: bool = False, zebra: bool = False) -> None:
        style = [
            ("FONTNAME", (0, 0), (-1, -1), body_font),
            ("FONTSIZE", (0, 0), (-1, -1), 9),
            ("GRID", (0, 0), (-1, -1), 0.2, colors.HexColor("#e5e7eb")),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("RIGHTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 6),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
        ]
        if header:
            style.append(("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#f3f4f6")))
            style.append(("FONTNAME", (0, 0), (-1, 0), bold_font))
        if zebra and len(rows) > 2:
            for i in range(1, len(rows), 2):
                style.append(("BACKGROUND", (0, i), (-1, i), colors.HexColor("#f7f7f7")))
        tbl.setStyle(TableStyle(style))

    def _card(title: str, body: list[Flowable]) -> Table:
        cell = [
            Paragraph(title, styles["CardTitle"]),
            HRFlowable(color=colors.HexColor("#e5e7eb"), thickness=0.6, width="100%"),
            Spacer(1, 4),
        ] + body
        card_table = Table([[cell]], colWidths=[160 * mm])
        card_table.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#f9fafb")),
            ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor("#e5e7eb")),
            ("LEFTPADDING", (0, 0), (-1, -1), 10),
            ("RIGHTPADDING", (0, 0), (-1, -1), 10),
            ("TOPPADDING", (0, 0), (-1, -1), 10),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
        ]))
        return card_table

    def _section_heading(title: str) -> list[Flowable]:
        return [
            Paragraph(title, styles["H2"]),
            HRFlowable(color=colors.HexColor("#e5e7eb"), thickness=0.6, width="100%"),
            Spacer(1, 4),
        ]

    cover_date = labels["date_fmt"]()

    def _decision_label() -> str:
        eligibility = audit_result.get("eligibility") if isinstance(audit_result.get("eligibility"), dict) else {}
        eligible = bool(eligibility.get("eligible", True))
        if not eligible or mode in ("broken", "no_website") or analyzed == 0:
            return "STOP"
        base_verdict = decision_verdict(audit_result, lang)
        if base_verdict in ("ATENȚIE", "CAUTION", "LIMITED", "LIMITAT"):
            return "GO WITH LIMITATIONS"
        return "GO"

    def _decision_sentence(label: str) -> str:
        if label == "GO":
            return ("Pe baza elementelor observabile și a paginilor analizate, acest website poate fi utilizat pentru campanii de ads "
                    "orientate pe conversie, fără riscuri structurale majore care să invalideze interpretarea rezultatelor.")
        if label == "GO WITH LIMITATIONS":
            return ("Website-ul poate fi utilizat pentru ads, dar există limitări structurale care pot afecta interpretarea rezultatelor. "
                    "Recomandăm rulare controlată și interpretare atentă.")
        return ("Website-ul nu permite evaluarea corectă a performanței ads orientate pe conversie în forma actuală. "
                "Orice buget cheltuit acum are risc ridicat de irosire.")

    def _agency_box_lines(label: str) -> list[str]:
        if label == "GO":
            return [
                "Ads pot fi rulate",
                "Rezultatele pot fi interpretate corect",
                "Performanța slabă NU este cauzată de blocaje structurale evidente în website",
            ]
        if label == "GO WITH LIMITATIONS":
            return [
                "Ads pot fi rulate, dar cu limitări",
                "Rezultatele pot fi distorsionate de limitările identificate",
                "Prioritizați remedierea limitărilor înainte de scalare",
            ]
        return [
            "Nu rulați ads pentru conversie acum",
            "Remediați blocajele și re-rulați evaluarea",
            "După remediere, verdictul se poate schimba",
        ]

    def _decision_marker(label: str) -> str:
        color_map = {
            "GO": "#16a34a",
            "GO WITH LIMITATIONS": "#ca8a04",
            "STOP": "#dc2626",
        }
        text_map = {
            "GO": "GO",
            "GO WITH LIMITATIONS": "GO WITH LIMITATIONS",
            "STOP": "STOP",
        }
        color = color_map.get(label, "#111827")
        text = text_map.get(label, label)
        return f'<font color="{color}">●</font> {text}'

    def _scope_lists() -> tuple[list[str], list[str]]:
        return (
            [
                "Un decision gate înainte de ads",
                "O evaluare a riscului structural pentru conversie",
                "Un instrument de protecție a bugetului și reputației agenției",
            ],
            [
                "Audit CRO complet",
                "Strategie UX",
                "Audit SEO",
                "Promisiune de rezultate",
            ],
        )

    def _sufficient_bullets() -> list[str]:
        bullets = []
        if signals.get("contact_detected"):
            bullets.append("Contact vizibil (date esențiale).")
        if signals.get("booking_detected"):
            bullets.append("Mecanism de programare/cerere prezent.")
        if signals.get("services_keywords_detected"):
            bullets.append("Servicii/ofertă clar prezentate.")
        if not bullets:
            bullets.append("Nu există suficiente elemente clare pentru conversie.")
        return bullets

    def _limiting_bullets() -> list[str]:
        items = []
        if primary_title and primary_title != "N/A":
            items.append(primary_title)
        for item in secondary:
            if len(items) >= 3:
                break
            items.append(str(item))
        return items[:3]

    def _coverage_section() -> list[Flowable]:
        attempted = crawl_v1.get("playwright_attempted") if isinstance(crawl_v1, dict) else None
        if isinstance(attempted, bool):
            render_flag = "da" if attempted else "nu"
        else:
            used_playwright = crawl_v1.get("used_playwright") if isinstance(crawl_v1, dict) else None
            render_flag = "da" if used_playwright else "nu"
        lines = [
            f"Pagini descoperite: {discovered}",
            f"Pagini analizate: {analyzed}",
            f"Randare avansată: {render_flag}",
            ("Validitatea verdictului: Verdictul este valabil pentru structura actuală a website-ului și "
             "paginile analizate la momentul rulării. Modificări majore pot invalida concluziile."),
        ]
        body = [Paragraph(line, styles["Body"]) for line in lines]
        return body

    def _appendix_pages(crawl_pages: list[dict]) -> list[Flowable]:
        appendix: list[Flowable] = []
        appendix.append(Paragraph("ANEXĂ – DOVEZI (TRANSPARENȚĂ)", styles["H1"]))
        appendix.append(Paragraph("Notă: afișare eșantionată pentru concizie.", styles["Small"]))
        appendix.append(Paragraph(
            "Această secțiune arată exemple concrete din website care susțin verdictul de mai sus.",
            styles["Small"],
        ))
        appendix.append(Paragraph(
            "Nu este necesară pentru luarea deciziei.",
            styles["Small"],
        ))
        appendix.append(Spacer(1, 6))
        max_pages = 25
        if len(crawl_pages) > max_pages:
            appendix.append(Spacer(1, 4))

        def _norm_text(text: str) -> str:
            normalized = unicodedata.normalize("NFKC", str(text or ""))
            cleaned = "".join(
                ch for ch in normalized
                if (ch in ("\n", "\t") or unicodedata.category(ch) != "Cc")
            )
            return cleaned.replace("\ufffd", "").replace("\ufffe", "").replace("\uffff", "")

        def _dedupe_segments(text: str) -> str:
            for sep in ("|", "•", "·", "/", ";", ">"):
                while sep * 2 in text:
                    text = text.replace(sep * 2, sep)
                if sep in text:
                    parts = [seg.strip() for seg in text.split(sep) if seg.strip()]
                    seen = set()
                    unique = []
                    for part in parts:
                        if part in seen:
                            continue
                        seen.add(part)
                        unique.append(part)
                    text = f" {sep} ".join(unique)
            return text

        def _is_boilerplatey_line(text: str) -> bool:
            text_l = text.lower()
            menu_terms = (
                "acasa", "despre", "servicii", "serviciu", "echipa", "contact", "blog", "programare",
                "portofoliu", "termeni", "politica", "confidentialitate", "cookie", "tarife", "preturi",
                "program", "galerie", "produse", "rezervare",
            )
            words = [w for w in text_l.split() if w.isalpha()]
            hits = sum(1 for w in words if w in menu_terms)
            return len(words) >= 6 and hits >= 3

        def _trim(text: str, max_chars: int) -> str:
            if len(text) <= max_chars:
                return text
            return text[: max_chars - 1] + "…"

        def _clean_snippet(text: str) -> str:
            s = _norm_text(text)
            while "Lucian&Partners;Lucian&Partners;" in s:
                s = s.replace("Lucian&Partners;Lucian&Partners;", "Lucian&Partners;")
            if "Lucian&Partners;" in s:
                parts = s.split("Lucian&Partners;")
                s = "Lucian&Partners;".join([parts[0], *[p for p in parts[1:] if p][:1]])
            s = " ".join(s.split())
            s = _dedupe_segments(s)
            if _is_boilerplatey_line(s):
                return ""
            email_tokens = []
            phone_tokens = []
            for token in s.split():
                if "@" in token and "." in token:
                    email_tokens.append(token)
                if sum(ch.isdigit() for ch in token) >= 6:
                    phone_tokens.append(token)
            no_contact = s
            for token in email_tokens + phone_tokens:
                no_contact = no_contact.replace(token, "")
            no_contact = " ".join(no_contact.split())
            if no_contact:
                s = no_contact
            else:
                if email_tokens or phone_tokens:
                    s = " ".join(email_tokens + phone_tokens)
            return s

        def _pick_label(url_text: str, snippet_texts: list[str]) -> str:
            url_l = (url_text or "").lower()
            combined = " ".join([url_l] + [s.lower() for s in snippet_texts])
            if any(k in combined for k in ("cerere", "oferta", "formular", "programare", "programare", "booking", "rezerv")):
                return "Mecanism de cerere / programare"
            if "contact" in combined or "@" in combined:
                return "Contact prezent"
            if any(k in url_l for k in ("servicii", "services", "service", "oferta", "offer", "pricing", "tarife", "products", "produse", "product", "shop", "store")):
                return "Servicii / ofertă descrise"
            if any(k in url_l for k in ("blog", "articol", "article", "noutati", "news")):
                return "Conținut informativ relevant"
            return "Pagină accesibilă și funcțională"

        def _truncate_text(text: str, max_chars: int = 90) -> str:
            text = _norm_text(text)
            if len(text) <= max_chars:
                return text
            return text[: max_chars - 1] + "…"

        entries = []
        for page in crawl_pages:
            if not isinstance(page, dict):
                continue
            url_line = _truncate_text(page.get("url", ""), 90)
            snippets = page.get("snippets") or []
            snippet_lines = []
            if isinstance(snippets, list) and snippets:
                for s in snippets:
                    s_clean = _clean_snippet(s)
                    if not s_clean or s_clean in ("•", "-", "—"):
                        continue
                    s_stripped = s_clean.lstrip("•-—").strip()
                    if not s_stripped:
                        continue
                    snippet_lines.append(_trim(s_clean, 170))
                    break
            label = _pick_label(url_line, snippet_lines)
            entries.append({
                "url": url_line or "-",
                "label": label,
                "snippet": snippet_lines[0] if snippet_lines else "",
            })

        priority = {
            "Mecanism de cerere / programare": 1,
            "Contact prezent": 2,
            "Servicii / ofertă descrise": 3,
            "Conținut informativ relevant": 4,
            "Pagină accesibilă și funcțională": 5,
        }
        buckets = {k: [] for k in priority}
        for entry in entries:
            buckets.get(entry["label"], buckets["Pagină accesibilă și funcțională"]).append(entry)

        label5_cap = 4
        count = 0
        for label in sorted(priority, key=priority.get):
            for entry in buckets[label]:
                if count >= max_pages:
                    break
                if label == "Pagină accesibilă și funcțională" and label5_cap <= 0:
                    continue
                appendix.append(Paragraph(f"URL: {entry['url']}", styles["Small"]))
                appendix.append(Spacer(1, 1))
                appendix.append(Paragraph(f"Dovadă: {entry['label']}", styles["Small"]))
                appendix.append(Spacer(1, 1))
                if entry["snippet"]:
                    appendix.append(Paragraph(f"• \"{entry['snippet']}\"", styles["Small"]))
                    appendix.append(Spacer(1, 1))
                appendix.append(Spacer(1, 3))
                count += 1
                if label == "Pagină accesibilă și funcțională":
                    label5_cap -= 1
        return appendix

    story: list[Flowable] = []

    cover_block = [
        Paragraph("SCOPE", styles["H1"]),
        Paragraph("Ads Readiness Decision Report", styles["H2"]),
        Paragraph("Evaluare deterministă pentru pornirea campaniilor de conversie", styles["Body"]),
        Spacer(1, 8),
        Paragraph(f"Website auditat: {url or '-'}", styles["Body"]),
        Paragraph(f"Data: {cover_date}", styles["Body"]),
        Paragraph(f"Tool version: {display_tool_version}", styles["Body"]),
        Spacer(1, 10),
        Paragraph("Client-safe • Determinist • Evidence-based", styles["Small"]),
    ]
    story.append(KeepTogether(cover_block))
    story.append(PageBreak())

    decision = _decision_label()
    story.append(Paragraph("ADS DECISION", styles["H1"]))
    story.append(Spacer(1, 6))
    story.append(Paragraph(_decision_marker(decision), styles["H2"]))
    story.append(Spacer(1, 6))
    story.append(Paragraph(_decision_sentence(decision), styles["Body"]))
    story.append(Spacer(1, 8))
    story.append(_card("Ce înseamnă asta pentru agenție", [
        Paragraph("<br/>".join([f"• {s}" for s in _agency_box_lines(decision)]), styles["Body"])
    ]))
    story.append(Spacer(1, 12))

    story.append(Paragraph("SCOP & LIMITĂRI", styles["H1"]))
    story.append(Spacer(1, 6))
    yes_list, no_list = _scope_lists()
    story.append(Paragraph("Ce este acest document", styles["H2"]))
    story.append(Paragraph("<br/>".join([f"• {s}" for s in yes_list]), styles["Body"]))
    story.append(Spacer(1, 6))
    story.append(Paragraph("Ce NU este acest document", styles["H2"]))
    story.append(Paragraph("<br/>".join([f"• {s}" for s in no_list]), styles["Body"]))
    story.append(Spacer(1, 12))

    story.append(Paragraph("MOTIVAREA DECIZIEI", styles["H1"]))
    story.append(Spacer(1, 6))
    story.append(Paragraph("Ce este suficient pentru ads", styles["H2"]))
    story.append(Paragraph("<br/>".join([f"• {s}" for s in _sufficient_bullets()]), styles["Body"]))
    story.append(Spacer(1, 6))
    story.append(Paragraph("Ce limitează conversia (fără să o invalideze)", styles["H2"]))
    story.append(Paragraph("Nu au fost identificate limitări structurale evidente.", styles["Body"]))
    story.append(Spacer(1, 6))
    story.append(Paragraph("Ce NU blochează decizia", styles["H2"]))
    story.append(Paragraph("<br/>".join([
        "• Branding",
        "• SEO",
        "• Fine-tuning de copy",
        "• Lipsa experimentelor CRO",
    ]), styles["Body"]))
    story.append(Spacer(1, 12))

    story.append(Paragraph("IMPLICAȚII DIRECTE PENTRU ADS", styles["H1"]))
    story.append(Spacer(1, 6))
    story.append(Paragraph("Ce poți face ACUM", styles["H2"]))
    story.append(Paragraph("<br/>".join([
        "• Rula campanii de validare",
        "• Testa ofertă, mesaje și audiențe",
        "• Măsura conversii primare (lead / contact)",
    ]), styles["Body"]))
    story.append(Spacer(1, 6))
    story.append(Paragraph("Ce NU poți concluziona corect", styles["H2"]))
    story.append(Paragraph("<br/>".join([
        "• Rata maximă posibilă de conversie",
        "• Impactul optimizărilor fine de UX",
        "• Performanță long-term fără iterații",
    ]), styles["Body"]))
    story.append(Spacer(1, 12))

    story.append(Paragraph("NEXT STEPS", styles["H1"]))
    story.append(Spacer(1, 6))
    story.append(Paragraph("1. Rulați ads cu buget controlat pentru validare", styles["Body"]))
    story.append(Paragraph("2. Observați comportamentul de conversie", styles["Body"]))
    story.append(Paragraph("3. Dacă performanța este sub așteptări, optimizați CTA și elementele de încredere", styles["Body"]))
    story.append(Spacer(1, 10))

    story.append(Paragraph("COVERAGE & VALIDITATEA DECIZIEI", styles["H1"]))
    story.append(Spacer(1, 6))
    story.extend(_coverage_section())
    story.append(Spacer(1, 12))

    evidence_pack = audit_result.get("evidence_pack") or {}
    crawl_pages = evidence_pack.get("crawl_pages") if isinstance(evidence_pack, dict) else []
    if isinstance(crawl_pages, list) and crawl_pages:
        story.append(PageBreak())
        story.extend(_appendix_pages(crawl_pages))

    story.append(Spacer(1, 6))
    def _audited_domain(raw_url: str) -> str:
        try:
            parsed = urlparse(raw_url)
            if parsed.netloc:
                return parsed.netloc
        except Exception:
            pass
        return str(raw_url or "").split("/")[0]

    audited_domain = _audited_domain(url)

    def draw_header_footer(canvas, doc_obj):
        canvas.saveState()
        width, height = A4
        left = doc_obj.leftMargin
        right = width - doc_obj.rightMargin
        header_y = height - 12 * mm
        footer_y = 10 * mm

        canvas.setFont(body_font, 8)
        canvas.setFillColor(colors.HexColor("#6b7280"))
        header_line = f"{audited_domain} • {cover_date}" if audited_domain else cover_date
        canvas.drawString(left, header_y, header_line)

        canvas.setStrokeColor(colors.HexColor("#e5e7eb"))
        canvas.setLineWidth(0.5)
        canvas.line(left, footer_y + 4 * mm, right, footer_y + 4 * mm)
        canvas.drawRightString(right, footer_y, f"Pagina {canvas.getPageNumber()}")
        canvas.restoreState()

    doc.build(story, onFirstPage=draw_header_footer, onLaterPages=draw_header_footer)
    return out_path
