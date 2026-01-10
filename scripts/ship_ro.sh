#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/ship_ro.sh targets.txt CAMPANIE
#
# Output:
#   deliverables/out/<CAMPANIE>/  (PDF-urile + decision brief template)
#   deliverables/out/<CAMPANIE>.zip

CLEANUP=0
TARGETS_FILE="${1:-}"
CAMPAIGN=""

shifted=0
if [[ -n "${TARGETS_FILE}" ]]; then
  shifted=1
  shift
fi

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

echo "== Running audit (RO) =="
RUN_LOG="${OUT_DIR}/run.log"

# Output live + log, fără să omoare scriptul din cauza pipefail
set +e
set +o pipefail
python3 batch.py --lang ro --targets "${TARGETS_FILE}" 2>&1 | tee "${RUN_LOG}"
RUN_EXIT=${PIPESTATUS[0]}
set -o pipefail
set -e
if [[ "$RUN_EXIT" -ne 0 && "$RUN_EXIT" -ne 1 ]]; then
  echo "FATAL: Batch run failed with exit code ${RUN_EXIT}"
  exit 2
fi

echo "== Collecting PDFs from run output =="

LIST_FILE="${OUT_DIR}/pdf_list.txt"

awk '
  /^\[[0-9]+\/[0-9]+\]/ {
    target=$0
    sub(/^\[[0-9]+\/[0-9]+\][[:space:]]+/, "", target)
    gsub(/[[:space:]]+$/, "", target)
    status=""
    pdf=""
    next
  }
  /^[[:space:]]+status:/ {
    status=$0
    sub(/^[[:space:]]+status:[[:space:]]+/, "", status)
    gsub(/[[:space:]]+$/, "", status)
    next
  }
  /^[[:space:]]+pdf:/ {
    pdf=$0
    sub(/^[[:space:]]+pdf:[[:space:]]+/, "", pdf)
    gsub(/[[:space:]]+$/, "", pdf)
    if (target != "" && status != "" && pdf != "") {
      safe=target
      gsub(/^https?:\/\//, "", safe)
      gsub(/\/$/, "", safe)
      gsub(/[^A-Za-z0-9._-]+/, "_", safe)
      print safe, status, pdf
    }
    next
  }
' "${RUN_LOG}" > "${LIST_FILE}"

if [[ ! -s "${LIST_FILE}" ]]; then
  echo "FATAL: No PDFs found in run log. Check: ${RUN_LOG}"
  exit 2
fi

COPIED_COUNT=0
while read -r SAFE STATUS PDF_PATH; do
  if [[ ! -f "${PDF_PATH}" ]]; then
    echo "WARN: PDF not found (skipping): ${PDF_PATH}"
    continue
  fi

  COUNT="$(find "${OUT_DIR}" -maxdepth 1 -name "*.pdf" -print 2>/dev/null | wc -l | tr -d " ")"
  NUM=$((COUNT + 1))
  printf -v PREFIX "%02d" "${NUM}"

  DEST="${OUT_DIR}/${PREFIX}_${SAFE}_${STATUS}.pdf"
  cp -f "${PDF_PATH}" "${DEST}"
  echo "Copied: ${DEST}"
  COPIED_COUNT=$((COPIED_COUNT + 1))
done < "${LIST_FILE}"

if [[ "$COPIED_COUNT" -eq 0 ]]; then
  echo "FATAL: No PDFs were copied into ${OUT_DIR}"
  exit 2
fi

# Copy Decision Brief template (TXT) for the operator to fill
if [[ -f "deliverables/templates/DECISION_BRIEF_RO.txt" ]]; then
  cp -f "deliverables/templates/DECISION_BRIEF_RO.txt" "${OUT_DIR}/DECISION_BRIEF_RO.txt"
  echo "Added template: ${OUT_DIR}/DECISION_BRIEF_RO.txt"
else
  echo "NOTE: Decision brief template not found at deliverables/templates/DECISION_BRIEF_RO.txt"
fi

# Create ZIP
echo "== Creating ZIP =="
( cd "deliverables/out" && rm -f "${CAMPAIGN}.zip" && zip -r "${CAMPAIGN}.zip" "${CAMPAIGN}" >/dev/null )
echo "ZIP ready: ${REPO_ROOT}/${ZIP_PATH}"

# Optional cleanup + archive
if [[ "${CLEANUP}" -eq 1 ]]; then
  TODAY="$(date +%Y-%m-%d)"
  ARCHIVE_DIR="deliverables/archive/${TODAY}/${CAMPAIGN}"
  echo "== Archiving to ${ARCHIVE_DIR} =="
  mkdir -p "${ARCHIVE_DIR}"
  cp -f "${ZIP_PATH}" "${ARCHIVE_DIR}/${CAMPAIGN}.zip"
  cp -f "${TARGETS_FILE}" "${ARCHIVE_DIR}/targets.txt"
  if [[ -f "${OUT_DIR}/DECISION_BRIEF_RO.txt" ]]; then
    cp -f "${OUT_DIR}/DECISION_BRIEF_RO.txt" "${ARCHIVE_DIR}/DECISION_BRIEF_RO.txt"
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
  rm -f "${OUT_DIR}/run.log" "${OUT_DIR}/pdf_list.txt"
  echo "Cleaned internal files from: ${OUT_DIR}"
fi

# Open output folder in Finder (macOS)
echo "== Opening output folder =="
open "${OUT_DIR}" || true

echo "DONE."
