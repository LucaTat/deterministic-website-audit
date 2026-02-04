#!/usr/bin/env python3
"""Generate audit/report.pdf from existing verdict.json.

This script loads verdict.json and generates the Decision Brief and Evidence Appendix PDFs.
It's useful when the main audit was run but the PDF reports weren't generated.

Usage:
    python generate_report_from_verdict.py <RUN_DIR> [--lang RO|EN]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate audit report from verdict.json")
    parser.add_argument("run_dir", help="Path to the run directory containing verdict.json")
    parser.add_argument("--lang", default=None, help="Language (RO or EN)")
    args = parser.parse_args()

    run_dir = Path(args.run_dir).resolve()
    
    # Find verdict.json in various locations
    verdict_path = None
    for candidate in [
        run_dir / "verdict.json",
        run_dir / "audit" / "verdict.json",
    ]:
        if candidate.exists():
            verdict_path = candidate
            break
    
    if not verdict_path:
        print(f"ERROR: verdict.json not found in {run_dir}")
        return 1
    
    with open(verdict_path, "r", encoding="utf-8") as f:
        verdict_data = json.load(f)
    
    # Extract data from verdict.json
    url = verdict_data.get("url_input") or verdict_data.get("final_url", "")
    verdict = verdict_data.get("verdict", "UNKNOWN")
    categories = verdict_data.get("categories", {})
    blockers = verdict_data.get("blockers", [])
    timestamp_utc = verdict_data.get("timestamp_utc", "")
    lang = args.lang or verdict_data.get("lang", "EN")
    signals = verdict_data.get("signals") or verdict_data.get("v3x_flags") or {}
    if not isinstance(signals, dict):
        signals = {}
    
    # Ensure audit directory exists
    audit_dir = run_dir / "audit"
    audit_dir.mkdir(parents=True, exist_ok=True)
    
    # Try to use Astra's report generation
    try:
        # Add Astra to path
        astra_path = Path.home() / "Desktop" / "astra"
        if astra_path.exists():
            sys.path.insert(0, str(astra_path))
        
        from astra.report.decision_brief import generate_decision_brief_pdf
        from astra.report.evidence_appendix import generate_evidence_appendix_pdf
        
        # Generate Decision Brief
        generate_decision_brief_pdf(
            output_dir=audit_dir,
            url=url,
            verdict=verdict,
            categories=categories,
            timestamp_utc=timestamp_utc,
            lang=lang,
            signals=signals,
            filename="report.pdf",
        )
        print(f"Generated: {audit_dir / 'report.pdf'}")
        
        # Also generate the deliverables if they don't exist
        deliverables_dir = run_dir / "deliverables"
        deliverables_dir.mkdir(parents=True, exist_ok=True)
        
        brief_path = deliverables_dir / f"Decision_Brief_{lang}.pdf"
        if not brief_path.exists():
            generate_decision_brief_pdf(
                output_dir=deliverables_dir,
                url=url,
                verdict=verdict,
                categories=categories,
                timestamp_utc=timestamp_utc,
                lang=lang,
                signals=signals,
                filename=f"Decision_Brief_{lang}.pdf",
            )
            print(f"Generated: {brief_path}")
        
        appendix_path = deliverables_dir / f"Evidence_Appendix_{lang}.pdf"
        if not appendix_path.exists():
            generate_evidence_appendix_pdf(
                output_dir=deliverables_dir,
                url=url,
                verdict=verdict,
                categories=categories,
                timestamp_utc=timestamp_utc,
                lang=lang,
            )
            print(f"Generated: {appendix_path}")
        
        return 0
        
    except ImportError as e:
        print(f"ERROR: Could not import Astra report modules: {e}")
        print("Falling back to stub generation...")
    except Exception as e:
        print(f"ERROR: Report generation failed: {e}")
        print("Falling back to stub generation...")
    
    # Fallback: generate simple PDFs from verdict data
    try:
        from reportlab.lib.pagesizes import letter
        from reportlab.pdfgen import canvas

        def write_stub_pdf(path: Path, title: str, lines: list[str]) -> None:
            path.parent.mkdir(parents=True, exist_ok=True)
            c = canvas.Canvas(str(path), pagesize=letter)
            c.setFont("Helvetica-Bold", 18)
            c.drawString(72, 720, title)
            c.setFont("Helvetica", 11)
            y = 690
            for line in lines:
                if y < 72:
                    c.showPage()
                    c.setFont("Helvetica", 11)
                    y = 720
                c.drawString(72, y, str(line))
                y -= 14
            c.showPage()
            c.save()

        report_path = audit_dir / "report.pdf"
        write_stub_pdf(
            report_path,
            "Audit Report (Fallback)",
            [
                f"URL: {url}",
                f"Verdict: {verdict}",
                f"Language: {lang}",
                f"Generated: {timestamp_utc}",
            ],
        )

        deliverables_dir = run_dir / "deliverables"
        deliverables_dir.mkdir(parents=True, exist_ok=True)

        brief_path = deliverables_dir / f"Decision_Brief_{lang}.pdf"
        if not brief_path.exists():
            write_stub_pdf(
                brief_path,
                f"Decision Brief ({lang})",
                [
                    f"URL: {url}",
                    f"Verdict: {verdict}",
                    f"Generated: {timestamp_utc}",
                    "Summary: Auto-generated from verdict.json.",
                ],
            )

        appendix_path = deliverables_dir / f"Evidence_Appendix_{lang}.pdf"
        if not appendix_path.exists():
            blocker_lines = []
            for item in blockers[:12] if isinstance(blockers, list) else []:
                blocker_lines.append(f"- {item}")
            if not blocker_lines:
                blocker_lines = ["- No blockers listed in verdict.json"]

            signal_lines = []
            if isinstance(signals, dict) and signals:
                for key, value in list(signals.items())[:12]:
                    signal_lines.append(f"- {key}: {value}")
            else:
                signal_lines.append("- No signals listed in verdict.json")

            write_stub_pdf(
                appendix_path,
                f"Evidence Appendix ({lang})",
                [
                    f"URL: {url}",
                    f"Verdict: {verdict}",
                    f"Generated: {timestamp_utc}",
                    "Blockers:",
                    *blocker_lines,
                    "Signals:",
                    *signal_lines,
                ],
            )

        print(f"Generated fallback PDFs in {deliverables_dir}")
        return 0

    except Exception as e:
        print(f"FATAL: Could not generate fallback PDFs: {e}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
