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

RUN_BASE="$(basename "$RUN_DIR")"
LANG=""
case "$RUN_BASE" in
  *_ro|*_RO) LANG="RO";;
  *_en|*_EN) LANG="EN";;
esac

if [[ -z "$LANG" ]]; then
  echo "FATAL: unable to determine LANG from run dir" >&2
  exit 1
fi

DEST_DIR="$RUN_DIR/final"
DEST_ZIP="$DEST_DIR/client_safe_bundle.zip"

mkdir -p "$DEST_DIR" >/dev/null 2>&1 || true

rm -rf "$RUN_DIR/astra" "$RUN_DIR/final_decision" || true

ASTRA_PY="$HOME/Desktop/astra/.venv/bin/python3"
if [[ ! -x "$ASTRA_PY" ]]; then
  echo "FATAL: ASTRA venv python missing: $ASTRA_PY" >&2
  exit 1
fi

"$ASTRA_PY" -m astra.run_full_pipeline --det-run-dir "$RUN_DIR" --lang "$LANG" --force

ASTRA_BRIEF="$RUN_DIR/astra/deliverables/Decision_Brief_${LANG}.pdf"
ASTRA_VERDICT="$RUN_DIR/astra/deliverables/verdict.json"
if [[ ! -f "$ASTRA_BRIEF" ]]; then
  echo "FATAL: missing Decision Brief" >&2
  exit 1
fi
if [[ ! -f "$ASTRA_VERDICT" ]]; then
  echo "FATAL: missing astra verdict.json" >&2
  exit 1
fi

if ! bash scripts/build_master_pdf.sh "$RUN_DIR" >/dev/null; then
  echo "ERROR build master pdf"
  exit 2
fi

if ! .venv/bin/python3 scripts/write_final_manifest.py "$RUN_DIR" >/dev/null; then
  echo "ERROR write manifest"
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

if ! bash scripts/write_final_checksums.sh "$RUN_DIR" >/dev/null; then
  echo "ERROR write checksums"
  exit 2
fi

if ! .venv/bin/python3 scripts/verify_client_safe_zip.py "$DEST_ZIP" >/dev/null; then
  echo "ERROR verify client zip"
  exit 2
fi

echo "OK paid_audit $DEST_ZIP"
