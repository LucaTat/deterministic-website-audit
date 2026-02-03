#!/usr/bin/env python3
import argparse
import json
from pathlib import Path
from tempfile import NamedTemporaryFile

from pypdf import PdfReader, PdfWriter
from reportlab.lib.pagesizes import LETTER
from reportlab.pdfgen import canvas


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args()

    run_dir = Path(args.run_dir).resolve()
    if not run_dir.is_dir():
        print("ERROR run dir not found")
        return 2

    verdict_json = run_dir / "deliverables" / "verdict.json"
    required = [
        run_dir / "audit" / "report.pdf",
        run_dir / "action_scope" / "action_scope.pdf",
        run_dir / "proof_pack" / "proof_pack.pdf",
        run_dir / "regression" / "regression.pdf",
        run_dir / "final" / "master.pdf",
        verdict_json,
    ]
    for path in required:
        if not path.is_file():
            print("ERROR missing required: " + str(path))
            return 2

    try:
        data = json.loads(verdict_json.read_text(encoding="utf-8"))
    except Exception:
        print("ERROR invalid verdict.json")
        return 2
    verdict_text = (
        str(data.get("verdict") or data.get("final_verdict") or data.get("result") or "UNKNOWN")
    )

    out_pdf = run_dir / "final" / "MASTER_BUNDLE.pdf"
    out_pdf.parent.mkdir(parents=True, exist_ok=True)

    with NamedTemporaryFile(prefix="verdict_", suffix=".pdf", delete=False, dir=str(out_pdf.parent)) as tmp:
        verdict_path = Path(tmp.name)
    c = canvas.Canvas(str(verdict_path), pagesize=LETTER)
    c.setFont("Helvetica-Bold", 20)
    c.drawString(72, 720, "VERDICT")
    c.setFont("Helvetica", 16)
    c.drawString(72, 690, verdict_text)
    c.showPage()
    c.save()

    writer = PdfWriter()
    writer.add_metadata({})
    for path in [verdict_path] + [p for p in required if p != verdict_json]:
        reader = PdfReader(str(path))
        for page in reader.pages:
            writer.add_page(page)

    with open(out_pdf, "wb") as f:
        writer.write(f)
    try:
        verdict_path.unlink()
    except Exception:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
