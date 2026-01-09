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
)
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont

AGENCY_NAME = "Digital Audit Studio"
AGENCY_CONTACT = "contact@digitalaudit.ro"


def _register_font() -> str:
    import os
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont

    here = os.path.dirname(os.path.abspath(__file__))
    font_path = os.path.join(here, "fonts", "DejaVuSans.ttf")

    if os.path.exists(font_path):
        pdfmetrics.registerFont(TTFont("AuditFont", font_path))
        return "AuditFont"

    return "Helvetica"




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
        wins.append("Add pricing ranges or starting prices (“from…”, packages) to reduce hesitation and increase trust.")
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


def export_audit_pdf(audit_result: dict, out_path: str, tool_version: str = "unknown") -> str:
    font = _register_font()

    if not out_path.lower().endswith(".pdf"):
        out_path += ".pdf"

    lang = (audit_result.get("lang") or "en").lower().strip()
    if lang not in ("en", "ro"):
        lang = "en"

    labels = {
        "en": {
            "title": "Website Audit",
            "date": "Date",
            "website": "Website",
            "status": "Status",
            "score": "Score",
            "overview": "Overview",
            "primary": "Primary issue",
            "secondary": "Secondary issues",
            "plan": "Recommended plan",
            "confidence": "Confidence",
            "quickwins": "Top 3 quick wins",
            "checks": "Basic checks",
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
            "confidence_col": "Confidence",
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
            "date": "Data",
            "website": "Website",
            "status": "Status",
            "score": "Scor",
            "overview": "Prezentare generală",
            "primary": "Problema principală",
            "secondary": "Probleme secundare",
            "plan": "Plan recomandat",
            "confidence": "Încredere",
            "quickwins": "Top 3 „Quick Wins”",
            "checks": "Verificări de bază",
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
            "confidence_col": "Încredere",
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
            },"audit_type": "Tip audit",
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

    font_name = _register_font()
    styles = getSampleStyleSheet()

    # Force all default styles to use the registered font
    for s in styles.byName.values():
        s.fontName = font_name

    # Custom styles must also use the same font_name
    styles.add(ParagraphStyle(
        name="H1",
        fontName=font_name,
        fontSize=18,
        leading=22,
        textColor=colors.HexColor("#111827"),
    ))

    styles.add(ParagraphStyle(
        name="H2",
        fontName=font_name,
        fontSize=13,
        leading=16,
        textColor=colors.HexColor("#111827"),
        spaceBefore=12,
    ))

    styles.add(ParagraphStyle(
        name="Body",
        fontName=font_name,
        fontSize=10,
        leading=15,
        textColor=colors.HexColor("#111827"),
    ))

    styles.add(ParagraphStyle(
        name="Small",
        fontName=font_name,
        fontSize=9,
        leading=13,
        textColor=colors.HexColor("#374151"),
    ))

    url = audit_result.get("url", "")
    mode = audit_result.get("mode", "ok")
    signals = audit_result.get("signals", {}) or {}
    client_narrative = audit_result.get("client_narrative", {}) or {}
    findings = audit_result.get("findings", []) or []

    score = int(signals.get("score", 0) or 0)
    if mode in ("no_website", "broken"):
        score = 0

    story = []

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
    meta_table = Table(meta, colWidths=[35 * mm, 137 * mm], hAlign="LEFT")
    meta_table.setStyle(TableStyle([
        ("FONTNAME", (0, 0), (-1, -1), font),
        ("FONTSIZE", (0, 0), (-1, -1), 9),
        ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#e5e7eb")),
        ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#f9fafb")),
        ("LEFTPADDING", (0, 0), (-1, -1), 6),
        ("RIGHTPADDING", (0, 0), (-1, -1), 6),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
    ]))
    story.append(meta_table)

    story.append(Spacer(1, 10))
    story.append(HRFlowable(color=colors.HexColor("#e5e7eb"), thickness=1, width="100%"))
    story.append(Spacer(1, 10))

    overview = client_narrative.get("overview", []) or []
    primary = client_narrative.get("primary_issue", {}) or {}
    secondary = client_narrative.get("secondary_issues", []) or []
    plan = client_narrative.get("plan", []) or []
    confidence = client_narrative.get("confidence", "") or ""

    story.append(Paragraph(labels["overview"], styles["H2"]))
    story.append(Paragraph("<br/>".join(overview) if overview else "N/A", styles["Body"]))
    story.append(Spacer(1, 10))

    story.append(Paragraph(labels["primary"], styles["H2"]))
    p_title = primary.get("title", "")
    p_impact = primary.get("impact", "")
    primary_lines = []
    if p_title:
        primary_lines.append(f"<b>{p_title}</b>")
    if p_impact:
        primary_lines.append(p_impact)
    story.append(Paragraph("<br/>".join(primary_lines) if primary_lines else "N/A", styles["Body"]))
    story.append(Spacer(1, 10))

    if secondary:
        story.append(Paragraph(labels["secondary"], styles["H2"]))
        sec_html = "<br/>".join([f"• {s}" for s in secondary])
        story.append(Paragraph(sec_html, styles["Body"]))
        story.append(Spacer(1, 10))

    story.append(Paragraph(labels["plan"], styles["H2"]))
    plan_html = "<br/>".join([f"• {s}" for s in plan]) if plan else "N/A"
    story.append(Paragraph(plan_html, styles["Body"]))
    story.append(Spacer(1, 10))

    if confidence:
        story.append(Paragraph(labels["confidence"], styles["H2"]))
        story.append(Paragraph(confidence, styles["Body"]))
        story.append(Spacer(1, 10))

    story.append(Paragraph(labels["quickwins"], styles["H2"]))
    wins = quick_wins_ro(mode, signals) if lang == "ro" else quick_wins_en(mode, signals)
    wins_html = "<br/>".join([f"• {w}" for w in wins]) if wins else "N/A"
    story.append(Paragraph(wins_html, styles["Body"]))
    story.append(Spacer(1, 10))

    ai_advisory = audit_result.get("ai_advisory") or {}
    if isinstance(ai_advisory, dict) and ai_advisory:
        ai_status = (ai_advisory.get("ai_status") or "").strip()
        if ai_status in ("ok", "fallback"):
            story.append(Paragraph(labels["ai_advisory"], styles["H2"]))
            story.append(Paragraph(f"<b>{labels['ai_status']}:</b> {ai_status}", styles["Body"]))
            if ai_status == "fallback":
                story.append(Paragraph(labels["ai_fallback_note"], styles["Body"]))
            summary = ai_advisory.get("executive_summary") or ""
            if summary:
                story.append(Paragraph(f"<b>{labels['ai_summary']}:</b> {summary}", styles["Body"]))

            priorities = ai_advisory.get("priorities") or []
            if isinstance(priorities, list) and priorities:
                story.append(Spacer(1, 6))
                story.append(Paragraph(labels["ai_priorities"], styles["H2"]))

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
        story.append(Paragraph(labels["checks"], styles["H2"]))
        rows = [
            [labels["booking"], labels["yes"] if signals.get("booking_detected") else labels["no"]],
            [labels["contact"], labels["yes"] if signals.get("contact_detected") else labels["no"]],
            [labels["services"], labels["yes"] if signals.get("services_keywords_detected") else labels["no"]],
            [labels["pricing"], labels["yes"] if signals.get("pricing_keywords_detected") else labels["no"]],
        ]
        checks = Table(rows, colWidths=[80 * mm, 92 * mm], hAlign="LEFT")
        checks.setStyle(TableStyle([
            ("FONTNAME", (0, 0), (-1, -1), font),
            ("FONTSIZE", (0, 0), (-1, -1), 9),
            ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#e5e7eb")),
            ("BACKGROUND", (0, 0), (0, -1), colors.HexColor("#f9fafb")),
            ("LEFTPADDING", (0, 0), (-1, -1), 6),
            ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ]))
        story.append(checks)

        # Social findings (agency-friendly, evidence-based)
        social_findings = [f for f in findings if (f or {}).get("category") == "social"]
        if social_findings:
            story.append(Spacer(1, 10))
            story.append(Paragraph(labels["social_findings"], styles["H2"]))

            rows = [[labels["severity"], labels["finding_col"], labels["recommendation_col"]]]
            for f in social_findings:
                sev = (f.get("severity") or "").capitalize()
                title = f.get("title_ro") if lang == "ro" else f.get("title_en")
                rec = f.get("recommendation_ro") if lang == "ro" else f.get("recommendation_en")

                rows.append([
                    Paragraph(sev, styles["Body"]),
                    Paragraph(title or "", styles["Body"]),
                    Paragraph(rec or "", styles["Body"]),
                ])

            tbl = Table(rows, colWidths=[22 * mm, 78 * mm, 72 * mm], hAlign="LEFT")
            tbl.setStyle(TableStyle([
                ("FONTNAME", (0, 0), (-1, -1), font),
                ("FONTSIZE", (0, 0), (-1, -1), 9),
                ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#e5e7eb")),
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#f9fafb")),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]))
            story.append(tbl)

        # Share preview & social metadata findings (Open Graph / Twitter)
        share_meta_findings = [f for f in findings if (f or {}).get("category") == "share_meta"]
        if share_meta_findings:
            story.append(Spacer(1, 10))
            story.append(Paragraph(labels["share_meta_findings"], styles["H2"]))

            rows = [[labels["severity"], labels["finding_col"], labels["recommendation_col"]]]
            for f in share_meta_findings:
                sev = (f.get("severity") or "").capitalize()
                title = f.get("title_ro") if lang == "ro" else f.get("title_en")
                rec = f.get("recommendation_ro") if lang == "ro" else f.get("recommendation_en")

                rows.append([
                    Paragraph(sev, styles["Body"]),
                    Paragraph(title or "", styles["Body"]),
                    Paragraph(rec or "", styles["Body"]),
                ])

            tbl = Table(rows, colWidths=[22 * mm, 78 * mm, 72 * mm], hAlign="LEFT")
            tbl.setStyle(TableStyle([
                ("FONTNAME", (0, 0), (-1, -1), font),
                ("FONTSIZE", (0, 0), (-1, -1), 9),
                ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#e5e7eb")),
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#f9fafb")),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]))
            story.append(tbl)

        # Indexability & Technical Access findings (always show section)
        index_findings = [f for f in findings if (f or {}).get("category") == "indexability_technical_access"]
        story.append(Spacer(1, 10))
        story.append(Paragraph(labels["indexability_findings"], styles["H2"]))

        if not index_findings:
            no_issues = (
                "No issues detected in this section based on the checks performed."
                if lang != "ro"
                else "Nu au fost detectate probleme în această secțiune pe baza verificărilor efectuate."
            )
            story.append(Paragraph(no_issues, styles["Body"]))
        else:
            rows = [[labels["severity"], labels["finding_col"], labels["recommendation_col"]]]
            for f in index_findings:
                sev = (f.get("severity") or "").capitalize()
                title = f.get("title_ro") if lang == "ro" else f.get("title_en")
                rec = f.get("recommendation_ro") if lang == "ro" else f.get("recommendation_en")

                rows.append([
                    Paragraph(sev, styles["Body"]),
                    Paragraph(title or "", styles["Body"]),
                    Paragraph(rec or "", styles["Body"]),
                ])

            tbl = Table(rows, colWidths=[22 * mm, 78 * mm, 72 * mm], hAlign="LEFT")
            tbl.setStyle(TableStyle([
                ("FONTNAME", (0, 0), (-1, -1), font),
                ("FONTSIZE", (0, 0), (-1, -1), 9),
                ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#e5e7eb")),
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#f9fafb")),
                ("LEFTPADDING", (0, 0), (-1, -1), 6),
                ("RIGHTPADDING", (0, 0), (-1, -1), 6),
                ("TOPPADDING", (0, 0), (-1, -1), 5),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
            ]))
            story.append(tbl)

    # Conversion loss (conservative) - show for all modes if present
    conv_findings = [f for f in findings if (f or {}).get("category") == "conversion_loss"]
    if conv_findings:
        story.append(Spacer(1, 10))
        story.append(Paragraph(labels["conversion_loss_findings"], styles["H2"]))

        def pct_range(ev: dict) -> str:
            try:
                lo = float(ev.get("impact_pct_low", 0) or 0)
                hi = float(ev.get("impact_pct_high", 0) or 0)
                return f"{round(lo*100)}%–{round(hi*100)}%"
            except Exception:
                return ""

        rows = [[labels["severity"], labels["finding_col"], labels["estimate_col"], labels["confidence_col"]]]
        for f in conv_findings:
            sev = (f.get("severity") or "").capitalize()
            title = f.get("title_ro") if lang == "ro" else f.get("title_en")
            ev = f.get("evidence", {}) or {}
            est = pct_range(ev)
            conf = ev.get("confidence") or ""
            rows.append([
                Paragraph(sev, styles["Body"]),
                Paragraph(title or "", styles["Body"]),
                Paragraph(est, styles["Body"]),
                Paragraph(str(conf), styles["Body"]),
            ])

        tbl = Table(rows, colWidths=[18 * mm, 80 * mm, 32 * mm, 42 * mm], hAlign="LEFT")
        tbl.setStyle(TableStyle([
            ("FONTNAME", (0, 0), (-1, -1), font),
            ("FONTSIZE", (0, 0), (-1, -1), 9),
            ("GRID", (0, 0), (-1, -1), 0.25, colors.HexColor("#e5e7eb")),
            ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#f9fafb")),
            ("LEFTPADDING", (0, 0), (-1, -1), 6),
            ("RIGHTPADDING", (0, 0), (-1, -1), 6),
            ("TOPPADDING", (0, 0), (-1, -1), 5),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ]))
        story.append(tbl)

    if mode == "broken":
        reason = signals.get("reason", "")
        if reason:
            story.append(Spacer(1, 10))
            story.append(Paragraph(labels["error_details"], styles["H2"]))
            safe_reason = (
                "Website-ul nu a putut fi accesat în timpul auditului. Detaliile tehnice sunt disponibile la cerere."
                if lang == "ro"
                else "The website could not be accessed during the audit. Technical details are available on request."
            )
            story.append(Paragraph(safe_reason, styles["Body"]))

    story.append(Spacer(1, 12))
    story.append(HRFlowable(color=colors.HexColor("#e5e7eb"), thickness=1, width="100%"))

    # --- Next steps CTA ---
    story.append(Spacer(1, 10))
    story.append(Paragraph("Next steps" if lang == "en" else "Pașii următori", styles["H2"]))

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

    story.append(Paragraph(cta_text, styles["Body"]))
    story.append(Spacer(1, 6))
    # Scope note (from client_narrative)
    scope_note = client_narrative.get("scope_note", "") or ""
    if scope_note:
        story.append(Spacer(1, 8))
        story.append(Paragraph(scope_note, styles["Small"]))

    story.append(Spacer(1, 6))
    story.append(Paragraph(f"Tool version: {tool_version}", styles["Small"]))
    story.append(Paragraph(labels["note"], styles["Small"]))

    doc.build(story)
    return out_path
