#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

PY="$ROOT/.venv/bin/python3"
if [[ ! -x "$PY" ]]; then
  echo "FATAL: expected venv python not found: $PY" >&2
  echo "Run: python3 -m venv .venv && source .venv/bin/activate && python3 -m pip install -r requirements.txt -r requirements-dev.txt" >&2
  exit 2
fi

echo "== SEC_GATE =="
echo "Repo: $ROOT"
echo "Python: $PY"
echo

# Tests
"$PY" -m pytest -q

# Smoke (make sure it sees the venv python)
# If smoke script expects the venv to be 'active', set VIRTUAL_ENV + PATH explicitly.
export VIRTUAL_ENV="$ROOT/.venv"
export PATH="$ROOT/.venv/bin:$PATH"

# Optional override for scripts that look for SMOKE_AUTO_VENV
export SMOKE_AUTO_VENV="${SMOKE_AUTO_VENV:-1}"

if [[ -x "$ROOT/scripts/smoke_test.sh" ]]; then
  bash "$ROOT/scripts/smoke_test.sh"
elif [[ -x "$ROOT/scripts/smoke_master_final.sh" ]]; then
  # If this needs a RUN path, sec_gate can be called with one; otherwise skip.
  if [[ "${1:-}" != "" ]]; then
    bash "$ROOT/scripts/smoke_master_final.sh" "$1"
  else
    echo "WARN: smoke_master_final.sh requires a RUN path; skipping (provide RUN as arg or SEC_GATE_RUN env)."
  fi
else
  echo "WARN: no smoke script found; skipping smoke."
fi

# Optional bundle checks when RUN provided
RUN="${SEC_GATE_RUN:-${1:-}}"
if [[ -n "${RUN}" ]]; then
  if [[ -x "$ROOT/scripts/smoke_client_bundle_includes_tools.sh" ]]; then
    bash "$ROOT/scripts/smoke_client_bundle_includes_tools.sh" "$RUN"
  fi
  ZIP="$RUN/final/client_safe_bundle.zip"
  if [[ -f "$ZIP" ]]; then
    "$PY" "$ROOT/scripts/verify_client_safe_zip.py" "$ZIP"
  else
    echo "FATAL: expected zip missing: $ZIP" >&2
    exit 3
  fi
fi

echo "== SEC_GATE PASSED =="
