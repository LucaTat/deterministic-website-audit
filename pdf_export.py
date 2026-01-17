# pdf_export.py
import os
import datetime as dt
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
    client_narrative = _preferred_narrative(audit_result)
    findings = audit_result.get("findings", []) or []
    overview = client_narrative.get("overview", []) or []
    primary = client_narrative.get("primary_issue", {}) or {}
    secondary = client_narrative.get("secondary_issues", []) or []
    plan = client_narrative.get("plan", []) or []
    confidence = client_narrative.get("confidence", "") or ""
    p_title = primary.get("title", "")
    primary_title = p_title.strip() if isinstance(p_title, str) and p_title.strip() else "N/A"

    score = int(signals.get("score", 0) or 0)
    if mode in ("no_website", "broken"):
        score = 0

    story = []

    def _style_table(tbl: Table, rows: list, header: bool = False, zebra: bool = False) -> None:
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

    def _card(title: str, body: list) -> Table:
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

    def _section_heading(title: str) -> list:
        return [
            Paragraph(title, styles["H2"]),
            HRFlowable(color=colors.HexColor("#e5e7eb"), thickness=0.6, width="100%"),
            Spacer(1, 4),
        ]

    summary_items = []
    for f in findings:
        title = f.get("title_ro") if lang == "ro" else f.get("title_en")
        if title and title not in summary_items:
            summary_items.append(title)
        if len(summary_items) >= 3:
            break
    summary_html = "<br/>".join([f"• {s}" for s in summary_items[:3]]) if summary_items else "N/A"
    primary_text = primary_title.lower() if isinstance(primary_title, str) else ""
    no_major_issues = (
        ("nu am detectat probleme majore" in primary_text)
        or ("no major issues detected" in primary_text)
        or ("validare pozitiv" in primary_text)
        or ("positive validation" in primary_text)
    )
    expert_context = (
        (
            ("Primary findings highlight optimization opportunities to improve clarity and response rates.<br/>"
             if no_major_issues else
             "Primary findings point to a bottleneck that shapes how visitors decide and act.<br/>")
            + "Resolving the top issue typically improves clarity, reduces friction, and raises response rates.<br/>"
            + "This interpretation is based on observable page elements, not internal business data.<br/>"
            + f"This context refers to the primary issue: {primary_title}."
        )
        if lang == "en"
        else (
            ("Constatările principale indică oportunități de optimizare pentru claritate și răspuns.<br/>"
             if no_major_issues else
             "Constatările principale indică un blocaj care influențează decizia și acțiunea vizitatorilor.<br/>")
            + "Rezolvarea problemei de top crește claritatea, reduce fricțiunea și îmbunătățește răspunsul.<br/>"
            + "Interpretarea se bazează pe elemente observabile, nu pe date interne de business.<br/>"
            + f"Acest context se referă la problema principală: {primary_title}."
        )
    )

    cover_status = "OK" if mode == "ok" else "BROKEN"
    cover_status_display = labels["cover_status_ok"] if mode == "ok" else labels["cover_status_issues"]
    cover_date = labels["date_fmt"]()
    campaign = (audit_result.get("campaign") or "").strip() or "-"

    status_table = Table(
        [[Paragraph(
            f'{cover_status_display}<br/><font size="8" color="#6b7280">'
            f'{labels["cover_status_raw_label"]}: {cover_status}</font><br/>'
            f'<font size="7" color="#6b7280">{labels["cover_status_note"]}</font>',
            styles["Body"],
        )]],
        colWidths=[45 * mm],
        hAlign="LEFT",
    )
    status_table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#f9fafb")),
        ("TEXTCOLOR", (0, 0), (-1, -1), colors.HexColor("#111827")),
        ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor("#d1d5db")),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))
    cover_meta = [
        [Paragraph(f'{labels["cover_audited_domain"]}:', styles["Small"]), Paragraph(url or "-", styles["Body"])],
        [Paragraph(f'{labels["date"]}:', styles["Small"]), Paragraph(cover_date, styles["Body"])],
        [Paragraph(f'{labels["cover_campaign"]}:', styles["Small"]), Paragraph(campaign, styles["Body"])],
        [Paragraph(f'{labels["status"]}:', styles["Small"]), status_table],
    ]
    cover_meta_table = Table(cover_meta, colWidths=[35 * mm, 120 * mm], hAlign="LEFT")
    cover_meta_table.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
    ]))
    cover_footer = Table(
        [[Paragraph(url or "-", styles["Small"]), Paragraph(cover_date, styles["Small"])]],
        colWidths=[80 * mm, 75 * mm],
        hAlign="LEFT",
    )
    cover_footer.setStyle(TableStyle([
        ("LINEABOVE", (0, 0), (-1, -1), 0.5, colors.HexColor("#e5e7eb")),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
        ("ALIGN", (0, 0), (0, 0), "LEFT"),
        ("ALIGN", (1, 0), (1, 0), "RIGHT"),
    ]))
    verdict_label = decision_verdict(audit_result, lang)
    verdict_prefix = "VERDICT DECIZIONAL: " if lang == "ro" else "DECISION VERDICT: "
    verdict_line = f"{verdict_prefix}{verdict_label}"
    scorecard = ScorecardFlowable(audit_result, lang)
    cover_block = [
        Paragraph(labels["cover_title"], styles["H1"]),
        Paragraph(labels["cover_subtitle"], styles["Small"]),
        Paragraph(labels["cover_tagline"], styles["Small"]),
        Spacer(1, 6),
        Paragraph(verdict_line, styles["Verdict"]),
        Spacer(1, 6),
        scorecard,
        Spacer(1, 10),
        HRFlowable(color=colors.HexColor("#e5e7eb"), thickness=0.6, width="100%"),
        Spacer(1, 10),
        cover_meta_table,
        Spacer(1, 12),
        Paragraph(labels["cover_executive_summary"], styles["H2"]),
        Paragraph(summary_html, styles["Body"]),
        Spacer(1, 6),
        Paragraph(labels["cover_expert_interpretation"], styles["H2"]),
        Paragraph(expert_context, styles["Body"]),
        Spacer(1, 8),
        # Removed cover "next steps" to avoid duplicate sections and orphaned bullets.
        cover_footer,
    ]
    # Keep the top spacer inside KeepTogether to avoid a blank first page.
    story.append(KeepTogether([Spacer(1, 55 * mm)] + cover_block))
    story.append(PageBreak())

    client_name = (audit_result.get("client_name") or "").strip()
    title = labels["title"] + (f" - {client_name}" if client_name else "")
    story.append(Paragraph(title, styles["H1"]))
    story.append(Spacer(1, 6))

    meta = [
        [labels["date"], labels["date_fmt"]()],
        [labels["website"], url],
        [labels["status"], labels["status_map"].get(mode, mode)],
        [labels["score"], f"{score}/100"],
    ]
    meta_table = Table(meta, colWidths=[55 * mm, 117 * mm], hAlign="LEFT")
    _style_table(meta_table, meta, header=False, zebra=False)
    story.append(meta_table)

    story.append(Spacer(1, 10))
    story.append(HRFlowable(color=colors.HexColor("#e5e7eb"), thickness=1, width="100%"))
    story.append(Spacer(1, 10))

    overview_body = [Paragraph("<br/>".join(overview) if overview else "N/A", styles["Body"])]
    if mode == "broken":
        reason = signals.get("reason", "")
        label = humanize_fetch_error_label(reason, lang)
        if label:
            prefix = "Cauză probabilă: " if lang == "ro" else "Probable cause: "
            story.append(Spacer(1, 4))
            overview_body.append(Paragraph(f"{prefix}{label}", styles["Small"]))
    story.append(_card(labels["overview"], overview_body))
    story.append(Spacer(1, 12))

    scope_note = (
        "This is a decision and prioritization audit based on observable page elements. "
        "It is not a full UX/CRO strategy, research program, or conversion experiment plan."
        if lang == "en"
        else "Acesta este un audit de decizie și prioritizare bazat pe elemente observabile. "
             "Nu este o strategie completă de UX/CRO, cercetare sau plan de experimente de conversie."
    )
    for flow in _section_heading(labels["scope_limits"]):
        story.append(flow)
    story.append(Paragraph(scope_note, styles["Body"]))
    story.append(Spacer(1, 10))

    p_impact = primary.get("impact", "")
    primary_lines = []
    if p_title:
        primary_lines.append(f"<b>{p_title}</b>")
    if p_impact:
        primary_lines.append(p_impact)
    story.append(_card(labels["primary"], [Paragraph("<br/>".join(primary_lines) if primary_lines else "N/A", styles["Body"])]))
    story.append(Spacer(1, 12))

    if secondary:
        for flow in _section_heading(labels["secondary"]):
            story.append(flow)
        sec_html = "<br/>".join([f"• {s}" for s in secondary])
        story.append(Paragraph(sec_html, styles["Body"]))
        story.append(Spacer(1, 10))

    plan_html = "<br/>".join([f"• {s}" for s in plan]) if plan else "N/A"
    story.append(_card(labels["plan"], [Paragraph(plan_html, styles["Body"])]))
    story.append(Spacer(1, 12))

    if confidence:
        for flow in _section_heading(labels["confidence"]):
            story.append(flow)
        conf_note = (
            "Refers to confidence in the assessment and impact estimate, not brand trust."
            if lang == "en"
            else "Se referă la certitudinea evaluării și impactului estimat, nu la încrederea în brand."
        )
        story.append(Paragraph(conf_note, styles["Small"]))
        story.append(Paragraph(confidence, styles["Body"]))
        story.append(Spacer(1, 10))

    quickwins_body = []
    if lang == "ro":
        quickwins_body.append(Paragraph("Aceste îmbunătățiri pot fi implementate rapid, fără redesign complet.", styles["Small"]))
        quickwins_body.append(Spacer(1, 4))
    wins = quick_wins_ro(mode, signals) if lang == "ro" else quick_wins_en(mode, signals)
    if no_major_issues:
        wins = [
            "Clarificați CTA-ul principal: un singur mesaj dominant, vizibil imediat.",
            "Reduceți fricțiunea pe mobil: spații, butoane, viteză și formular simplu.",
            "Adăugați elemente de încredere lângă CTA: recenzii, certificări, rezultate."
        ] if lang == "ro" else [
            "Clarify the primary CTA: one dominant message, visible immediately.",
            "Reduce mobile friction: spacing, button size, speed, and a short form.",
            "Add trust elements near the CTA: reviews, certifications, outcomes."
        ]
    wins_html = "<br/>".join([f"• {w}" for w in wins]) if wins else "N/A"
    quickwins_body.append(Paragraph(wins_html, styles["Body"]))
    story.append(_card(labels["quickwins"], quickwins_body))
    story.append(Spacer(1, 12))

    ai_advisory = audit_result.get("ai_advisory") or {}
    if isinstance(ai_advisory, dict) and ai_advisory:
        ai_status = (ai_advisory.get("ai_status") or "").strip()
        if ai_status == "fallback" and no_major_issues:
            pass
        elif ai_status in ("ok", "fallback"):
            for flow in _section_heading(labels["ai_advisory"]):
                story.append(flow)
            story.append(Paragraph(f"<b>{labels['ai_status']}:</b> {ai_status}", styles["Body"]))
            if ai_status == "fallback":
                story.append(Paragraph(labels["ai_fallback_note"], styles["Body"]))
            summary = ai_advisory.get("executive_summary") or ""
            if summary:
                story.append(Paragraph(f"<b>{labels['ai_summary']}:</b> {summary}", styles["Body"]))

            priorities = ai_advisory.get("priorities") or []
            if isinstance(priorities, list) and priorities:
                story.append(Spacer(1, 6))
                for flow in _section_heading(labels["ai_priorities"]):
                    story.append(flow)

                findings_by_id = {f.get("id"): f for f in findings if f.get("id")}
                level_labels = labels["ai_levels"]
                for group in priorities:
                    if not isinstance(group, dict):
                        continue
                    level = group.get("level")
                    ids = group.get("finding_ids") or []
                    if level not in level_labels or not isinstance(ids, list):
                        continue
                    items = []
                    for fid in ids:
                        f = findings_by_id.get(fid)
                        if not f:
                            continue
                        title = f.get("title_ro") if lang == "ro" else f.get("title_en")
                        if title:
                            items.append(f"• {title}")
                    if items:
                        story.append(Paragraph(level_labels[level], styles["Body"]))
                        story.append(Paragraph("<br/>".join(items), styles["Body"]))
                        story.append(Spacer(1, 4))

            disclaimer = ai_advisory.get("disclaimer") or labels["ai_disclaimer"]
            if disclaimer:
                story.append(Paragraph(disclaimer, styles["Small"]))
            story.append(Spacer(1, 10))

    if mode == "ok":
        rows = [
            [labels["booking"], labels["yes"] if signals.get("booking_detected") else labels["no"]],
            [labels["contact"], labels["yes"] if signals.get("contact_detected") else labels["no"]],
            [labels["services"], labels["yes"] if signals.get("services_keywords_detected") else labels["no"]],
            [labels["pricing"], labels["yes"] if signals.get("pricing_keywords_detected") else labels["no"]],
        ]
        checks = Table(rows, colWidths=[80 * mm, 92 * mm], hAlign="LEFT")
        _style_table(checks, rows, header=False, zebra=False)
        story.append(KeepTogether(_section_heading(labels["checks"]) + [checks]))

        social_findings = [f for f in findings if (f or {}).get("category") == "social"]
        story.append(Spacer(1, 10))
        if social_findings:
            rows = [[labels["severity"], labels["finding_col"], labels["recommendation_col"]]]
            for f in social_findings:
                sev = (f.get("severity") or "").capitalize()
                title = f.get("title_ro") if lang == "ro" else f.get("title_en")
                rec = f.get("recommendation_ro") if lang == "ro" else f.get("recommendation_en")
                if isinstance(title, str):
                    title = title.replace("Twitter/X", "Twitter")
                if isinstance(rec, str):
                    rec = rec.replace("Twitter/X", "Twitter")

                rows.append([
                    Paragraph(sev, styles["Meta"]),
                    Paragraph(title or "", styles["Body"]),
                    Paragraph(rec or "", styles["Body"]),
                ])

            tbl = Table(rows, colWidths=[26 * mm, 76 * mm, 72 * mm], hAlign="LEFT")
            _style_table(tbl, rows, header=True, zebra=True)
            social_block = _section_heading(labels["social_findings"]) + [tbl]
        else:
            note = (
                "Nu au fost detectate semnale sociale clare."
                if lang == "ro"
                else "No clear social signals were detected."
            )
            social_block = _section_heading(labels["social_findings"]) + [Paragraph(note, styles["Body"])]
        story.append(KeepTogether(social_block))

        share_meta_findings = [f for f in findings if (f or {}).get("category") == "share_meta"]
        if share_meta_findings:
            story.append(Spacer(1, 10))
            rows = [[labels["severity"], labels["finding_col"], labels["recommendation_col"]]]
            for f in share_meta_findings:
                sev = (f.get("severity") or "").capitalize()
                title = f.get("title_ro") if lang == "ro" else f.get("title_en")
                rec = f.get("recommendation_ro") if lang == "ro" else f.get("recommendation_en")
                if isinstance(title, str):
                    title = title.replace("Twitter/X", "Twitter")
                if isinstance(rec, str):
                    rec = rec.replace("Twitter/X", "Twitter")

                rows.append([
                    Paragraph(sev, styles["Meta"]),
                    Paragraph(title or "", styles["Body"]),
                    Paragraph(rec or "", styles["Body"]),
                ])

            tbl = Table(rows, colWidths=[26 * mm, 76 * mm, 72 * mm], hAlign="LEFT")
            _style_table(tbl, rows, header=True, zebra=True)
            story.append(KeepTogether(_section_heading(labels["share_meta_findings"]) + [tbl]))

        index_findings = [f for f in findings if (f or {}).get("category") == "indexability_technical_access"]
        story.append(Spacer(1, 10))
        if lang == "ro":
            story.append(Paragraph(
                "Următoarele verificări susțin stabilitatea și accesibilitatea website-ului, dar nu reprezintă probleme directe de conversie.",
                styles["Small"],
            ))
        index_block = _section_heading(labels["indexability_findings"])
        if not index_findings:
            no_issues = (
                "No issues detected in this section based on the checks performed."
                if lang != "ro"
                else "Nu au fost detectate probleme în această secțiune pe baza verificărilor efectuate."
            )
            index_block.append(Paragraph(no_issues, styles["Body"]))
        else:
            rows = [[labels["severity"], labels["finding_col"], labels["recommendation_col"]]]
            for f in index_findings:
                sev = (f.get("severity") or "").capitalize()
                title = f.get("title_ro") if lang == "ro" else f.get("title_en")
                rec = f.get("recommendation_ro") if lang == "ro" else f.get("recommendation_en")

                rows.append([
                    Paragraph(sev, styles["Meta"]),
                    Paragraph(title or "", styles["Body"]),
                    Paragraph(rec or "", styles["Body"]),
                ])

            tbl = Table(rows, colWidths=[26 * mm, 76 * mm, 72 * mm], hAlign="LEFT")
            _style_table(tbl, rows, header=True, zebra=True)
            index_block.append(tbl)
        story.append(KeepTogether(index_block))

    conv_findings = [f for f in findings if (f or {}).get("category") == "conversion_loss"]
    if conv_findings:
        story.append(Spacer(1, 10))
        def pct_range(ev: dict) -> str:
            try:
                lo = float(ev.get("impact_pct_low", 0) or 0)
                hi = float(ev.get("impact_pct_high", 0) or 0)
                return f"{round(lo*100)}%–{round(hi*100)}%"
            except Exception:
                return ""

        impact_note = (
            "Estimările sunt orientative și reflectă intervale de impact observate frecvent atunci când elemente similare "
            "lipsesc sau sunt optimizate în site-uri comerciale comparabile. Nu reprezintă o predicție bazată pe datele "
            "interne ale business-ului."
        )

        rows = [[labels["severity"], labels["finding_col"], labels["estimate_col"], labels["confidence_col"]]]
        for f in conv_findings:
            sev = (f.get("severity") or "").capitalize()
            title = f.get("title_ro") if lang == "ro" else f.get("title_en")
            ev = f.get("evidence", {}) or {}
            est = pct_range(ev)
            conf = ev.get("confidence") or ""
            if lang == "ro" and conf == "High" and est == "0%–0%" and isinstance(title, str) and "Nu am detectat probleme majore" in title:
                conf = "Scăzută"
            rows.append([
                Paragraph(sev, styles["Meta"]),
                Paragraph(title or "", styles["Body"]),
                Paragraph(est, styles["Body"]),
                Paragraph(str(conf), styles["Body"]),
            ])

        tbl = Table(rows, colWidths=[24 * mm, 76 * mm, 32 * mm, 42 * mm], hAlign="LEFT")
        _style_table(tbl, rows, header=True, zebra=True)
        conv_block = _section_heading(labels["conversion_loss_findings"])
        if lang == "ro":
            conv_block.append(Paragraph(impact_note, styles["Small"]))
        conv_block.append(tbl)
        story.append(KeepTogether(conv_block))

    if mode == "broken":
        reason = signals.get("reason", "")
        if reason:
            story.append(Spacer(1, 10))
            for flow in _section_heading(labels["error_details"]):
                story.append(flow)
            safe_reason = (
                "Website-ul nu a putut fi accesat în timpul auditului. Detaliile tehnice sunt disponibile la cerere."
                if lang == "ro"
                else "The website could not be accessed during the audit. Technical details are available on request."
            )
            story.append(Paragraph(safe_reason, styles["Body"]))

    story.append(Spacer(1, 12))
    story.append(HRFlowable(color=colors.HexColor("#e5e7eb"), thickness=1, width="100%"))

    story.append(Spacer(1, 10))
    next_steps_block = [
        Paragraph("Next steps" if lang == "en" else "Pașii următori", styles["CardTitle"]),
        HRFlowable(color=colors.HexColor("#e5e7eb"), thickness=0.6, width="100%"),
        Spacer(1, 4),
    ]
    primary_action = p_title if isinstance(p_title, str) and p_title.strip() else ""
    if not primary_action:
        primary_action = (
            "address the primary issue highlighted in this report"
            if lang == "en"
            else "rezolvați problema principală evidențiată în acest raport"
        )
    action_prefix = "If you do one thing now:" if lang == "en" else "Dacă faceți un singur lucru acum:"
    action_line = f"{action_prefix} {primary_action}"
    if lang == "ro" and no_major_issues:
        action_line = "Dacă faceți un singur lucru acum: Mențineți structura actuală și validați performanța prin introducerea controlată de trafic."
    if lang == "en" and isinstance(primary_action, str) and primary_action.startswith("No major issues detected"):
        action_line = "If you do one thing now: Keep the current structure, but emphasize the primary CTA to maximize conversions."
    if not action_line.endswith("."):
        action_line += "."
    next_steps_block.append(Paragraph(action_line, styles["Body"]))

    if lang == "en":
        cta_text = (
            "If you want support implementing these improvements, this audit can be used as a clear roadmap.<br/>"
            "We would address the primary issue first, then the remaining items that directly affect inquiries and bookings."
        )
    else:
        cta_text = (
            "Dacă doriți sprijin pentru implementarea acestor îmbunătățiri, acest audit poate fi folosit ca un plan clar de lucru.<br/>"
            "Am aborda mai întâi problema principală, apoi punctele rămase care influențează direct cererile și programările."
        )

    next_steps_block.append(Paragraph(cta_text, styles["Body"]))
    scope_note = client_narrative.get("scope_note", "") or ""
    if scope_note:
        next_steps_block.append(Spacer(1, 8))
        next_steps_block.append(Paragraph(scope_note, styles["Small"]))
    next_steps_card = Table([[next_steps_block]], colWidths=[160 * mm])
    next_steps_card.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#f9fafb")),
        ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor("#e5e7eb")),
        ("LEFTPADDING", (0, 0), (-1, -1), 10),
        ("RIGHTPADDING", (0, 0), (-1, -1), 10),
        ("TOPPADDING", (0, 0), (-1, -1), 10),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 10),
    ]))
    story.append(KeepTogether([next_steps_card]))

    story.append(Spacer(1, 6))
    story.append(Paragraph(f"Tool version: {tool_version}", styles["Small"]))
    story.append(Paragraph(labels["note"], styles["Small"]))

    if mode == "broken":
        story.append(PageBreak())
        if lang == "ro":
            story.append(Paragraph("Clarificare: rezultat BROKEN", styles["H1"]))
            story.append(Spacer(1, 10))
            options = [
                "BROKEN nu înseamnă că site-ul e stricat; înseamnă că verificarea automată nu a fost completă sau reproductibilă.",
                "Poate apărea dacă site-ul blochează accesul automat (WAF/anti-bot/rate limit).",
                "Ce poți face: (1) păstrezi raportul ca semnal valid, (2) permiți temporar acces pentru verificare și rerulăm.",
            ]
            story.append(ListFlowable(
                [Paragraph(item, styles["Body"]) for item in options],
                bulletType="bullet",
                leftIndent=12,
            ))
            story.append(Spacer(1, 6))
            story.append(Paragraph("Rezultat BROKEN este o constatare validă, nu o eroare de livrare.", styles["Small"]))
        else:
            story.append(Paragraph("Clarification: BROKEN result", styles["H1"]))
            story.append(Spacer(1, 10))
            options = [
                "BROKEN does not mean the site is broken; it means the automated check was not complete or reproducible.",
                "It can happen if the site blocks automated access (WAF/anti-bot/rate limit).",
                "What you can do: (1) keep the report as a valid signal, (2) allow temporary access and rerun.",
            ]
            story.append(ListFlowable(
                [Paragraph(item, styles["Body"]) for item in options],
                bulletType="bullet",
                leftIndent=12,
            ))
            story.append(Spacer(1, 6))
            story.append(Paragraph("A BROKEN result is a valid finding, not a delivery error.", styles["Small"]))

    # Removed recommended next steps block to prevent duplicate sections.

    def draw_header_footer(canvas, doc_obj):
        canvas.saveState()
        width, height = A4
        left = doc_obj.leftMargin
        right = width - doc_obj.rightMargin
        header_y = height - 12 * mm
        footer_y = 10 * mm

        canvas.setFont(body_font, 8)
        canvas.setFillColor(colors.HexColor("#6b7280"))
        canvas.drawString(left, header_y, url or "")
        header_right = campaign if campaign != "-" else cover_date
        canvas.drawRightString(right, header_y, header_right)

        canvas.setStrokeColor(colors.HexColor("#e5e7eb"))
        canvas.setLineWidth(0.5)
        canvas.line(left, footer_y + 4 * mm, right, footer_y + 4 * mm)
        canvas.drawString(left, footer_y, f"Deterministic Website Audit • v{tool_version}")
        canvas.drawRightString(right, footer_y, f"Pagina {canvas.getPageNumber()}")
        canvas.restoreState()

    doc.build(story, onFirstPage=draw_header_footer, onLaterPages=draw_header_footer)
    return out_path
