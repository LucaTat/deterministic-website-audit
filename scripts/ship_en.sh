#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/ship_ro.sh targets.txt CAMPANIE
#
# Output:
#   deliverables/out/<CAMPANIE>/  (PDF-urile + decision brief template)
#   deliverables/out/<CAMPANIE>.zip

CLEANUP=0
TARGETS_FILE=""
CAMPAIGN=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cleanup) CLEANUP=1; shift ;;
    --campaign)
  if [[ -z "${2:-}" ]]; then
    echo "FATAL: --campaign requires a value"
    exit 2
  fi
  CAMPAIGN="$2"
  shift 2
  ;;
    *)
  if [[ -z "${TARGETS_FILE}" ]]; then
    if [[ "$1" == -* ]]; then
      echo "FATAL: Unknown option: $1"
      exit 2
    fi
    TARGETS_FILE="$1"
  fi
  shift
  ;;

  esac
done



for arg in "$@"; do
  if [[ "${arg}" == "--cleanup" ]]; then
    CLEANUP=1
  elif [[ -z "${CAMPAIGN}" ]]; then
    CAMPAIGN="${arg}"
  fi
done

if [[ -z "${TARGETS_FILE}" ]]; then
  echo "Usage: ./scripts/ship_ro.sh <targets_file.txt> <CAMPAIGN_NAME> [--cleanup]"
  exit 2
fi

if [[ -z "${CAMPAIGN}" ]]; then
  CAMPAIGN="$(date +%Y-%m-%d_%H%M)"
  echo "Auto-generated campaign name: ${CAMPAIGN}"
fi

# Move to repo root (script is in scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

if [[ ! -f "batch.py" ]]; then
  echo "FATAL: batch.py not found. Run this from the repo root."
  echo "Current: ${PWD}"
  exit 2
fi

if [[ ! -f "${TARGETS_FILE}" ]]; then
  echo "FATAL: targets file not found: ${TARGETS_FILE}"
  exit 2
fi

OUT_DIR="deliverables/out/${CAMPAIGN}"
ZIP_PATH="deliverables/out/${CAMPAIGN}.zip"
mkdir -p "${OUT_DIR}"
LANG_TAG="EN"
SAFE_CAMPAIGN="$(echo "${CAMPAIGN}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+//; s/-+$//')"

echo "== Running audit (EN) =="
RUN_LOG="${OUT_DIR}/run.log"

# Output live + log, fără să omoare scriptul din cauza pipefail
set +e
set +o pipefail
python3 batch.py --lang en --targets "${TARGETS_FILE}" 2>&1 | tee "${RUN_LOG}"
RUN_EXIT=${PIPESTATUS[0]}
set -o pipefail
set -e
if [[ "$RUN_EXIT" -ne 0 && "$RUN_EXIT" -ne 1 ]]; then
  echo "FATAL: Batch run failed with exit code ${RUN_EXIT}"
  exit 2
fi

echo "== Collecting PDFs from run output =="

LIST_FILE="$(mktemp "${OUT_DIR}/pdf_list.XXXXXX")"

grep -E "^[[:space:]]+pdf:" "${RUN_LOG}" | sed -E "s/^[[:space:]]*pdf:[[:space:]]+//" > "${LIST_FILE}"
PDF_COUNT="$(wc -l < "${LIST_FILE}" | tr -d " ")"

if [[ "${PDF_COUNT}" -eq 0 ]]; then
  echo "FATAL: No PDFs found in run log: ${RUN_LOG}"
  exit 2
fi

COPIED_COUNT=0
while read -r PDF_PATH; do
  if [[ ! -f "${PDF_PATH}" ]]; then
    echo "WARN: PDF not found (skipping): ${PDF_PATH}"
    continue
  fi
  DATE_TAG="$(basename "$(dirname "${PDF_PATH}")")"
  CLIENT_DIR="$(basename "$(dirname "$(dirname "${PDF_PATH}")")")"
  SAFE="$(echo "${CLIENT_DIR}" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g' | sed -E 's/^-+//; s/-+$//')"
  JSON_PATH="$(dirname "${PDF_PATH}")/audit.json"
  STATUS="UNKNOWN"
  if [[ -f "${JSON_PATH}" ]]; then
    MODE="$(python3 - <<'PY' "${JSON_PATH}"
import json,sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    print((json.load(f).get("mode") or "").strip())
PY
)"
    if [[ "${MODE}" == "ok" ]]; then
      STATUS="OK"
    elif [[ "${MODE}" == "broken" ]]; then
      STATUS="BROKEN"
    fi
  fi

  COUNT="$(find "${OUT_DIR}" -maxdepth 1 -name "*.pdf" -print 2>/dev/null | wc -l | tr -d " ")"
  NUM=$((COUNT + 1))
  printf -v PREFIX "%02d" "${NUM}"

  DEST="${OUT_DIR}/${PREFIX}_${SAFE}-${DATE_TAG}-${LANG_TAG}"
  if [[ -n "${SAFE_CAMPAIGN}" ]]; then
    DEST="${DEST}-${SAFE_CAMPAIGN}"
  fi
  DEST="${DEST}.pdf"
  cp -f "${PDF_PATH}" "${DEST}"
  echo "Copied: ${DEST}"
  COPIED_COUNT=$((COPIED_COUNT + 1))
done < "${LIST_FILE}"

if [[ "$COPIED_COUNT" -eq 0 ]]; then
  echo "FATAL: No PDFs were copied into ${OUT_DIR}"
  exit 2
fi

# Copy Decision Brief template (TXT) for the operator to fill
if [[ -f "deliverables/templates/DECISION_BRIEF_EN.txt" ]]; then
  cp -f "deliverables/templates/DECISION_BRIEF_EN.txt" "${OUT_DIR}/DECISION_BRIEF_EN.txt"
  echo "Added template: ${OUT_DIR}/DECISION_BRIEF_EN.txt"
else
  echo "NOTE: Decision brief template not found at deliverables/templates/DECISION_BRIEF_EN.txt"
fi


# Create ZIP
echo "== Creating ZIP =="
if ! ( cd "deliverables/out" && rm -f "${CAMPAIGN}.zip" && zip -r "${CAMPAIGN}.zip" "${CAMPAIGN}" >/dev/null ); then
  echo "FATAL: ZIP packaging failed"
  exit 2
fi
echo "ZIP ready: ${REPO_ROOT}/${ZIP_PATH}"

# End summary (safe with pipefail when there are 0 matches)
TOTAL_COUNT="$( (grep -E "^\[[0-9]+/[0-9]+\] " "${RUN_LOG}" || true) | wc -l | tr -d " " )"
OK_COUNT="$( (grep -E "^[[:space:]]+status:[[:space:]]+OK" "${RUN_LOG}" || true) | wc -l | tr -d " " )"
BROKEN_COUNT="$( (grep -E "^[[:space:]]+status:[[:space:]]+BROKEN" "${RUN_LOG}" || true) | wc -l | tr -d " " )"
echo "== Summary =="
echo "Total: ${TOTAL_COUNT} | OK: ${OK_COUNT} | BROKEN: ${BROKEN_COUNT}"
echo "Output folder: ${REPO_ROOT}/${OUT_DIR}"
echo "ZIP: ${REPO_ROOT}/${ZIP_PATH}"
if [[ "$RUN_EXIT" -eq 1 ]]; then
  echo "Run completed; some sites were BROKEN (non-fatal)."
fi

# Optional cleanup + archive
if [[ "${CLEANUP}" -eq 1 ]]; then
  TODAY="$(date +%Y-%m-%d)"
  ARCHIVE_DIR="deliverables/archive/${TODAY}/${CAMPAIGN}"
  echo "== Archiving to ${ARCHIVE_DIR} =="
  mkdir -p "${ARCHIVE_DIR}"
  cp -f "${ZIP_PATH}" "${ARCHIVE_DIR}/${CAMPAIGN}.zip"
  cp -f "${TARGETS_FILE}" "${ARCHIVE_DIR}/targets.txt"
if [[ -f "${OUT_DIR}/DECISION_BRIEF_EN.txt" ]]; then
  cp -f "${OUT_DIR}/DECISION_BRIEF_EN.txt" "${ARCHIVE_DIR}/DECISION_BRIEF_EN.txt"
fi
  if [[ -f "${RUN_LOG}" ]]; then
  cp -f "${RUN_LOG}" "${ARCHIVE_DIR}/run.log"
  fi
  TARGETS_ABS="$(cd "$(dirname "${TARGETS_FILE}")" && pwd)/$(basename "${TARGETS_FILE}")"
  DELIVERABLES_ABS="$(cd "${REPO_ROOT}/deliverables" && pwd)"
  if [[ -f "${TARGETS_FILE}" && "${TARGETS_FILE}" == *.txt && "${TARGETS_ABS}" != "${DELIVERABLES_ABS}"/* ]]; then
    rm -f "${TARGETS_FILE}"
    echo "Deleted targets file: ${TARGETS_FILE}"
  fi
  rm -f "${OUT_DIR}/run.log" "${LIST_FILE}"
  echo "Cleaned internal files from: ${OUT_DIR}"
fi

# Open output folder in Finder (macOS)
echo "== Opening output folder =="
open "${OUT_DIR}" || true

echo "DONE."
exit "$RUN_EXIT"
