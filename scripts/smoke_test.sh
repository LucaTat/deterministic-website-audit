#!/usr/bin/env bash
set -euo pipefail

echo "== Smoke test started =="

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATE="$(date +%Y-%m-%d)"

SMOKE_FILE="$ROOT/smoke_urls.txt"

cat > "$SMOKE_FILE" <<EOF
(no website),none
SSL Test,https://wrong.host.badssl.com/
OK Test,https://example.com/
EOF

run_and_check () {
  LANG="$1"
  CAMPAIGN="$2"

  echo "-- Running $LANG / $CAMPAIGN"
  python3 batch.py --lang "$LANG" --targets "$SMOKE_FILE" --campaign "$CAMPAIGN"

  for SITE in no_website ssl_test ok_test; do
    BASE="$ROOT/reports/$CAMPAIGN/$SITE/$DATE"

    test -f "$BASE/audit.json" || { echo "Missing audit.json ($LANG/$SITE)"; exit 1; }
    test -f "$BASE/audit.pdf"  || { echo "Missing audit.pdf ($LANG/$SITE)"; exit 1; }

    jq -e ".lang == \"$LANG\"" "$BASE/audit.json" > /dev/null \
      || { echo "Lang mismatch in JSON ($LANG/$SITE)"; exit 1; }

    pdftotext "$BASE/audit.pdf" - | rg -n "HTTPSConnectionPool|SSLError|_ssl\.c|traceback|CERTIFICATE_VERIFY_FAILED" \
      && { echo "Technical leak in PDF ($LANG/$SITE)"; exit 1; } || true
  done
}

run_and_check ro smoke_ro
run_and_check en smoke_en

rm -f "$SMOKE_FILE"

echo "== Smoke test PASSED =="

