#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RUN_DIR="$TMP_DIR/run_ro"
mkdir -p "$RUN_DIR/audit" "$RUN_DIR/deliverables" "$RUN_DIR/action_scope" "$RUN_DIR/proof_pack" "$RUN_DIR/regression"

python3 - <<'PY' "$RUN_DIR"
import os
import sys
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas

run_dir = sys.argv[1]

def make_pdf(path, pages=1):
    c = canvas.Canvas(path, pagesize=letter)
    for i in range(pages):
        c.drawString(72, 720, f"Test page {i+1}")
        c.showPage()
    c.save()

make_pdf(os.path.join(run_dir, "audit", "report.pdf"), pages=1)
make_pdf(os.path.join(run_dir, "deliverables", "Decision_Brief_RO.pdf"), pages=1)
make_pdf(os.path.join(run_dir, "deliverables", "Evidence_Appendix_RO.pdf"), pages=1)
make_pdf(os.path.join(run_dir, "action_scope", "action_scope.pdf"), pages=1)
make_pdf(os.path.join(run_dir, "proof_pack", "proof_pack.pdf"), pages=1)
make_pdf(os.path.join(run_dir, "regression", "regression.pdf"), pages=1)
PY

bash "$ROOT/scripts/build_master_pdf.sh" "$RUN_DIR" "RO"

OUT_PDF="$RUN_DIR/final/master.pdf"
if [[ ! -f "$OUT_PDF" ]]; then
  echo "FATAL: master PDF not created"
  exit 2
fi

python3 - <<'PY' "$OUT_PDF"
import sys
from pypdf import PdfReader

path = sys.argv[1]
reader = PdfReader(path)
count = len(reader.pages)
expected = 6
if count != expected:
    print(f"FATAL: expected {expected} pages, got {count}")
    raise SystemExit(2)
print(f"OK: master PDF pages={count}")
PY

echo "Smoke test OK"
