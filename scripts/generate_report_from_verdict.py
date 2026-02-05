#!/usr/bin/env python3
"""Generate Decision Brief and Evidence Appendix from verdict.json.

Usage:
    python3 generate_report_from_verdict.py <RUN_DIR> [--lang RO|EN]
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
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


def _load_verdict(run_dir: Path) -> tuple[Path, dict]:
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
                    return path, data
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

    # Try pages.json
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

    # Unique + deterministic order
    seen = set()
    unique: list[str] = []
    for url in urls:
        if url not in seen:
            seen.add(url)
            unique.append(url)
    return unique


def _verdict_badge_color(verdict: str):
    verdict = verdict.upper()
    return {
        "OK": colors.green,
        "GO": colors.green,
        "GO_WITH_FIXES": colors.orange,
        "CAUTION": colors.orange,
        "LIMITED": colors.orange,
        "NOT_AUDITABLE": colors.red,
        "FAIL": colors.red,
    }.get(verdict, colors.gray)


def _impact_for_category(name: str) -> str:
    n = name.lower()
    if "tracking" in n or "observability" in n or "analytics" in n:
        return "Impact: tracking/attribution may be incomplete."
    if "conversion" in n:
        return "Impact: paid traffic may not convert as expected."
    if "reachability" in n or "landing" in n:
        return "Impact: paid traffic may not reach a valid landing."
    if "index" in n:
        return "Impact: visibility/indexability may be limited."
    if "trust" in n or "security" in n:
        return "Impact: trust signals may be weakened."
    return "Impact: requires verification before ads."


def _category_evidence_ref(cat: dict) -> str:
    evidence = cat.get("evidence") if isinstance(cat, dict) else None
    if isinstance(evidence, dict) and evidence:
        key = sorted(evidence.keys())[0]
        return f"evidence.{key}"
    reasons = cat.get("reasons") if isinstance(cat, dict) else None
    if isinstance(reasons, list) and reasons:
        return str(reasons[0])[:80]
    return "verdict.json"


def _flatten_evidence(categories: dict) -> list[str]:
    lines: list[str] = []
    for name in sorted(categories.keys()):
        cat = categories.get(name) or {}
        evidence = cat.get("evidence") if isinstance(cat, dict) else None
        if isinstance(evidence, dict) and evidence:
            for key in sorted(evidence.keys()):
                value = evidence.get(key)
                text = _safe_text(value)
                if text:
                    lines.append(f"{name}: {key} = {text}")
    return lines


def _build_decision_brief(out_path: Path, data: dict, lang: str, urls: list[str]) -> None:
    styles = getSampleStyleSheet()
    story = []

    brand = _safe_text(data.get("brand"), "SCOPE")
    verdict = _safe_text(data.get("verdict"), "UNKNOWN")
    timestamp = _safe_text(data.get("timestamp_utc"))
    domain = _safe_text(data.get("final_url") or data.get("url_input"))

    # Cover page
    story.append(Paragraph(f"{brand} Decision Brief", styles["Title"]))
    if domain:
        story.append(Spacer(1, 8))
        story.append(Paragraph(f"Domain: {domain}", styles["Heading3"]))
    if timestamp:
        story.append(Paragraph(f"Date (UTC): {timestamp}", styles["BodyText"]))

    badge = Table(
        [[Paragraph(f"VERDICT: {verdict}", styles["Heading2"]) ]],
        style=[
            ("BACKGROUND", (0, 0), (-1, -1), _verdict_badge_color(verdict)),
            ("TEXTCOLOR", (0, 0), (-1, -1), colors.white),
            ("ALIGN", (0, 0), (-1, -1), "CENTER"),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("BOX", (0, 0), (-1, -1), 1, colors.black),
            ("INNERPADDING", (0, 0), (-1, -1), 8),
        ],
    )
    story.append(Spacer(1, 12))
    story.append(badge)
    story.append(PageBreak())

    categories = data.get("categories") if isinstance(data.get("categories"), dict) else {}
    blockers = data.get("blockers") if isinstance(data.get("blockers"), list) else []

    # Executive summary
    story.append(Paragraph("Executive Summary" if lang == "EN" else "Sumar Executiv", styles["Heading1"]))
    total = len(categories)
    non_pass = [name for name, cat in categories.items() if str((cat or {}).get("status", "")).upper() not in ("PASS", "OK")]
    parts = [f"Verdict: {verdict}."]
    if total:
        parts.append(f"Categories evaluated: {total}.")
    if non_pass:
        parts.append(f"Requires attention: {', '.join(sorted(non_pass))}.")
    if blockers:
        parts.append(f"Blockers listed: {len(blockers)}.")
    summary = " ".join(parts)
    story.append(Paragraph(summary, styles["BodyText"]))
    story.append(Spacer(1, 10))

    # Top risks
    story.append(Paragraph("Top Risks" if lang == "EN" else "Riscuri Majore", styles["Heading1"]))
    risks: list[str] = []
    if blockers:
        for item in blockers:
            risks.append(f"{item} — Impact: blocks approval until resolved. Evidence: verdict.json")
    for name in sorted(non_pass):
        cat = categories.get(name) or {}
        impact = _impact_for_category(name)
        ref = _category_evidence_ref(cat)
        risks.append(f"{name} — {impact} Evidence: {ref} (Tool: Audit)")
    if not risks:
        risks.append("No risks listed in verdict.json.")
    risks = risks[:5]
    story.append(ListFlowable([ListItem(Paragraph(r, styles["BodyText"])) for r in risks], bulletType="bullet"))
    story.append(Spacer(1, 10))

    # Required actions
    story.append(Paragraph("Required Actions Before Ads" if lang == "EN" else "Actiuni Necesare Inainte de Ads", styles["Heading1"]))
    actions: list[str] = []
    if blockers:
        actions = [str(b) for b in blockers]
    elif non_pass:
        for name in sorted(non_pass):
            cat = categories.get(name) or {}
            reasons = cat.get("reasons") if isinstance(cat, dict) else None
            if isinstance(reasons, list) and reasons:
                actions.append(f"{name}: {reasons[0]}")
            else:
                actions.append(f"{name}: review required")
    if not actions:
        actions.append("No required actions listed in verdict.json.")
    story.append(ListFlowable([ListItem(Paragraph(a, styles["BodyText"])) for a in actions], bulletType="bullet"))
    story.append(Spacer(1, 10))

    # Scope & limitations
    story.append(Paragraph("Scope & Limitations" if lang == "EN" else "Arie si Limitari", styles["Heading1"]))
    audited = ", ".join(sorted(categories.keys())) if categories else "No categories provided"
    story.append(Paragraph(f"Audited categories: {audited}.", styles["BodyText"]))
    not_audited = [
        "Creative quality",
        "Legal compliance",
        "Backend data integrity",
        "Load testing or performance under sustained traffic",
    ]
    story.append(Paragraph("Not audited by this toolset:", styles["BodyText"]))
    story.append(ListFlowable([ListItem(Paragraph(x, styles["BodyText"])) for x in not_audited], bulletType="bullet"))

    doc = SimpleDocTemplate(str(out_path), pagesize=LETTER, title="Decision Brief")
    doc.build(story)


def _build_evidence_appendix(out_path: Path, data: dict, lang: str, urls: list[str]) -> None:
    styles = getSampleStyleSheet()
    story = []

    brand = _safe_text(data.get("brand"), "SCOPE")
    domain = _safe_text(data.get("final_url") or data.get("url_input"))
    timestamp = _safe_text(data.get("timestamp_utc"))

    story.append(Paragraph(f"{brand} Evidence Appendix", styles["Title"]))
    if domain:
        story.append(Paragraph(f"Domain: {domain}", styles["Heading3"]))
    if timestamp:
        story.append(Paragraph(f"Date (UTC): {timestamp}", styles["BodyText"]))
    story.append(PageBreak())

    # TOC (simple list)
    story.append(Paragraph("Table of Contents" if lang == "EN" else "Cuprins", styles["Heading1"]))
    toc_items = [
        "Audit Evidence",
        "Action Scope Evidence",
        "Proof Pack Evidence",
        "Regression Evidence",
    ]
    story.append(ListFlowable([ListItem(Paragraph(item, styles["BodyText"])) for item in toc_items], bulletType="bullet"))
    story.append(PageBreak())

    categories = data.get("categories") if isinstance(data.get("categories"), dict) else {}
    evidence_summary = data.get("evidence_summary") if isinstance(data.get("evidence_summary"), dict) else {}
    signals = data.get("signals") if isinstance(data.get("signals"), dict) else {}

    def add_tool_section(title: str, relevant_categories: list[str]) -> None:
        story.append(Paragraph(title, styles["Heading1"]))
        # URLs tested
        if urls:
            story.append(Paragraph("URLs tested:", styles["Heading3"]))
            story.append(ListFlowable([ListItem(Paragraph(u, styles["BodyText"])) for u in urls], bulletType="bullet"))

        # Response codes / headers
        detail_lines: list[str] = []
        if evidence_summary:
            for key in sorted(evidence_summary.keys()):
                val = _safe_text(evidence_summary.get(key))
                if val:
                    detail_lines.append(f"{key}: {val}")
        for name in relevant_categories:
            cat = categories.get(name) or {}
            ev = cat.get("evidence") if isinstance(cat, dict) else None
            if isinstance(ev, dict):
                for key in sorted(ev.keys()):
                    val = _safe_text(ev.get(key))
                    if val:
                        detail_lines.append(f"{name}: {key} = {val}")
        if signals:
            for key in sorted(signals.keys()):
                val = _safe_text(signals.get(key))
                if val:
                    detail_lines.append(f"signal.{key}: {val}")

        if detail_lines:
            story.append(Paragraph("Evidence detected:", styles["Heading3"]))
            story.append(ListFlowable([ListItem(Paragraph(line, styles["BodyText"])) for line in detail_lines], bulletType="bullet"))
        else:
            story.append(Paragraph("No evidence items recorded for this tool.", styles["BodyText"]))

        story.append(PageBreak())

    # Determine categories by tool
    names = list(categories.keys())
    audit_cats = [n for n in names if any(k in n.lower() for k in ["reachability", "landing", "conversion", "tracking", "index"])]
    action_cats = [n for n in names if any(k in n.lower() for k in ["conversion", "landing", "reachability"])]
    proof_cats = [n for n in names if any(k in n.lower() for k in ["tracking", "observability", "analytics"])]
    regression_cats = [n for n in names if "regression" in n.lower()]

    add_tool_section("Audit Evidence", audit_cats or names)
    add_tool_section("Action Scope Evidence", action_cats or names)
    add_tool_section("Proof Pack Evidence", proof_cats or names)
    add_tool_section("Regression Evidence", regression_cats or names)

    doc = SimpleDocTemplate(str(out_path), pagesize=LETTER, title="Evidence Appendix")
    doc.build(story)


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate Decision Brief and Evidence Appendix from verdict.json")
    parser.add_argument("run_dir", help="Path to the run directory containing verdict.json")
    parser.add_argument("--lang", default=None, help="Language (RO or EN)")
    args = parser.parse_args()

    run_dir = Path(args.run_dir).resolve()
    if not run_dir.is_dir():
        print("ERROR: run dir missing")
        return 2

    try:
        _, data = _load_verdict(run_dir)
    except FileNotFoundError:
        print("ERROR: verdict.json missing")
        return 2

    lang = _detect_lang(data, args.lang)
    urls = _collect_urls(data, run_dir)

    deliverables_dir = run_dir / "deliverables"
    deliverables_dir.mkdir(parents=True, exist_ok=True)

    # Ensure verdict.json exists in deliverables (deterministic copy)
    verdict_out = deliverables_dir / "verdict.json"
    try:
        with verdict_out.open("w", encoding="utf-8") as f:
            json.dump(data, f, sort_keys=True, indent=2)
            f.write("\n")
    except Exception:
        print("ERROR: could not write deliverables/verdict.json")
        return 2

    brief_path = deliverables_dir / f"Decision_Brief_{lang}.pdf"
    appendix_path = deliverables_dir / f"Evidence_Appendix_{lang}.pdf"

    _build_decision_brief(brief_path, data, lang, urls)
    _build_evidence_appendix(appendix_path, data, lang, urls)

    print("OK deliverables")
    return 0


if __name__ == "__main__":
    sys.exit(main())
