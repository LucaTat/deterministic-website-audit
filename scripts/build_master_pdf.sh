#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "Usage: $0 <RUN_DIR> [LANG]"
  exit 2
fi

RUN_DIR="$1"
LANG="${2:-}"
if [[ ! -d "$RUN_DIR" ]]; then
  echo "FATAL: run dir not found: $RUN_DIR"
  exit 2
fi

OUT_PDF="$RUN_DIR/final/master.pdf"
mkdir -p "$RUN_DIR/final"

if [[ -z "$LANG" ]]; then
  if [[ -f "$RUN_DIR/deliverables/Decision_Brief_RO.pdf" && ! -f "$RUN_DIR/deliverables/Decision_Brief_EN.pdf" ]]; then
    LANG="RO"
  elif [[ -f "$RUN_DIR/deliverables/Decision_Brief_EN.pdf" && ! -f "$RUN_DIR/deliverables/Decision_Brief_RO.pdf" ]]; then
    LANG="EN"
  fi
fi

if [[ -z "$LANG" ]]; then
  echo "FATAL: language missing"
  exit 2
fi

# Required files for master PDF (strict, deterministic)
REQ=(
  "deliverables/Decision_Brief_${LANG}.pdf"
  "deliverables/Evidence_Appendix_${LANG}.pdf"
  "audit/report.pdf"
  "action_scope/action_scope.pdf"
  "proof_pack/proof_pack.pdf"
  "regression/regression.pdf"
)

for rel in "${REQ[@]}"; do
  if [[ ! -f "$RUN_DIR/$rel" ]]; then
    echo "FATAL: missing required PDF: $rel"
    exit 2
  fi
done

# Deterministic order:
# Decision Brief -> Evidence Appendix -> Audit -> Tool2 -> Tool3 -> Tool4
ORDERED=(
  "$RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf"
  "$RUN_DIR/deliverables/Evidence_Appendix_${LANG}.pdf"
  "$RUN_DIR/audit/report.pdf"
  "$RUN_DIR/action_scope/action_scope.pdf"
  "$RUN_DIR/proof_pack/proof_pack.pdf"
  "$RUN_DIR/regression/regression.pdf"
)

if command -v qpdf >/dev/null 2>&1; then
  qpdf --empty --pages "${ORDERED[@]}" -- "$OUT_PDF" || { echo "FATAL: qpdf merge failed"; exit 2; }
elif command -v pdfunite >/dev/null 2>&1; then
  pdfunite "${ORDERED[@]}" "$OUT_PDF" || { echo "FATAL: pdfunite merge failed"; exit 2; }
else
  python3 - <<'PY' "$OUT_PDF" "${ORDERED[@]}"
import sys
from pypdf import PdfWriter, PdfReader

out_path = sys.argv[1]
files = sys.argv[2:]
writer = PdfWriter()
for path in files:
    reader = PdfReader(path)
    for page in reader.pages:
        writer.add_page(page)
with open(out_path, "wb") as f:
    writer.write(f)
PY
fi
