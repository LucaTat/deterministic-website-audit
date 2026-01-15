import datetime as dt
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle


def _decision_brief_content(audit_result: dict, lang: str) -> dict:
    lang = (lang or "en").lower().strip()
    if lang not in ("ro", "en"):
        lang = "en"

    labels = {
        "en": {
            "title": "Decision Brief",
            "badge": "Client-safe",
            "status_ok": "OK (Ready)",
            "status_issues": "Issues found",
            "section_status": "Overall status",
            "section_means": "What this means",
            "section_decision": "Recommended decision",
            "means_ok": [
                "The website is reachable and clear enough for decisions.",
                "Focus on quick wins to improve response and clarity.",
            ],
            "means_issues": [
                "There are blockers that reduce trust or conversion.",
                "Fix the highest-impact issues before promoting the site.",
            ],
            "decision_ok": "Proceed with sending this report and schedule a brief review call.",
            "decision_issues": "Pause promotion until the top issues are resolved, then re-run.",
            "footer_campaign": "Campaign",
            "footer_date": "Date",
            "tool": "Deterministic Website Audit",
            "date_fmt": lambda: dt.date.today().strftime("%Y-%m-%d"),
            "domain_label": "Domain",
        },
        "ro": {
            "title": "Decizie rapidă",
            "badge": "Client-safe",
            "status_ok": "OK (Gata de trimis)",
            "status_issues": "Probleme găsite",
            "section_status": "Status general",
            "section_means": "Ce înseamnă",
            "section_decision": "Decizie recomandată",
            "means_ok": [
                "Website-ul este accesibil și suficient de clar pentru decizie.",
                "Concentrați-vă pe quick wins pentru claritate și răspuns.",
            ],
            "means_issues": [
                "Există blocaje care reduc încrederea sau conversia.",
                "Rezolvați întâi problemele cu impact mare.",
            ],
            "decision_ok": "Trimiteți raportul și programați un scurt call de revizuire.",
            "decision_issues": "Pauzați promovarea până la rezolvarea blocajelor, apoi re-rulați.",
            "footer_campaign": "Campanie",
            "footer_date": "Data",
            "tool": "Deterministic Website Audit",
            "date_fmt": lambda: dt.date.today().strftime("%d.%m.%Y"),
            "domain_label": "Domeniu",
        },
    }[lang]

    mode = (audit_result.get("mode") or "").strip().lower()
    is_ok = mode == "ok"

    domain = (audit_result.get("url") or audit_result.get("domain") or "").strip() or "-"
    campaign = (audit_result.get("campaign") or "").strip() or "-"
    cover_date = labels["date_fmt"]()

    status_text = labels["status_ok"] if is_ok else labels["status_issues"]
    means_list = labels["means_ok"] if is_ok else labels["means_issues"]
    decision_text = labels["decision_ok"] if is_ok else labels["decision_issues"]

    return {
        "labels": labels,
        "status_text": status_text,
        "means_list": means_list,
        "decision_text": decision_text,
        "domain": domain,
        "campaign": campaign,
        "date": cover_date,
    }


def generate_decision_brief_pdf(audit_result: dict, lang: str, output_path: str) -> str:
    """
    Generate a 1-page, client-safe decision brief PDF.
    """
    data = _decision_brief_content(audit_result, lang)
    labels = data["labels"]
    status_text = data["status_text"]
    means_list = data["means_list"]
    decision_text = data["decision_text"]
    domain = data["domain"]
    campaign = data["campaign"]
    cover_date = data["date"]

    styles = getSampleStyleSheet()
    styles.add(ParagraphStyle(
        name="SmallMuted",
        parent=styles["Normal"],
        fontSize=9,
        leading=12,
        textColor=colors.HexColor("#6b7280"),
    ))
    styles.add(ParagraphStyle(
        name="Header",
        parent=styles["Heading1"],
        fontSize=18,
        leading=22,
        textColor=colors.HexColor("#111827"),
    ))
    styles.add(ParagraphStyle(
        name="H2",
        parent=styles["Heading2"],
        fontSize=12,
        leading=15,
        textColor=colors.HexColor("#111827"),
    ))

    doc = SimpleDocTemplate(
        output_path,
        pagesize=A4,
        leftMargin=18 * mm,
        rightMargin=18 * mm,
        topMargin=16 * mm,
        bottomMargin=16 * mm,
        title=labels["title"],
    )

    header_table = Table(
        [[
            Paragraph(labels["title"], styles["Header"]),
            Paragraph(labels["badge"], styles["SmallMuted"]),
        ]],
        colWidths=[120 * mm, 40 * mm],
        hAlign="LEFT",
    )
    header_table.setStyle(TableStyle([
        ("ALIGN", (1, 0), (1, 0), "RIGHT"),
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
    ]))

    meta_table = Table(
        [
            [Paragraph(f'{labels["domain_label"]}:', styles["SmallMuted"]), Paragraph(domain, styles["Normal"])],
            [Paragraph(f'{labels["footer_campaign"]}:', styles["SmallMuted"]), Paragraph(campaign, styles["Normal"])],
        ],
        colWidths=[30 * mm, 130 * mm],
        hAlign="LEFT",
    )
    meta_table.setStyle(TableStyle([
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
    ]))

    status_box = Table(
        [[Paragraph(status_text, styles["Normal"])]],
        colWidths=[70 * mm],
        hAlign="LEFT",
    )
    status_box.setStyle(TableStyle([
        ("BOX", (0, 0), (-1, -1), 0.6, colors.HexColor("#d1d5db")),
        ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#f9fafb")),
        ("LEFTPADDING", (0, 0), (-1, -1), 8),
        ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))

    means_paragraphs = [Paragraph(f"• {item}", styles["Normal"]) for item in means_list]

    footer_table = Table(
        [[
            Paragraph(f'{labels["footer_campaign"]}: {campaign}', styles["SmallMuted"]),
            Paragraph(f'{labels["footer_date"]}: {cover_date}', styles["SmallMuted"]),
            Paragraph(labels["tool"], styles["SmallMuted"]),
        ]],
        colWidths=[55 * mm, 45 * mm, 55 * mm],
        hAlign="LEFT",
    )
    footer_table.setStyle(TableStyle([
        ("LINEABOVE", (0, 0), (-1, -1), 0.5, colors.HexColor("#e5e7eb")),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
        ("ALIGN", (1, 0), (1, 0), "CENTER"),
        ("ALIGN", (2, 0), (2, 0), "RIGHT"),
    ]))

    story = [
        header_table,
        Spacer(1, 6),
        meta_table,
        Spacer(1, 10),
        Paragraph(labels["section_status"], styles["H2"]),
        status_box,
        Spacer(1, 10),
        Paragraph(labels["section_means"], styles["H2"]),
        Spacer(1, 4),
        *means_paragraphs,
        Spacer(1, 10),
        Paragraph(labels["section_decision"], styles["H2"]),
        Paragraph(decision_text, styles["Normal"]),
        Spacer(1, 18),
        footer_table,
    ]

    doc.build(story)
    return output_path


def generate_decision_brief_txt(audit_result: dict, lang: str, output_path: str) -> None:
    """
    Generate a 1-page, client-safe decision brief TXT.
    """
    data = _decision_brief_content(audit_result, lang)
    labels = data["labels"]
    status_text = data["status_text"]
    means_list = data["means_list"]
    decision_text = data["decision_text"]
    domain = data["domain"]
    campaign = data["campaign"]
    cover_date = data["date"]

    lines = [
        labels["title"],
        f'{labels["domain_label"]}: {domain}',
        f'{labels["footer_campaign"]}: {campaign}',
        "",
        f'{labels["section_status"]}: {status_text}',
        "",
        labels["section_means"] + ":",
    ]
    for item in means_list:
        lines.append(f"- {item}")
    lines.extend([
        "",
        labels["section_decision"] + ":",
        decision_text,
        "",
        f'{labels["footer_date"]}: {cover_date}',
        labels["tool"],
    ])

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines).strip() + "\n")
