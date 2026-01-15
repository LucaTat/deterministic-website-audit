import datetime as dt
import os
import re
import unicodedata
from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle


def sanitize_pdf_text(text: str) -> str:
    if text is None:
        return ""
    if not isinstance(text, str):
        text = str(text)

    replacements = {
        "\u00a0": " ",  # NBSP
        "\u202f": " ",  # narrow NBSP
    }
    for key, value in replacements.items():
        text = text.replace(key, value)

    for ch in ("\u200b", "\u200c", "\u200d", "\u2060", "\ufeff", "\u00ad"):
        text = text.replace(ch, "")

    text = text.replace("\r\n", "\n").replace("\r", "\n")
    text = "".join(ch for ch in text if ch == "\n" or ch == "\t" or (ord(ch) >= 32 and ord(ch) != 127))
    text = "".join(
        ch for ch in text
        if ch == "\n" or ch == "\t" or unicodedata.category(ch) not in ("Cc", "Cf")
    )
    text = re.sub(r"[ ]{2,}", " ", text)
    return text


def _canonical_list(items) -> list:
    if not items:
        return []
    return sorted([str(item).strip() for item in items if str(item).strip()])


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

    def sanitize_labels(src: dict) -> dict:
        cleaned = {}
        for key, value in src.items():
            if isinstance(value, list):
                cleaned[key] = [sanitize_pdf_text(item) for item in value]
            elif callable(value):
                cleaned[key] = value
            else:
                cleaned[key] = sanitize_pdf_text(value)
        return cleaned

    labels = sanitize_labels(labels)

    mode = (audit_result.get("mode") or "").strip().lower()
    is_ok = mode == "ok"

    domain = sanitize_pdf_text((audit_result.get("url") or audit_result.get("domain") or "").strip() or "-")
    campaign = sanitize_pdf_text((audit_result.get("campaign") or "").strip() or "-")
    cover_date = sanitize_pdf_text(labels["date_fmt"]())

    status_text = labels["status_ok"] if is_ok else labels["status_issues"]
    means_list = labels["means_ok"] if is_ok else labels["means_issues"]
    decision_text = labels["decision_ok"] if is_ok else labels["decision_issues"]

    status_text = sanitize_pdf_text(status_text)
    means_list = [sanitize_pdf_text(item) for item in means_list]
    decision_text = sanitize_pdf_text(decision_text)

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
    def _is_valid_ttf(path: str) -> bool:
        try:
            with open(path, "rb") as handle:
                header = handle.read(4)
            return header in (b"\x00\x01\x00\x00", b"OTTO", b"ttcf")
        except OSError:
            return False

    data = _decision_brief_content(audit_result, lang)
    labels = data["labels"]
    status_text = data["status_text"]
    means_list = data["means_list"]
    decision_text = data["decision_text"]
    domain = data["domain"]
    campaign = data["campaign"]
    cover_date = data["date"]

    font_name = "ScopeSans"
    font_bold = "ScopeSans-Bold"
    here = os.path.dirname(os.path.abspath(__file__))
    repo_root = os.path.abspath(os.path.join(here, "..", ".."))
    font_dir = os.path.join(repo_root, "fonts")
    font_path = os.path.join(font_dir, "DejaVuSans.ttf")
    font_bold_path = os.path.join(font_dir, "DejaVuSans-Bold.ttf")
    if not os.path.exists(font_path):
        raise FileNotFoundError(
            "Missing fonts/DejaVuSans.ttf. Add it to enable Unicode-safe PDF output."
        )
    if not _is_valid_ttf(font_path):
        raise FileNotFoundError(
            "Invalid fonts/DejaVuSans.ttf. Replace with a valid TTF file."
        )
    pdfmetrics.registerFont(TTFont("ScopeSans", font_path))
    if os.path.exists(font_bold_path) and _is_valid_ttf(font_bold_path):
        pdfmetrics.registerFont(TTFont("ScopeSans-Bold", font_bold_path))
    else:
        font_bold = font_name

    styles = getSampleStyleSheet()
    styles["Normal"].fontName = font_name
    styles["Heading1"].fontName = font_bold
    styles["Heading2"].fontName = font_bold
    styles.add(ParagraphStyle(
        name="SmallMuted",
        parent=styles["Normal"],
        fontName=font_name,
        fontSize=9,
        leading=12,
        textColor=colors.HexColor("#6b7280"),
    ))
    styles.add(ParagraphStyle(
        name="Header",
        parent=styles["Heading1"],
        fontName=font_bold,
        fontSize=18,
        leading=22,
        textColor=colors.HexColor("#111827"),
    ))
    styles.add(ParagraphStyle(
        name="H2",
        parent=styles["Heading2"],
        fontName=font_bold,
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
            Paragraph(sanitize_pdf_text(labels["title"]), styles["Header"]),
            Paragraph(sanitize_pdf_text(labels["badge"]), styles["SmallMuted"]),
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
            [Paragraph(sanitize_pdf_text(f'{labels["domain_label"]}:'), styles["SmallMuted"]), Paragraph(sanitize_pdf_text(domain), styles["Normal"])],
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
        [[Paragraph(sanitize_pdf_text(status_text), styles["Normal"])]],
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

    means_paragraphs = [Paragraph(sanitize_pdf_text(f"- {item}"), styles["Normal"]) for item in means_list]

    footer_table = Table(
        [[
            Paragraph(sanitize_pdf_text(f'{labels["footer_campaign"]}: {campaign}'), styles["SmallMuted"]),
            Paragraph(sanitize_pdf_text(f'{labels["footer_date"]}: {cover_date}'), styles["SmallMuted"]),
            Paragraph(sanitize_pdf_text(labels["tool"]), styles["SmallMuted"]),
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
        Paragraph(sanitize_pdf_text(labels["section_status"]), styles["H2"]),
        status_box,
        Spacer(1, 10),
        Paragraph(sanitize_pdf_text(labels["section_means"]), styles["H2"]),
        Spacer(1, 4),
        *means_paragraphs,
        Spacer(1, 10),
        Paragraph(sanitize_pdf_text(labels["section_decision"]), styles["H2"]),
        Paragraph(sanitize_pdf_text(decision_text), styles["Normal"]),
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
    lines = [
        sanitize_pdf_text(labels["title"]),
        sanitize_pdf_text(f'{labels["domain_label"]}: {domain}'),
        "",
        sanitize_pdf_text(f'{labels["section_status"]}: {status_text}'),
        "",
        sanitize_pdf_text(labels["section_means"] + ":"),
    ]
    for item in _canonical_list(means_list):
        lines.append(sanitize_pdf_text(f"- {item}"))
    lines.extend([
        "",
        sanitize_pdf_text(labels["section_decision"] + ":"),
        sanitize_pdf_text(decision_text),
        "",
        sanitize_pdf_text(labels["tool"]),
    ])

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines).strip() + "\n")
