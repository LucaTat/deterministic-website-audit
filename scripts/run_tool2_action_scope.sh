#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "ERROR tool2 usage"
  exit 2
fi

RUN_DIR="$1"
if [[ ! -d "$RUN_DIR" ]]; then
  echo "ERROR tool2 run dir missing"
  exit 2
fi

TARGET_DIR="$RUN_DIR/action_scope"
mkdir -p "$TARGET_DIR"
PDF_PATH="$TARGET_DIR/action_scope.pdf"

PYTHON=".venv/bin/python3"
if [[ ! -x "$PYTHON" ]]; then
  echo "ERROR tool2 venv missing"
  exit 2
fi

if ! "$PYTHON" - <<'PY' "$PDF_PATH" >/dev/null 2>&1; then
import sys
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas

path = sys.argv[1]
canvas = canvas.Canvas(path, pagesize=letter)
canvas.setFont("Helvetica", 14)
canvas.drawString(72, 720, "Action Scope")
canvas.showPage()
canvas.save()
PY
  echo "ERROR tool2 write"
  exit 2
fi

if ! "$PYTHON" scripts/write_tool_summary.py "$RUN_DIR" "action_scope" "action_scope/action_scope.pdf" >/dev/null 2>&1; then
  echo "ERROR tool2 summary"
  exit 2
fi

echo "OK tool2 $PDF_PATH"
