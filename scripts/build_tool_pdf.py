#!/usr/bin/env python3
"""Build deterministic Tool PDFs (tool2/tool3/tool4) from verdict.json.

Usage:
  python3 build_tool_pdf.py --run-dir <RUN_DIR> --tool tool2|tool3|tool4 [--lang RO|EN]
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.pagesizes import LETTER
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    PageBreak,
    ListFlowable,
    ListItem,
)

TOOL_SPEC = {
    "tool2": {
        "folder": "action_scope",
        "pdf": "action_scope.pdf",
        "title": "Action Scope",
        "keywords": ["reachability", "landing", "conversion"],
        "limitations": [
            "Does not verify creative quality",
            "Does not validate backend order processing",
            "Does not measure paid traffic performance",
        ],
    },
    "tool3": {
        "folder": "proof_pack",
        "pdf": "proof_pack.pdf",
        "title": "Implementation Proof",
        "keywords": ["tracking", "observability", "analytics", "index"],
        "limitations": [
            "Does not verify ad platform setup",
            "Does not validate conversion attribution accuracy",
            "Does not test long-term tracking stability",
        ],
    },
    "tool4": {
        "folder": "regression",
        "pdf": "regression.pdf",
        "title": "Regression Scan",
        "keywords": ["regression"],
        "limitations": [
            "No baseline comparison unless a prior run exists",
            "Does not compare historical business metrics",
            "Does not validate backend data changes",
        ],
    },
}


def _load_verdict(run_dir: Path) -> dict:
    candidates = [
        run_dir / "deliverables" / "verdict.json",
        run_dir / "audit" / "verdict.json",
        run_dir / "verdict.json",
        run_dir / "astra" / "verdict.json",
        run_dir / "astra" / "audit" / "verdict.json",
    ]
    for path in candidates:
        if path.is_file():
            try:
                data = json.loads(path.read_text(encoding="utf-8"))
                if isinstance(data, dict):
                    return data
            except Exception:
                continue
    raise FileNotFoundError("verdict.json not found")


def _detect_lang(data: dict, arg_lang: str | None) -> str:
    lang = (arg_lang or data.get("lang") or "EN").strip().upper()
    return "RO" if lang == "RO" else "EN"


def _safe_text(value, fallback: str = "") -> str:
    if value is None:
        return fallback
    text = str(value).strip()
    return text if text else fallback


def _collect_urls(data: dict, run_dir: Path) -> list[str]:
    urls: list[str] = []
    for key in ("url_input", "final_url"):
        val = _safe_text(data.get(key))
        if val:
            urls.append(val)

    pages_path = None
    scope = data.get("scope") or {}
    outputs = scope.get("outputs") if isinstance(scope, dict) else {}
    if isinstance(outputs, dict):
        rel = _safe_text(outputs.get("pages_json_path"))
        if rel:
            for base in (run_dir, run_dir.parent):
                candidate = base / rel
                if candidate.is_file():
                    pages_path = candidate
                    break
    if pages_path is None:
        for base in (run_dir, run_dir.parent):
            candidate = base / "scope" / "evidence" / "pages.json"
            if candidate.is_file():
                pages_path = candidate
                break

    if pages_path:
        try:
            pages = json.loads(pages_path.read_text(encoding="utf-8"))
            if isinstance(pages, list):
                for page in pages:
                    if isinstance(page, dict):
                        url = _safe_text(page.get("url"))
                        if url:
                            urls.append(url)
        except Exception:
            pass

    seen = set()
    unique: list[str] = []
    for url in urls:
        if url not in seen:
            seen.add(url)
            unique.append(url)
    return unique


def _category_evidence_ref(cat: dict) -> str:
    evidence = cat.get("evidence") if isinstance(cat, dict) else None
    if isinstance(evidence, dict) and evidence:
        key = sorted(evidence.keys())[0]
        return f"evidence.{key}"
    reasons = cat.get("reasons") if isinstance(cat, dict) else None
    if isinstance(reasons, list) and reasons:
        return str(reasons[0])[:80]
    return "verdict.json"


def _select_categories(categories: dict, keywords: list[str]) -> list[tuple[str, dict]]:
    selected = []
    for name in sorted(categories.keys()):
        lname = name.lower()
        if any(k in lname for k in keywords):
            selected.append((name, categories.get(name) or {}))
    return selected


def build_tool_pdf(run_dir: Path, tool: str, lang: str) -> Path:
    spec = TOOL_SPEC[tool]
    data = _load_verdict(run_dir)
    categories = data.get("categories") if isinstance(data.get("categories"), dict) else {}
    evidence_summary = data.get("evidence_summary") if isinstance(data.get("evidence_summary"), dict) else {}
    signals = data.get("signals") if isinstance(data.get("signals"), dict) else {}

    urls = _collect_urls(data, run_dir)
    domain = _safe_text(data.get("final_url") or data.get("url_input"))
    timestamp = _safe_text(data.get("timestamp_utc"))

    tool_dir = run_dir / spec["folder"]
    tool_dir.mkdir(parents=True, exist_ok=True)
    out_path = tool_dir / spec["pdf"]

    styles = getSampleStyleSheet()
    story = []

    # Cover page
    story.append(Paragraph(spec["title"], styles["Title"]))
    if domain:
        story.append(Paragraph(f"Domain: {domain}", styles["Heading3"]))
    if timestamp:
        story.append(Paragraph(f"Run (UTC): {timestamp}", styles["BodyText"]))
    story.append(PageBreak())

    # Summary table
    story.append(Paragraph("Summary" if lang == "EN" else "Sumar", styles["Heading1"]))
    selected = _select_categories(categories, spec["keywords"])
    rows = [["Check", "Status", "Evidence Ref"]]
    if selected:
        for name, cat in selected:
            status = _safe_text((cat or {}).get("status"), "N/A")
            ref = _category_evidence_ref(cat or {})
            rows.append([name, status, ref])
    else:
        rows.append(["No issues detected", "OK", "verdict.json"])

    table = Table(rows, colWidths=[200, 80, 200])
    table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), colors.lightgrey),
                ("TEXTCOLOR", (0, 0), (-1, 0), colors.black),
                ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]
        )
    )
    story.append(table)
    story.append(Spacer(1, 10))

    # Evidence
    story.append(Paragraph("Evidence", styles["Heading1"]))
    if urls:
        story.append(Paragraph("URLs tested:", styles["Heading3"]))
        story.append(ListFlowable([ListItem(Paragraph(u, styles["BodyText"])) for u in urls], bulletType="bullet"))

    evidence_lines: list[str] = []
    if evidence_summary:
        for key in sorted(evidence_summary.keys()):
            val = _safe_text(evidence_summary.get(key))
            if val:
                evidence_lines.append(f"{key}: {val}")
    for name, cat in selected:
        ev = cat.get("evidence") if isinstance(cat, dict) else None
        if isinstance(ev, dict):
            for key in sorted(ev.keys()):
                val = _safe_text(ev.get(key))
                if val:
                    evidence_lines.append(f"{name}: {key} = {val}")
    if signals:
        for key in sorted(signals.keys()):
            val = _safe_text(signals.get(key))
            if val:
                evidence_lines.append(f"signal.{key}: {val}")

    if evidence_lines:
        story.append(Paragraph("Detected headers/scripts/signals:", styles["Heading3"]))
        story.append(ListFlowable([ListItem(Paragraph(line, styles["BodyText"])) for line in evidence_lines], bulletType="bullet"))
    else:
        story.append(Paragraph("No evidence items recorded for this tool.", styles["BodyText"]))

    story.append(Spacer(1, 10))

    # Limitations
    story.append(Paragraph("What this tool does NOT verify", styles["Heading1"]))
    story.append(ListFlowable([ListItem(Paragraph(x, styles["BodyText"])) for x in spec["limitations"]], bulletType="bullet"))

    doc = SimpleDocTemplate(str(out_path), pagesize=LETTER, title=spec["title"])
    doc.build(story)
    return out_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Build deterministic Tool PDF")
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--tool", required=True, choices=sorted(TOOL_SPEC.keys()))
    parser.add_argument("--lang", default=None, help="Language (RO or EN)")
    args = parser.parse_args()

    run_dir = Path(args.run_dir).resolve()
    if not run_dir.is_dir():
        print("ERROR: run dir missing")
        return 2

    try:
        data = _load_verdict(run_dir)
    except FileNotFoundError:
        print("ERROR: verdict.json missing")
        return 2

    lang = _detect_lang(data, args.lang)
    build_tool_pdf(run_dir, args.tool, lang)
    print("OK tool pdf")
    return 0


if __name__ == "__main__":
    sys.exit(main())
