import argparse
import glob
import io
import os
from typing import Dict, List

from pypdf import PdfReader, PdfWriter
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas


BUCKETS = [
    ("tool1_scope_report", True, [
        "audit/report.pdf",
        "audit/*.pdf",
        "deliverables/report.pdf",
        "scope/report.pdf",
        "report.pdf",
    ]),
    ("astra_decision", True, [
        "astra/deliverables/Decision_Brief*.pdf",
        "astra/Decision Brief*.pdf",
        "astra/*.pdf",
        "astra/final_decision/ASTRA_Traffic_Readiness_Decision_*.pdf",
        "astra/Decision_Brief_*_*.pdf",
        "astra/Decision Brief - * - *.pdf",
        "deliverables/Decision Brief - * - *.pdf",
    ]),
    ("tool2_action_scope", False, [
        "action_scope/*.pdf",
        "tool2/*.pdf",
    ]),
    ("tool3_proof_pack", False, [
        "proof_pack/*.pdf",
        "tool3/*.pdf",
    ]),
    ("tool4_regression", False, [
        "regression/*.pdf",
        "tool4/*.pdf",
    ]),
]

DIVIDER_TITLES = {
    "tool1_scope_report": "Scope Report",
    "astra_decision": "ASTRA Decision",
    "tool2_action_scope": "Action Scope",
    "tool3_proof_pack": "Proof Pack",
    "tool4_regression": "Regression Guard",
}


def _relative_path(base: str, path: str) -> str:
    return os.path.relpath(path, base).replace("\\", "/")


def _find_bucket_file(run_dir: str, patterns: List[str]) -> str | None:
    candidates: List[str] = []
    for pattern in patterns:
        abs_pattern = os.path.join(run_dir, pattern)
        if "*" not in pattern:
            if os.path.isfile(abs_pattern):
                candidates.append(abs_pattern)
        else:
            for match in sorted(glob.glob(abs_pattern)):
                if os.path.isfile(match) and match.lower().endswith(".pdf"):
                    candidates.append(match)
    if not candidates:
        return None
    candidates_sorted = sorted(candidates, key=lambda p: _relative_path(run_dir, p))
    return candidates_sorted[0]


def _build_divider_pdf(title: str) -> PdfReader:
    buf = io.BytesIO()
    c = canvas.Canvas(buf, pagesize=letter)
    width, height = letter
    c.setFont("Helvetica-Bold", 32)
    c.drawCentredString(width / 2.0, height / 2.0, title)
    c.showPage()
    c.save()
    buf.seek(0)
    return PdfReader(buf)


def build_master_pdf(run_dir: str, out_pdf: str, *, strict: bool = True) -> Dict:
    run_dir = os.path.abspath(run_dir)
    if not os.path.isdir(run_dir):
        raise ValueError(f"Run directory not found: {run_dir}")

    included = []
    missing_optional: List[str] = []

    writer = PdfWriter()
    total_pages = 0

    for key, required, patterns in BUCKETS:
        path = _find_bucket_file(run_dir, patterns)
        if not path:
            if required and strict:
                raise ValueError(f"Missing required PDF for {key}.")
            if not required:
                missing_optional.append(key)
            continue

        divider_title = DIVIDER_TITLES.get(key, key)
        divider_reader = _build_divider_pdf(divider_title)
        for page in divider_reader.pages:
            writer.add_page(page)
            total_pages += 1

        reader = PdfReader(path)
        for page in reader.pages:
            writer.add_page(page)
        included.append({
            "key": key,
            "path": path,
            "pages": len(reader.pages),
        })
        total_pages += len(reader.pages)

    if strict:
        required_missing = [
            key for key, required, _ in BUCKETS
            if required and key not in {item["key"] for item in included}
        ]
        if required_missing:
            raise ValueError(f"Missing required PDFs: {', '.join(required_missing)}")

    out_dir = os.path.dirname(out_pdf)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)

    with open(out_pdf, "wb") as f:
        writer.write(f)

    return {
        "included": included,
        "missing_optional": missing_optional,
        "out_pdf": out_pdf,
        "total_pages": total_pages,
    }


def _main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    try:
        result = build_master_pdf(args.run_dir, args.out, strict=True)
    except Exception as exc:
        reason = str(exc) or "Unknown error"
        print(f"ERROR master.pdf {reason}")
        return 2

    print(f"OK master.pdf {result['out_pdf']} pages={result['total_pages']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
