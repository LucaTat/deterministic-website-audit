#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "ERROR tool4 usage"
  exit 2
fi

RUN_DIR="$1"
if [[ ! -d "$RUN_DIR" ]]; then
  echo "ERROR tool4 run dir missing"
  exit 2
fi

TARGET_DIR="$RUN_DIR/regression"
mkdir -p "$TARGET_DIR"
PDF_PATH="$TARGET_DIR/regression.pdf"

PYTHON=".venv/bin/python3"
if [[ ! -x "$PYTHON" ]]; then
  echo "ERROR tool4 venv missing"
  exit 2
fi

if ! "$PYTHON" - <<'PY' "$PDF_PATH" >/dev/null 2>&1; then
import sys
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas

path = sys.argv[1]
canvas = canvas.Canvas(path, pagesize=letter)
canvas.setFont("Helvetica", 14)
canvas.drawString(72, 720, "Regression Guard")
canvas.showPage()
canvas.save()
PY
  echo "ERROR tool4 write"
  exit 2
fi

SUMMARY_PATH="$TARGET_DIR/summary.json"
if ! "$PYTHON" - <<'PY' "$SUMMARY_PATH"; then
import json
import sys
from datetime import datetime, timezone

out_path = sys.argv[1]
data = {
    "tool": "tool4",
    "ok": True,
    "generated_utc": datetime.now(timezone.utc).isoformat(),
    "artifacts": ["regression.pdf"],
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(data, f, sort_keys=True, indent=2)
    f.write("\n")
PY
  echo "ERROR tool4 summary"
  exit 2
fi

echo "OK tool4 $PDF_PATH"
