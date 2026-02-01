#!/usr/bin/env bash
set -euo pipefail

echo "== Smoke test started =="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATE="$(date +%Y-%m-%d)"

# Resolve repo root (assuming script is in scripts/)
EXPECTED_VENV="$ROOT/.venv"

# Helper to print version info
print_versions() {
    echo "Using source: $ROOT"
    echo "Active Python: $(python3 -c 'import sys; print(sys.executable)')"
    echo "Active Pip: $(python3 -m pip --version)"
    echo "----------------------------------------"
}

# Verify VENV
if [[ "${VIRTUAL_ENV:-}" != "$EXPECTED_VENV" ]]; then
    if [[ "${SMOKE_AUTO_VENV:-}" == "1" ]]; then
        if [ -f "$EXPECTED_VENV/bin/activate" ]; then
            echo "Auto-activating venv..."
            source "$EXPECTED_VENV/bin/activate"
        else
            echo "ERROR: SMOKE_AUTO_VENV=1 set, but .venv not found at $EXPECTED_VENV"
            exit 2
        fi
    else
        echo "ERROR: strictly enforced venv policy violation for deterministic-website-audit."
        echo "Current Python: $(python3 -c 'import sys; print(sys.executable)')"
        echo "Expected VENV:  $EXPECTED_VENV"
        echo
        echo "Expected venv:  $EXPECTED_VENV"
        echo ""
        echo "To run correctly:"
        echo "  bash scripts/bootstrap_venv.sh"
        echo "  source .venv/bin/activate"
        echo "  ./scripts/smoke_test.sh"
        echo ""
        echo "Or run with auto-activation: SMOKE_AUTO_VENV=1 ./scripts/smoke_test.sh"
        exit 2
    fi
fi

# 2. Assert correctness (double check)
PYTHON_PATH="$(python3 -c 'import sys; print(sys.executable)')"
if [[ "$PYTHON_PATH" != *"$EXPECTED_VENV"* ]]; then
    echo "FATAL: Failed to switch to expected venv!"
    echo "Active: $PYTHON_PATH"
    echo "Wanted: $EXPECTED_VENV"
    exit 2
fi

print_versions

SMOKE_FILE="$ROOT/scripts/smoke_targets.txt"

python3 "$ROOT/scripts/guardrails_test.py"
python3 "$ROOT/scripts/verify_sitemap_safety.py"

run_and_check () {
  LANG="$1"
  CAMPAIGN="$2"

  echo "-- Running $LANG / $CAMPAIGN"
  set +e
  python3 batch.py --lang "$LANG" --targets "$SMOKE_FILE" --campaign "$CAMPAIGN"
  EXIT_CODE=$?
  set -e
  if [[ "$EXIT_CODE" -ne 1 ]]; then
    if [[ "$EXIT_CODE" -eq 2 ]]; then
      echo "Batch run failed fatally ($LANG/$CAMPAIGN)"
      exit 1
    fi
    echo "Unexpected exit code $EXIT_CODE ($LANG/$CAMPAIGN)"
    exit 1
  fi

  for SITE in no_website ssl_test ok_test dns_test; do
    BASE="$ROOT/reports/$CAMPAIGN/$SITE/$DATE"

    test -f "$BASE/audit_${LANG}.json" || { echo "Missing audit_${LANG}.json ($LANG/$SITE)"; exit 1; }
    test -f "$BASE/audit_${LANG}.pdf"  || { echo "Missing audit_${LANG}.pdf ($LANG/$SITE)"; exit 1; }

    jq -e ".mode and .lang and (.client_narrative.overview | type == \"array\") and (.client_narrative.primary_issue.title | type == \"string\") and (.client_narrative.secondary_issues | type == \"array\") and (.client_narrative.plan | type == \"array\")" "$BASE/audit_${LANG}.json" > /dev/null \
      || { echo "Schema mismatch in JSON ($LANG/$SITE)"; exit 1; }

    jq -e ".lang == \"$LANG\"" "$BASE/audit_${LANG}.json" > /dev/null \
      || { echo "Lang mismatch in JSON ($LANG/$SITE)"; exit 1; }

    jq -e "if .mode == \"broken\" then (.signals.reason | type == \"string\" and length > 0) else true end" "$BASE/audit_${LANG}.json" > /dev/null \
      || { echo "Broken mode missing reason ($LANG/$SITE)"; exit 1; }

    jq -e "if .mode == \"ok\" then (.html | type == \"string\" and length > 0) else true end" "$BASE/audit_${LANG}.json" > /dev/null \
      || { echo "OK mode missing html ($LANG/$SITE)"; exit 1; }

    pdftotext "$BASE/audit_${LANG}.pdf" - | rg -n "HTTPSConnectionPool|SSLError|_ssl\.c|traceback|CERTIFICATE_VERIFY_FAILED" \
      && { echo "Technical leak in PDF ($LANG/$SITE)"; exit 1; } || true
  done
}

run_and_check ro smoke_ro
run_and_check en smoke_en

if [[ "${PACKAGE_RUN_ZIP_SMOKE:-}" == "1" ]]; then
  if [[ -z "${PACKAGE_RUN_ZIP_DIR:-}" ]]; then
    echo "FATAL: PACKAGE_RUN_ZIP_SMOKE=1 requires PACKAGE_RUN_ZIP_DIR=<DET_RUN_DIR>"
    exit 2
  fi
  bash "$ROOT/scripts/package_run_client_safe_zip.sh" "$PACKAGE_RUN_ZIP_DIR"
  ZIP_PATH="${PACKAGE_RUN_ZIP_DIR}/client_safe_bundle_$(basename "$PACKAGE_RUN_ZIP_DIR").zip"
  python3 "$ROOT/scripts/verify_client_safe_zip.py" "$ZIP_PATH"
fi

echo "== Smoke test PASSED =="
