#!/usr/bin/env bash
set -euo pipefail

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

if [[ -z "${TARGETS_FILE}" ]]; then
  echo "FATAL: targets file not provided"
  exit 2
fi

if [[ ! -f "${TARGETS_FILE}" ]]; then
  echo "FATAL: targets file not found: ${TARGETS_FILE}"
  exit 2
fi

# If campaign not provided, generate one (same for both runs)
if [[ -z "${CAMPAIGN}" ]]; then
  CAMPAIGN="$(date +%F_%H%M)"
  echo "Auto-generated campaign name: ${CAMPAIGN}"
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Allow non-fatal exit codes (1 = BROKEN) without stopping the script
set +e

echo "== Running RO =="
bash "${REPO_ROOT}/scripts/ship_ro.sh" "${TARGETS_FILE}" --campaign "${CAMPAIGN}"
RO_EXIT=$?

echo "== Running EN =="
if [[ "${CLEANUP}" -eq 1 ]]; then
  bash "${REPO_ROOT}/scripts/ship_en.sh" "${TARGETS_FILE}" --campaign "${CAMPAIGN}" --cleanup
else
  bash "${REPO_ROOT}/scripts/ship_en.sh" "${TARGETS_FILE}" --campaign "${CAMPAIGN}"
fi
EN_EXIT=$?

# Re-enable strict mode
set -e

# If any run fatals, return 2 (shouldn't happen because set -e would stop, but keep explicit)
if [[ "${RO_EXIT}" -eq 2 || "${EN_EXIT}" -eq 2 ]]; then
  exit 2
fi

# If any run had BROKEN, return 1; else 0
if [[ "${RO_EXIT}" -eq 1 || "${EN_EXIT}" -eq 1 ]]; then
  exit 1
fi

exit 0
