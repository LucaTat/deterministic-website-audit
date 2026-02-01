#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <RUN_DIR>"
  exit 2
fi

RUN_DIR="$1"
if [[ ! -d "$RUN_DIR" ]]; then
  echo "ERROR run dir not found"
  exit 2
fi

DEST_DIR="$RUN_DIR/final"
DEST_ZIP="$DEST_DIR/client_safe_bundle.zip"

mkdir -p "$DEST_DIR" >/dev/null 2>&1 || true

if ! bash scripts/build_master_pdf.sh "$RUN_DIR" >/dev/null; then
  echo "ERROR build master pdf"
  exit 2
fi

if ! bash scripts/package_run_client_safe_zip.sh "$RUN_DIR" >/dev/null; then
  echo "ERROR package client zip"
  exit 2
fi

if [[ ! -f "$DEST_ZIP" ]]; then
  echo "ERROR package client zip"
  exit 2
fi

if ! .venv/bin/python3 scripts/verify_client_safe_zip.py "$DEST_ZIP" >/dev/null; then
  echo "ERROR verify client zip"
  exit 2
fi

echo "OK paid_audit $DEST_ZIP"
