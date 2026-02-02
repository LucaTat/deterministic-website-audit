#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C
export LANG=C

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

ASTRA_PY="${ASTRA_PY:-$HOME/Desktop/astra/.venv/bin/python3}"
if [[ ! -x "$ASTRA_PY" ]]; then
  echo "FATAL: ASTRA venv python missing: $ASTRA_PY" >&2
  exit 2
fi

"$ASTRA_PY" -c "import astra, pathlib; print('ASTRA_PKG=' + str(pathlib.Path(astra.__file__).resolve()))"
set +e
ASTRA_OUTPUT="$("$ASTRA_PY" -m astra.run_full_pipeline --det-run-dir "$RUN_DIR" --lang "$LANG" --force 2>&1)"
ASTRA_CODE=$?
set -e
if [[ "$ASTRA_OUTPUT" == *"Missing required summary.json after pipeline."* || "$ASTRA_CODE" -eq 2 ]]; then
  if ! bash scripts/run_tool2_action_scope.sh "$RUN_DIR"; then
    echo "FATAL: tool2 summary failed" >&2
    exit 2
  fi
  if ! bash scripts/run_tool3_proof_pack.sh "$RUN_DIR"; then
    echo "FATAL: tool3 summary failed" >&2
    exit 2
  fi
  if ! bash scripts/run_tool4_regression.sh "$RUN_DIR"; then
    echo "FATAL: tool4 summary failed" >&2
    exit 2
  fi
  ASTRA_OUTPUT="$("$ASTRA_PY" -m astra.run_full_pipeline --det-run-dir "$RUN_DIR" --lang "$LANG" --force 2>&1)"
  ASTRA_CODE=$?
fi
if [[ "$ASTRA_CODE" -ne 0 ]]; then
  echo "$ASTRA_OUTPUT"
  exit 2
fi

mkdir -p "$RUN_DIR/deliverables"

BRIEF_A="$RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf"
BRIEF_B="$RUN_DIR/astra/deliverables/Decision_Brief_${LANG}.pdf"
EVID_A="$RUN_DIR/deliverables/Evidence_Appendix_${LANG}.pdf"
EVID_B="$RUN_DIR/astra/deliverables/Evidence_Appendix_${LANG}.pdf"
VERDICT_A="$RUN_DIR/deliverables/verdict.json"
VERDICT_B="$RUN_DIR/astra/deliverables/verdict.json"
FINAL_DECISION="$RUN_DIR/final_decision/ASTRA_Traffic_Readiness_Decision_${LANG}.pdf"

if [[ ! -f "$BRIEF_A" && -f "$BRIEF_B" ]]; then
  cp -f "$BRIEF_B" "$BRIEF_A"
fi
if [[ ! -f "$EVID_A" && -f "$EVID_B" ]]; then
  cp -f "$EVID_B" "$EVID_A"
fi
if [[ ! -f "$VERDICT_A" && -f "$VERDICT_B" ]]; then
  cp -f "$VERDICT_B" "$VERDICT_A"
fi

if [[ ! -f "$BRIEF_A" ]]; then
  echo "FATAL: missing Decision Brief" >&2
  exit 1
fi
if [[ ! -f "$EVID_A" ]]; then
  echo "FATAL: missing Evidence Appendix" >&2
  exit 1
fi
if [[ ! -f "$VERDICT_A" ]]; then
  echo "FATAL: missing verdict.json" >&2
  exit 1
fi

if ! bash scripts/build_master_pdf.sh "$RUN_DIR" "$LANG" >/dev/null; then
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
