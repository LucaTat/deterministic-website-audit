#!/usr/bin/env bash
set -euo pipefail

# Tool 4 — Regression Guard
# Compares current run to baseline to detect regressions; generates deterministic PDF if needed

if [[ $# -ne 1 ]]; then
  echo "ERROR tool4 usage: run_tool4_regression.sh <RUN_DIR>"
  exit 2
fi

RUN_DIR="$1"
if [[ ! -d "$RUN_DIR" ]]; then
  echo "ERROR tool4 run dir missing: $RUN_DIR"
  exit 2
fi
RUN_DIR="$(cd "$RUN_DIR" && pwd)"

# Detect effective run dir and verdict.json location
# Prefer canonical run dir first; fall back to legacy subfolders if needed.
if [[ -f "$RUN_DIR/audit/verdict.json" ]]; then
  EFFECTIVE_RUN_DIR="$RUN_DIR"
  VERDICT_PATH="$RUN_DIR/audit/verdict.json"
elif [[ -f "$RUN_DIR/verdict.json" ]]; then
  EFFECTIVE_RUN_DIR="$RUN_DIR"
  VERDICT_PATH="$RUN_DIR/verdict.json"
elif [[ -f "$RUN_DIR/astra/verdict.json" ]]; then
  EFFECTIVE_RUN_DIR="$RUN_DIR/astra"
  VERDICT_PATH="$RUN_DIR/astra/verdict.json"
elif [[ -f "$RUN_DIR/astra/audit/verdict.json" ]]; then
  EFFECTIVE_RUN_DIR="$RUN_DIR/astra"
  VERDICT_PATH="$RUN_DIR/astra/audit/verdict.json"
else
  echo "ERROR tool4 no verdict.json found in $RUN_DIR"
  exit 2
fi

echo "Using verdict.json"

# Ensure audit folder has verdict.json
if [[ ! -f "$EFFECTIVE_RUN_DIR/audit/verdict.json" ]]; then
  mkdir -p "$EFFECTIVE_RUN_DIR/audit"
  cp "$VERDICT_PATH" "$EFFECTIVE_RUN_DIR/audit/verdict.json"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$EFFECTIVE_RUN_DIR/regression"
mkdir -p "$TARGET_DIR"
PDF_PATH="$TARGET_DIR/regression.pdf"

PYTHON="$REPO_ROOT/.venv/bin/python3"
if [[ ! -x "$PYTHON" ]]; then
  PYTHON="python3"
fi

LANG="$("$PYTHON" - <<'PY' "$VERDICT_PATH" 2>/dev/null || true
import json
import sys
path = sys.argv[1]
try:
    data = json.load(open(path, "r", encoding="utf-8"))
    lang = str(data.get("lang") or "RO").strip().upper()
    print("RO" if lang == "RO" else "EN")
except Exception:
    print("RO")
PY
)"
if [[ "$LANG" != "RO" && "$LANG" != "EN" ]]; then
  LANG="RO"
fi

# Try premium Astra first  
ASTRA_DIR="$HOME/Desktop/astra"
ASTRA_PY="$ASTRA_DIR/.venv/bin/python3"

if [[ -x "$ASTRA_PY" ]]; then
  echo "Running premium Astra tool4..."
  
  URL=$("$PYTHON" - <<'PY' "$VERDICT_PATH" 2>/dev/null || true
import json
import sys
path = sys.argv[1]
try:
    data = json.load(open(path, "r", encoding="utf-8"))
    print(str(data.get("url_input") or data.get("final_url") or "").strip())
except Exception:
    pass
PY
)
  
  if [[ -n "$URL" ]]; then
    RUNS_ROOT=$(dirname "$EFFECTIVE_RUN_DIR")
    set +e
    astra_output="$("$ASTRA_PY" -m astra.tool4.run --url "$URL" --out-root "$RUNS_ROOT" --lang "$LANG" --run-dir "$RUN_DIR" 2>&1)"
    astra_status=$?
    set -e
    if [[ -n "$astra_output" ]]; then
      echo "$astra_output"
    fi
    actual_run_dir="$(echo "$astra_output" | sed -n 's/^ASTRA_RUN_DIR=//p' | head -n 1 | tr -d '\r')"
    if [[ -n "$actual_run_dir" ]]; then
      resolved_actual="$(cd "$actual_run_dir" 2>/dev/null && pwd || echo "$actual_run_dir")"
      if [[ "$resolved_actual" != "$RUN_DIR" ]]; then
        echo "ERROR tool4 run dir mismatch"
        exit 2
      fi
    fi
    if [[ "$astra_status" -eq 0 ]]; then
      echo "Premium Astra tool4 completed"
    else
      echo "WARN: Astra tool4 failed"
      ASTRA_PY=""
    fi
  else
    echo "WARN: Could not extract URL"
    ASTRA_PY=""
  fi
fi

# Ensure a compliant PDF (>=2 pages)
needs_pdf=0
if [[ ! -f "$PDF_PATH" ]]; then
  needs_pdf=1
else
  if ! "$PYTHON" - <<'PY' "$PDF_PATH" >/dev/null 2>&1; then
import sys
from pypdf import PdfReader
path = sys.argv[1]
try:
    pages = len(PdfReader(path).pages)
except Exception:
    raise SystemExit(2)
raise SystemExit(0 if pages >= 2 else 2)
PY
    needs_pdf=1
  fi
fi

if [[ "$needs_pdf" -eq 1 ]]; then
  if ! "$PYTHON" "$REPO_ROOT/scripts/build_tool_pdf.py" --run-dir "$EFFECTIVE_RUN_DIR" --tool tool4 --lang "$LANG" >/dev/null; then
    echo "ERROR tool4 pdf"
    exit 2
  fi
fi

if [[ ! -f "$PDF_PATH" ]]; then
  echo "ERROR tool4 pdf"
  exit 2
fi
if ! "$PYTHON" - <<'PY' "$PDF_PATH" >/dev/null 2>&1; then
import sys
from pypdf import PdfReader
path = sys.argv[1]
try:
    pages = len(PdfReader(path).pages)
except Exception:
    raise SystemExit(2)
raise SystemExit(0 if pages >= 2 else 2)
PY
  echo "ERROR tool4 pdf"
  exit 2
fi

# Generate summary.json
SUMMARY_PATH="$TARGET_DIR/summary.json"
if ! "$PYTHON" "$REPO_ROOT/scripts/write_tool_summary.py" "$EFFECTIVE_RUN_DIR" "regression" "regression/regression.pdf" >/dev/null; then
  echo "ERROR tool4 summary"
  exit 2
fi

echo "OK tool4 $PDF_PATH"
