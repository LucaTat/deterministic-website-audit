#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RUN_DIR="$TMP_DIR/run_ro"
mkdir -p "$RUN_DIR/audit" "$RUN_DIR/action_scope" "$RUN_DIR/proof_pack" "$RUN_DIR/regression" "$RUN_DIR/final"

CAMPAIGN="smoke_tool1_tmp"
DATE="$(date +%Y-%m-%d)"
TARGETS_FILE="$TMP_DIR/targets.txt"
echo "OK Test,https://example.com/" > "$TARGETS_FILE"

set +e
python3 "$ROOT/batch.py" --lang ro --targets "$TARGETS_FILE" --campaign "$CAMPAIGN"
TOOL1_CODE=$?
set -e

TOOL1_ROOT="$ROOT/reports/$CAMPAIGN"
TOOL1_EVIDENCE_DIR="$(find "$TOOL1_ROOT" -type d -name evidence | sort | tail -n 1)"
TOOL1_PDF="$(find "$TOOL1_ROOT" -type f -name 'audit_ro.pdf' | sort | tail -n 1)"
TOOL1_JSON="$(find "$TOOL1_ROOT" -type f -name 'audit_ro.json' | sort | tail -n 1)"

if [[ -z "$TOOL1_EVIDENCE_DIR" || ! -d "$TOOL1_EVIDENCE_DIR" ]]; then
  echo "FATAL: missing tool1 evidence"
  exit 2
fi
if [[ -z "$TOOL1_PDF" || ! -f "$TOOL1_PDF" ]]; then
  echo "FATAL: missing tool1 pdf"
  exit 2
fi

mkdir -p "$RUN_DIR/audit" "$RUN_DIR/scope/evidence"
rsync -a "$TOOL1_EVIDENCE_DIR/" "$RUN_DIR/scope/evidence/"
cp -f "$TOOL1_PDF" "$RUN_DIR/audit/report.pdf"
if [[ -n "$TOOL1_JSON" && -f "$TOOL1_JSON" ]]; then
  cp -f "$TOOL1_JSON" "$RUN_DIR/audit/audit_ro.json"
fi

if [[ ! -f "$RUN_DIR/scope/evidence/home.html" || ! -f "$RUN_DIR/scope/evidence/pages.json" ]]; then
  echo "FATAL: missing tool1 evidence files"
  exit 2
fi
if [[ "$TOOL1_CODE" -ne 0 ]]; then
  if [[ ! -s "$RUN_DIR/audit/report.pdf" ]]; then
    echo "FATAL: tool1 failed and audit/report.pdf missing"
    exit 2
  fi
  if [[ -z "$TOOL1_JSON" || ! -f "$TOOL1_JSON" ]]; then
    echo "FATAL: tool1 failed and audit_ro.json missing"
    exit 2
  fi
fi

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

if [[ ! -s "$RUN_DIR/final/master.pdf" ]]; then
  echo "FATAL: missing or empty master.pdf"
  exit 2
fi
if [[ ! -s "$RUN_DIR/final/MASTER_BUNDLE.pdf" ]]; then
  echo "FATAL: missing or empty MASTER_BUNDLE.pdf"
  exit 2
fi

python3 - <<'PY' "$ZIP_PATH"
import sys
import zipfile

zip_path = sys.argv[1]
required = [
    "audit/report.pdf",
    "final/master.pdf",
    "final/MASTER_BUNDLE.pdf",
    "deliverables/Decision_Brief_RO.pdf",
    "deliverables/Evidence_Appendix_RO.pdf",
    "deliverables/verdict.json",
    "action_scope/action_scope.pdf",
    "proof_pack/proof_pack.pdf",
    "regression/regression.pdf",
]
with zipfile.ZipFile(zip_path, "r") as zf:
    names = zf.namelist()
    for n in sorted(names):
        print(n)
    for item in required:
        if item not in names:
            print(f"FATAL: missing {item}")
            raise SystemExit(2)

print("Smoke OK")
PY
