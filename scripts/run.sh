#!/usr/bin/env bash
set -euo pipefail

LANG="en"
TARGETS="urls.txt"
CAMPAIGN="2025-Q1-outreach"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang)
      LANG="${2:-}"
      shift 2
      ;;
    --targets)
      TARGETS="${2:-}"
      shift 2
      ;;
    --campaign)
      CAMPAIGN="${2:-}"
      shift 2
      ;;
    *)
      echo "Usage: ./scripts/run.sh [--lang en|ro] [--targets urls.txt] [--campaign 2025-Q1-outreach]"
      exit 1
      ;;
  esac
done

echo "== Running audit =="
echo "lang: $LANG"
echo "targets: $TARGETS"
echo "campaign: $CAMPAIGN"

python3 "$ROOT/batch.py" --lang "$LANG" --targets "$ROOT/$TARGETS" --campaign "$CAMPAIGN"
