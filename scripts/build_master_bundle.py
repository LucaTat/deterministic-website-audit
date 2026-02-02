#!/usr/bin/env python3
import argparse
import os
from pathlib import Path

from pypdf import PdfReader, PdfWriter


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True)
    args = parser.parse_args()

    run_dir = Path(args.run_dir).resolve()
    if not run_dir.is_dir():
        print("ERROR run dir not found")
        return 2

    required = [
        run_dir / "audit" / "report.pdf",
        run_dir / "action_scope" / "action_scope.pdf",
        run_dir / "proof_pack" / "proof_pack.pdf",
        run_dir / "regression" / "regression.pdf",
        run_dir / "final" / "master.pdf",
    ]
    for path in required:
        if not path.is_file():
            print("ERROR missing required: " + str(path))
            return 2

    out_pdf = run_dir / "final" / "MASTER_BUNDLE.pdf"
    out_pdf.parent.mkdir(parents=True, exist_ok=True)

    writer = PdfWriter()
    for path in required:
        reader = PdfReader(str(path))
        for page in reader.pages:
            writer.add_page(page)

    with open(out_pdf, "wb") as f:
        writer.write(f)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
