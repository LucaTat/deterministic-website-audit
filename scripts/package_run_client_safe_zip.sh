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

LANG=""
case "$RUN_BASE" in
  *_ro|*_RO) LANG="ro";;
  *_en|*_EN) LANG="en";;
esac

if [[ -z "$LANG" ]]; then
  if [[ -f "$RUN_DIR/astra/verdict.json" ]]; then
    LANG="$(python3 - <<'PY' "$RUN_DIR/astra/verdict.json" || true
import json
import sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    value = (data.get("lang") or "").strip().lower()
    if value in ("ro", "en"):
        print(value)
except Exception:
    pass
PY
)"
  fi
fi

if [[ -z "$LANG" ]]; then
  if [[ -f "$RUN_DIR/scope/audit_ro.json" ]]; then
    LANG="ro"
  elif [[ -f "$RUN_DIR/scope/audit_en.json" ]]; then
    LANG="en"
  fi
fi

if [[ -z "$LANG" ]]; then
  echo "ERROR language missing"
  exit 2
fi

LANG_UP="$(printf "%s" "$LANG" | tr '[:lower:]' '[:upper:]')"

FILES=()

FINAL_PDF="$RUN_DIR/astra/final_decision/ASTRA_Traffic_Readiness_Decision_${LANG_UP}.pdf"
if [[ -f "$FINAL_PDF" ]]; then
  FILES+=("$FINAL_PDF")
else
  for f in "$RUN_DIR"/astra/Decision_Brief_*_"${LANG_UP}".pdf; do
    if [[ -f "$f" ]]; then
      FILES+=("$f")
    fi
  done
fi

for f in "$RUN_DIR"/astra/Decision_Brief_*_"${LANG_UP}".pdf; do
  if [[ -f "$f" ]]; then
    FILES+=("$f")
  fi
done

for f in "$RUN_DIR"/astra/Evidence_Appendix_*_"${LANG_UP}".pdf; do
  if [[ -f "$f" ]]; then
    FILES+=("$f")
  fi
done

if [[ -f "$RUN_DIR/scope/report.pdf" ]]; then
  FILES+=("$RUN_DIR/scope/report.pdf")
fi

for f in "$RUN_DIR"/tool2/*.pdf "$RUN_DIR"/tool3/*.pdf "$RUN_DIR"/tool4/*.pdf; do
  if [[ -f "$f" ]]; then
    FILES+=("$f")
  fi
done

if [[ -f "$RUN_DIR/astra/verdict.json" ]]; then
  FILES+=("$RUN_DIR/astra/verdict.json")
fi

if [[ -f "$RUN_DIR/scope/evidence_pack.json" ]]; then
  FILES+=("$RUN_DIR/scope/evidence_pack.json")
fi

INCLUDE_DIRS=("audit" "astra" "action_scope" "proof_pack" "regression" "final")
for d in "${INCLUDE_DIRS[@]}"; do
  if [[ -d "$RUN_DIR/$d" ]]; then
    while IFS= read -r -d '' f; do
      FILES+=("$f")
    done < <(find "$RUN_DIR/$d" -type f -print0)
  fi
done

if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "ERROR no files"
  exit 2
fi

ZIP_LIST="$(mktemp "$RUN_DIR/zip_list.XXXXXX")"
printf "%s\n" "${FILES[@]}" | LC_ALL=C sort -u > "$ZIP_LIST"

ZIP_LIST_FILTERED="$(mktemp "$RUN_DIR/zip_list.filtered.XXXXXX")"
rg -v '(^|/)\.run_state\.json$|(^|/)pipeline\.log$|(^|/)version\.json$|\.log$|(^|/)__pycache__(/|$)|\.pyc$|(^|/)\.DS_Store$|(^|/)node_modules(/|$)|(^|/)(\.venv|venv)(/|$)|(^|/)__MACOSX(/|$)|(^|/)\._' "$ZIP_LIST" > "$ZIP_LIST_FILTERED" || true
mv -f "$ZIP_LIST_FILTERED" "$ZIP_LIST"

ZIP_LIST_REL="$(mktemp "$RUN_DIR/zip_list.rel.XXXXXX")"
while read -r ZIP_PATH_ITEM; do
  if [[ "$ZIP_PATH_ITEM" == "$RUN_DIR/"* ]]; then
    echo "${ZIP_PATH_ITEM#${RUN_DIR}/}" >> "$ZIP_LIST_REL"
  else
    echo "$(basename "$ZIP_PATH_ITEM")" >> "$ZIP_LIST_REL"
  fi
done < "$ZIP_LIST"

LC_ALL=C sort -u "$ZIP_LIST_REL" > "$ZIP_LIST"
rm -f "$ZIP_LIST_REL"

if [[ ! -s "$ZIP_LIST" ]]; then
  echo "ERROR empty zip list"
  rm -f "$ZIP_LIST"
  exit 2
fi

FINAL_DIR="$RUN_DIR/final"
mkdir -p "$FINAL_DIR"
ZIP_PATH="$FINAL_DIR/client_safe_bundle.zip"
if ! ( rm -f "$ZIP_PATH" && cd "$RUN_DIR" && zip "$ZIP_PATH" -@ < "$ZIP_LIST" >/dev/null ); then
  echo "ERROR zip failed"
  rm -f "$ZIP_LIST"
  exit 2
fi

rm -f "$ZIP_LIST"

echo "OK $ZIP_PATH"
