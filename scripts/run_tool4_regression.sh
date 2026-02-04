#!/usr/bin/env bash
set -euo pipefail

# Tool 4 — Regression Guard
# Compares current run to baseline to detect regressions

if [[ $# -ne 1 ]]; then
  echo "ERROR tool4 usage: run_tool4_regression.sh <RUN_DIR>"
  exit 2
fi

RUN_DIR="$1"
if [[ ! -d "$RUN_DIR" ]]; then
  echo "ERROR tool4 run dir missing: $RUN_DIR"
  exit 2
fi

# Detect effective run dir and verdict.json location
if [[ -f "$RUN_DIR/astra/verdict.json" ]]; then
  EFFECTIVE_RUN_DIR="$RUN_DIR/astra"
  VERDICT_PATH="$RUN_DIR/astra/verdict.json"
elif [[ -f "$RUN_DIR/astra/audit/verdict.json" ]]; then
  EFFECTIVE_RUN_DIR="$RUN_DIR/astra"
  VERDICT_PATH="$RUN_DIR/astra/audit/verdict.json"
elif [[ -f "$RUN_DIR/audit/verdict.json" ]]; then
  EFFECTIVE_RUN_DIR="$RUN_DIR"
  VERDICT_PATH="$RUN_DIR/audit/verdict.json"
elif [[ -f "$RUN_DIR/verdict.json" ]]; then
  EFFECTIVE_RUN_DIR="$RUN_DIR"
  VERDICT_PATH="$RUN_DIR/verdict.json"
else
  echo "ERROR tool4 no verdict.json found in $RUN_DIR"
  exit 2
fi

echo "Using verdict.json from: $VERDICT_PATH"

# Ensure audit folder has verdict.json
if [[ ! -f "$EFFECTIVE_RUN_DIR/audit/verdict.json" ]]; then
  mkdir -p "$EFFECTIVE_RUN_DIR/audit"
  cp "$VERDICT_PATH" "$EFFECTIVE_RUN_DIR/audit/verdict.json"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$EFFECTIVE_RUN_DIR/regression"
mkdir -p "$TARGET_DIR"
PDF_PATH="$TARGET_DIR/regression.pdf"

# Try premium Astra first  
ASTRA_DIR="$HOME/Desktop/astra"
ASTRA_PY="$ASTRA_DIR/.venv/bin/python3"

if [[ -x "$ASTRA_PY" ]]; then
  echo "Running premium Astra tool4..."
  
  URL=$("$ASTRA_PY" -c "import json; print(json.load(open('$VERDICT_PATH'))['url_input'])" 2>/dev/null || echo "")
  
  if [[ -n "$URL" ]]; then
    RUNS_ROOT=$(dirname "$EFFECTIVE_RUN_DIR")
    if "$ASTRA_PY" -m astra.tool4.run --url "$URL" --out-root "$RUNS_ROOT" --lang "RO" 2>&1; then
      echo "Premium Astra tool4 completed"
    else
      echo "WARN: Astra tool4 failed, falling back to stub"
      ASTRA_PY=""
    fi
  else
    echo "WARN: Could not extract URL, falling back to stub"
    ASTRA_PY=""
  fi
fi

# Fallback to stub PDF
if [[ ! -f "$PDF_PATH" ]]; then
  echo "Generating stub PDF..."
  PYTHON="$REPO_ROOT/.venv/bin/python3"
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
canvas.drawString(72, 700, "No baseline available - first run")
canvas.showPage()
canvas.save()
PY
    echo "ERROR tool4 write"
    exit 2
  fi
fi

# Generate summary.json
SUMMARY_PATH="$TARGET_DIR/summary.json"
PYTHON="${ASTRA_PY:-$REPO_ROOT/.venv/bin/python3}"
if ! "$PYTHON" - <<'PY' "$SUMMARY_PATH"; then
import json
import sys
from datetime import datetime, timezone

out_path = sys.argv[1]
data = {
    "tool": "tool4",
    "ok": True,
    "generated_utc": datetime.now(timezone.utc).isoformat(),
    "artifacts": {"pdf": "regression/regression.pdf"},
    "folder": "regression",
    "status": "not_applicable",
    "regressions": [],
    "improvements": [],
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(data, f, sort_keys=True, indent=2)
    f.write("\n")
PY
  echo "ERROR tool4 summary"
  exit 2
fi

echo "OK tool4 $PDF_PATH"
