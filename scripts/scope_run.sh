#!/bin/bash
set -euo pipefail

# Contract:
# 1) targets_file (abs path)
# 2) lang: ro|en|both
# 3) campaign_label
# 4) cleanup: 0|1

TARGETS_FILE="${1:-}"
LANG_SEL="${2:-ro}"
CAMPAIGN="${3:-Default}"
CLEANUP="${4:-1}"

if [[ -z "$TARGETS_FILE" ]]; then
  echo "FATAL: missing targets_file"
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/deliverables/logs"
TS="$(date +"%Y-%m-%d_%H-%M-%S")"
TODAY="$(date +%Y-%m-%d)"
mkdir -p "$LOG_DIR"

SAFE_CAMPAIGN="$(echo "$CAMPAIGN" | tr ' /' '__' | tr -cd '[:alnum:]_-.')"
LOG_FILE="$LOG_DIR/scope_${SAFE_CAMPAIGN}_${LANG_SEL}_${TS}.log"
log(){ echo "$1" | tee -a "$LOG_FILE"; }

log "SCOPE runner started"
log "Root: $ROOT_DIR"
log "Targets input: $TARGETS_FILE"
log "Lang: $LANG_SEL"
log "Campaign: $CAMPAIGN"
log "Cleanup: $CLEANUP"
log "--------------------------------"

cd "$ROOT_DIR"

# Validate targets file
if [[ ! -f "$TARGETS_FILE" ]]; then
  log "FATAL: targets file not found: $TARGETS_FILE"
  echo "SCOPE_LOG_FILE=$LOG_FILE"
  exit 2
fi

TARGETS_CONTENT="$(cat "$TARGETS_FILE" | tr -d '\r' | sed '/^\s*$/d' || true)"
if [[ -z "$TARGETS_CONTENT" ]]; then
  log "FATAL: targets file is empty after trimming."
  echo "SCOPE_LOG_FILE=$LOG_FILE"
  exit 2
fi

log "Targets preview (first 3 lines):"
echo "$TARGETS_CONTENT" | head -n 3 | tee -a "$LOG_FILE"

SHIP_RO="$ROOT_DIR/scripts/ship_ro.sh"
SHIP_EN="$ROOT_DIR/scripts/ship_en.sh"

if [[ ! -f "$SHIP_RO" || ! -f "$SHIP_EN" ]]; then
  log "FATAL: ship scripts missing. Expected:"
  log " - $SHIP_RO"
  log " - $SHIP_EN"
  echo "SCOPE_LOG_FILE=$LOG_FILE"
  exit 2
fi

chmod +x "$SHIP_RO" "$SHIP_EN" 2>/dev/null || true

OUT_BASE="$ROOT_DIR/deliverables/out"

run_ship () {
  local L="$1"
  local SHIP="$2"
  local CAMP="$3"
  local TMP_DIR="$ROOT_DIR/deliverables/tmp"
  local SAFE_CAMP
  SAFE_CAMP="$(echo "$CAMP" | tr ' /' '__' | tr -cd '[:alnum:]_-.')"
  local TMP_TARGETS="$TMP_DIR/scope_targets_${SAFE_CAMP}_${L}_${TS}.txt"

  log ""
  log "=== RUN SHIP: $L ==="
  log "Script: $SHIP"
  log "Campaign(out): $CAMP"

  mkdir -p "$TMP_DIR"
  cp -f "$TARGETS_FILE" "$TMP_TARGETS"

  # ship scripts require: <targets_file> <campaign_name> [--cleanup] (and support --campaign too)
  set +e
  set +o pipefail
  if [[ "$CLEANUP" == "1" ]]; then
    /bin/bash "$SHIP" "$TMP_TARGETS" --campaign "$CAMP" --cleanup 2>&1 | tee -a "$LOG_FILE"
  else
    /bin/bash "$SHIP" "$TMP_TARGETS" --campaign "$CAMP" 2>&1 | tee -a "$LOG_FILE"
  fi
  local CODE="${PIPESTATUS[0]}"
  set -o pipefail
  set -e

  log "=== EXIT SHIP: $L CODE: $CODE ==="

  # Emit machine-friendly outputs for the app
  local ZIP_PATH="$OUT_BASE/${CAMP}.zip"
  local OUT_DIR="$OUT_BASE/${CAMP}"
  echo "SCOPE_OUT_DIR_${L}=$OUT_DIR"
  echo "SCOPE_ZIP_${L}=$ZIP_PATH"

  return "$CODE"
}

overall=0

case "$LANG_SEL" in
  ro)
    run_ship "ro" "$SHIP_RO" "${CAMPAIGN}_ro" || overall=$?
    ;;
  en)
    run_ship "en" "$SHIP_EN" "${CAMPAIGN}_en" || overall=$?
    ;;
  both)
    code_ro=0
    code_en=0
    run_ship "ro" "$SHIP_RO" "${CAMPAIGN}_ro" || code_ro=$?
    run_ship "en" "$SHIP_EN" "${CAMPAIGN}_en" || code_en=$?

    if [[ "$code_ro" -eq 2 || "$code_en" -eq 2 ]]; then
      overall=2
    elif [[ "$code_ro" -eq 1 || "$code_en" -eq 1 ]]; then
      overall=1
    else
      overall=0
    fi
    ;;
  *)
    log "FATAL: invalid lang '$LANG_SEL' (expected ro|en|both)"
    overall=2
    ;;
esac

log ""
log "SCOPE runner finished with code: $overall"
echo "SCOPE_LOG_FILE=$LOG_FILE"

if [[ "$overall" -eq 0 || "$overall" -eq 1 ]]; then
  BASE_CAMPAIGN="${CAMPAIGN}"
  shopt -s nocasematch
  if [[ "${BASE_CAMPAIGN}" =~ ^(.*)_(ro|en)$ ]]; then
    BASE_CAMPAIGN="${BASH_REMATCH[1]}"
  fi
  shopt -u nocasematch

  ARCHIVE_ROOT="$ROOT_DIR/deliverables/archive/${TODAY}/${BASE_CAMPAIGN}"
  ARCHIVE_LOG_DIR="${ARCHIVE_ROOT}/logs"
  mkdir -p "${ARCHIVE_LOG_DIR}"
  ARCHIVE_LOG_PATH="${ARCHIVE_LOG_DIR}/scope_${BASE_CAMPAIGN}_${LANG_SEL}_${TS}.log"
  cp -f "${LOG_FILE}" "${ARCHIVE_LOG_PATH}"

  ARCHIVE_ROOT_ABS="$(cd "${ARCHIVE_ROOT}" && pwd)"
  ARCHIVE_LOG_ABS="$(cd "${ARCHIVE_LOG_DIR}" && pwd)/$(basename "${ARCHIVE_LOG_PATH}")"
  echo "SCOPE_SHIP_ROOT=${ARCHIVE_ROOT_ABS}"
  echo "SCOPE_LOG_ARCHIVED=${ARCHIVE_LOG_ABS}"
fi

exit "$overall"
