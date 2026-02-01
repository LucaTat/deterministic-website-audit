#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <DET_RUN_DIR>"
  exit 2
fi

DET_RUN_DIR="$1"
if [[ ! -d "$DET_RUN_DIR" ]]; then
  echo "ERROR run dir not found"
  exit 2
fi

RUN_DIR="$(cd "$DET_RUN_DIR" && pwd)"
RUN_BASE="$(basename "$RUN_DIR")"

FINAL_DIR="$RUN_DIR/final"
mkdir -p "$FINAL_DIR"

LANG=""
if [[ -f "$FINAL_DIR/manifest.json" ]]; then
  LANG="$(python3 - <<'PY' "$FINAL_DIR/manifest.json" || true
import json
import sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    value = (data.get("lang") or "").strip().upper()
    if value in ("RO", "EN"):
        print(value)
except Exception:
    pass
PY
)"
fi

if [[ -z "$LANG" ]]; then
  case "$RUN_BASE" in
    *_ro|*_RO) LANG="RO";;
    *_en|*_EN) LANG="EN";;
  esac
fi

if [[ -z "$LANG" ]]; then
  if [[ -f "$RUN_DIR/deliverables/Decision_Brief_RO.pdf" && ! -f "$RUN_DIR/deliverables/Decision_Brief_EN.pdf" ]]; then
    LANG="RO"
  elif [[ -f "$RUN_DIR/deliverables/Decision_Brief_EN.pdf" && ! -f "$RUN_DIR/deliverables/Decision_Brief_RO.pdf" ]]; then
    LANG="EN"
  fi
fi

if [[ -z "$LANG" ]]; then
  echo "ERROR language missing"
  exit 2
fi

REQ_FILES=(
  "audit/report.pdf"
  "deliverables/Decision_Brief_${LANG}.pdf"
  "deliverables/Evidence_Appendix_${LANG}.pdf"
  "deliverables/verdict.json"
  "final/master.pdf"
)

OPT_FILES=()
if [[ -f "$RUN_DIR/action_scope/action_scope.pdf" ]]; then
  OPT_FILES+=("action_scope/action_scope.pdf")
fi
if [[ -f "$RUN_DIR/proof_pack/proof_pack.pdf" ]]; then
  OPT_FILES+=("proof_pack/proof_pack.pdf")
fi
if [[ -f "$RUN_DIR/regression/regression.pdf" ]]; then
  OPT_FILES+=("regression/regression.pdf")
fi

for rel in "${REQ_FILES[@]}"; do
  if [[ ! -f "$RUN_DIR/$rel" ]]; then
    echo "ERROR missing required: $rel"
    exit 2
  fi
done

ZIP_LIST="$(mktemp "$RUN_DIR/zip_list.XXXXXX")"
printf "%s\n" "${REQ_FILES[@]}" "${OPT_FILES[@]}" | LC_ALL=C sort -u > "$ZIP_LIST"

if [[ ! -s "$ZIP_LIST" ]]; then
  echo "ERROR empty zip list"
  rm -f "$ZIP_LIST"
  exit 2
fi

ZIP_PATH="$FINAL_DIR/client_safe_bundle.zip"
if ! ( rm -f "$ZIP_PATH" && cd "$RUN_DIR" && zip "$ZIP_PATH" -@ < "$ZIP_LIST" >/dev/null ); then
  echo "ERROR zip failed"
  rm -f "$ZIP_LIST"
  exit 2
fi

rm -f "$ZIP_LIST"

if [[ -d "$FINAL_DIR/client_safe_bundle" ]]; then
  rm -rf "$FINAL_DIR/client_safe_bundle"
fi
if [[ -f "$FINAL_DIR/.DS_Store" ]]; then
  rm -f "$FINAL_DIR/.DS_Store"
fi
find "$FINAL_DIR" -name ".DS_Store" -type f -delete >/dev/null 2>&1 || true

echo "OK $ZIP_PATH"
