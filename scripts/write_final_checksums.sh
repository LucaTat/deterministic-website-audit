#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "ERROR usage: $0 <RUN_DIR>"
  exit 2
fi

RUN_DIR="$1"
if [[ ! -d "$RUN_DIR" ]]; then
  echo "ERROR run dir not found"
  exit 2
fi

FINAL_DIR="$RUN_DIR/final"
MASTER_PDF="$FINAL_DIR/master.pdf"
ZIP_PATH="$FINAL_DIR/client_safe_bundle.zip"
OUT_PATH="$FINAL_DIR/checksums.sha256"

if [[ ! -f "$MASTER_PDF" ]]; then
  echo "ERROR missing master.pdf"
  exit 2
fi
if [[ ! -f "$ZIP_PATH" ]]; then
  echo "ERROR missing client_safe_bundle.zip"
  exit 2
fi

{
  h1="$(shasum -a 256 "$MASTER_PDF" | awk '{print $1}')"
  h2="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
  printf "%s  %s\n" "$h1" "$(basename "$MASTER_PDF")"
  printf "%s  %s\n" "$h2" "$(basename "$ZIP_PATH")"
} > "$OUT_PATH"

echo "OK checksums"
