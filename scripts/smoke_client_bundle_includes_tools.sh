#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RUN_DIR="$TMP_DIR/run_ro"
mkdir -p "$RUN_DIR/audit" "$RUN_DIR/action_scope" "$RUN_DIR/proof_pack" "$RUN_DIR/regression" "$RUN_DIR/final"

python3 - <<'PY' "$RUN_DIR"
import os
import sys
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas

run_dir = sys.argv[1]

def make_pdf(path):
    c = canvas.Canvas(path, pagesize=letter)
    c.drawString(72, 720, "Smoke PDF")
    c.showPage()
    c.save()

make_pdf(os.path.join(run_dir, "audit", "report.pdf"))
make_pdf(os.path.join(run_dir, "action_scope", "action_scope.pdf"))
make_pdf(os.path.join(run_dir, "proof_pack", "proof_pack.pdf"))
make_pdf(os.path.join(run_dir, "regression", "regression.pdf"))
PY

if ! bash "$ROOT/scripts/run_paid_audit.sh" "$RUN_DIR"; then
  echo "FATAL: run_paid_audit failed"
  exit 2
fi

ZIP_PATH="$RUN_DIR/final/client_safe_bundle.zip"
if [[ ! -f "$ZIP_PATH" ]]; then
  echo "FATAL: missing client_safe_bundle.zip"
  exit 2
fi
python3 "$ROOT/scripts/verify_client_safe_zip.py" "$ZIP_PATH" >/dev/null

python3 - <<'PY' "$ZIP_PATH"
import sys
import zipfile

zip_path = sys.argv[1]
required = [
    "audit/report.pdf",
    "final/master.pdf",
    "deliverables/Decision_Brief_RO.pdf",
    "deliverables/Evidence_Appendix_RO.pdf",
    "deliverables/verdict.json",
    "action_scope/action_scope.pdf",
    "proof_pack/proof_pack.pdf",
    "regression/regression.pdf",
]
with zipfile.ZipFile(zip_path, "r") as zf:
    names = zf.namelist()
    for item in required:
        if item not in names:
            print(f"FATAL: missing {item}")
            raise SystemExit(2)

print("Smoke OK")
PY
