#!/usr/bin/env bash
set -euo pipefail

echo "== Smoke test started =="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATE="$(date +%Y-%m-%d)"

SMOKE_FILE="$ROOT/scripts/smoke_targets.txt"

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

    test -f "$BASE/audit.json" || { echo "Missing audit.json ($LANG/$SITE)"; exit 1; }
    test -f "$BASE/audit.pdf"  || { echo "Missing audit.pdf ($LANG/$SITE)"; exit 1; }

    jq -e ".mode and .lang and (.client_narrative.overview | type == \"array\") and (.client_narrative.primary_issue.title | type == \"string\") and (.client_narrative.secondary_issues | type == \"array\") and (.client_narrative.plan | type == \"array\")" "$BASE/audit.json" > /dev/null \
      || { echo "Schema mismatch in JSON ($LANG/$SITE)"; exit 1; }

    jq -e ".lang == \"$LANG\"" "$BASE/audit.json" > /dev/null \
      || { echo "Lang mismatch in JSON ($LANG/$SITE)"; exit 1; }

    jq -e "if .mode == \"broken\" then (.signals.reason | type == \"string\" and length > 0) else true end" "$BASE/audit.json" > /dev/null \
      || { echo "Broken mode missing reason ($LANG/$SITE)"; exit 1; }

    jq -e "if .mode == \"ok\" then (.html | type == \"string\" and length > 0) else true end" "$BASE/audit.json" > /dev/null \
      || { echo "OK mode missing html ($LANG/$SITE)"; exit 1; }

    pdftotext "$BASE/audit.pdf" - | rg -n "HTTPSConnectionPool|SSLError|_ssl\.c|traceback|CERTIFICATE_VERIFY_FAILED" \
      && { echo "Technical leak in PDF ($LANG/$SITE)"; exit 1; } || true
  done
}

run_and_check ro smoke_ro
run_and_check en smoke_en

echo "== Smoke test PASSED =="
