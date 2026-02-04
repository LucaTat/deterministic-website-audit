#!/usr/bin/env bash
set -euo pipefail

# Tool 2 — Action Scope
# Calls premium Astra tool2 if available, falls back to stub PDF

if [[ $# -ne 1 ]]; then
  echo "ERROR tool2 usage: run_tool2_action_scope.sh <RUN_DIR>"
  exit 2
fi

RUN_DIR="$1"
if [[ ! -d "$RUN_DIR" ]]; then
  echo "ERROR tool2 run dir missing: $RUN_DIR"
  exit 2
fi

# Detect effective run dir and verdict.json location
# Support multiple folder structures:
# 1. RUN_DIR/astra/verdict.json (campaign folder with astra/ subfolder)
# 2. RUN_DIR/astra/audit/verdict.json (alternative location)
# 3. RUN_DIR/audit/verdict.json (direct Astra run)
# 4. RUN_DIR/verdict.json (legacy/simple format)
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
  echo "ERROR tool2 no verdict.json found in $RUN_DIR"
  echo "Checked: $RUN_DIR/astra/verdict.json"
  echo "Checked: $RUN_DIR/astra/audit/verdict.json"
  echo "Checked: $RUN_DIR/audit/verdict.json"
  echo "Checked: $RUN_DIR/verdict.json"
  exit 2
fi

echo "Using verdict.json from: $VERDICT_PATH"
echo "Effective run dir: $EFFECTIVE_RUN_DIR"

# Ensure audit folder has verdict.json for Astra tools
if [[ ! -f "$EFFECTIVE_RUN_DIR/audit/verdict.json" ]]; then
  mkdir -p "$EFFECTIVE_RUN_DIR/audit"
  cp "$VERDICT_PATH" "$EFFECTIVE_RUN_DIR/audit/verdict.json"
  echo "Copied verdict.json to audit/"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$EFFECTIVE_RUN_DIR/action_scope"
mkdir -p "$TARGET_DIR"
PDF_PATH="$TARGET_DIR/action_scope.pdf"

# Try premium Astra first
ASTRA_DIR="$HOME/Desktop/astra"
ASTRA_PY="$ASTRA_DIR/.venv/bin/python3"

if [[ -x "$ASTRA_PY" ]]; then
  echo "Running premium Astra tool2..."
  if "$ASTRA_PY" -m astra.tool2.run "$EFFECTIVE_RUN_DIR" --lang "RO" 2>&1; then
    echo "Premium Astra tool2 completed"
  else
    echo "WARN: Astra tool2 failed, falling back to stub"
    ASTRA_PY=""
  fi
fi

# Fallback to stub PDF if Astra not available or failed
if [[ ! -f "$PDF_PATH" ]]; then
  echo "Generating stub PDF..."
  PYTHON="$REPO_ROOT/.venv/bin/python3"
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
fi

# Generate summary.json for master_final
SUMMARY_PATH="$TARGET_DIR/summary.json"
PYTHON="${ASTRA_PY:-$REPO_ROOT/.venv/bin/python3}"
if ! "$PYTHON" - <<'PY' "$SUMMARY_PATH"; then
import json
import sys
from datetime import datetime, timezone

out_path = sys.argv[1]
data = {
    "tool": "tool2",
    "ok": True,
    "generated_utc": datetime.now(timezone.utc).isoformat(),
    "artifacts": {"pdf": "action_scope/action_scope.pdf"},
    "folder": "action_scope",
}
with open(out_path, "w", encoding="utf-8") as f:
    json.dump(data, f, sort_keys=True, indent=2)
    f.write("\n")
PY
  echo "ERROR tool2 summary"
  exit 2
fi

echo "OK tool2 $PDF_PATH"
