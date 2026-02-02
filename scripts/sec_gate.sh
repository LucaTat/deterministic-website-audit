#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PYTHON=""
if [[ -x "$ROOT/.venv/bin/python3" ]]; then
  PYTHON="$ROOT/.venv/bin/python3"
else
  PYTHON="$(command -v python3 || true)"
fi

if [[ -z "$PYTHON" ]]; then
  echo "ERROR: python3 not found"
  exit 2
fi

echo "Active Python: $("$PYTHON" -c 'import sys; print(sys.executable)')"

"$PYTHON" -m pytest -q

if [[ -x "$ROOT/scripts/smoke_test.sh" ]]; then
  bash "$ROOT/scripts/smoke_test.sh"
elif [[ -x "$ROOT/scripts/smoke_master_final.sh" ]]; then
  bash "$ROOT/scripts/smoke_master_final.sh"
else
  echo "SKIP: no smoke script found"
fi

RUN_PATH="${SEC_GATE_RUN:-${1:-}}"
if [[ -n "$RUN_PATH" ]]; then
  bash "$ROOT/scripts/smoke_client_bundle_includes_tools.sh" "$RUN_PATH"
  ZIP_PATH="$RUN_PATH/final/client_safe_bundle.zip"
  if [[ ! -f "$ZIP_PATH" ]]; then
    echo "ERROR: missing zip $ZIP_PATH"
    exit 2
  fi
  "$PYTHON" "$ROOT/scripts/verify_client_safe_zip.py" "$ZIP_PATH"
else
  echo "SKIP: no SEC_GATE_RUN provided"
fi
