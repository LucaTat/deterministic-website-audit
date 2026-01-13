#!/usr/bin/env bash
set -euo pipefail

# ========= SCOPE Silent Runner (AUTO-SHIP + RESULT_JSON) =========
# args:
#   1 = targets_file (absolute path)
#   2 = lang (ro|en|both)
#   3 = campaign_label
#   4 = cleanup (0|1)
#
# exit codes:
#   0 = OK
#   1 = BROKEN (non-fatal)
#   2 = FATAL (internal)

TARGETS_FILE="${1:-}"
LANG="${2:-ro}"
CAMPAIGN="${3:-Default}"
CLEANUP="${4:-1}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Writable run dir (from SCOPE.app). If not set, default to repo deliverables.
RUN_DIR="${SCOPE_RUN_DIR:-}"
if [[ -n "$RUN_DIR" ]]; then
  LOG_DIR="$RUN_DIR/logs"
  OUT_DIR="$RUN_DIR/out"
else
  LOG_DIR="$ROOT_DIR/deliverables/logs"
  OUT_DIR="$ROOT_DIR/deliverables"
fi
mkdir -p "$LOG_DIR" "$OUT_DIR"

ts="$(date +%F_%H-%M-%S)"
LOG_FILE="$LOG_DIR/scope_run_${ts}.log"

echo "SCOPE runner started" | tee -a "$LOG_FILE"
echo "Root: $ROOT_DIR" | tee -a "$LOG_FILE"
echo "Run dir: ${RUN_DIR:-<repo deliverables>}" | tee -a "$LOG_FILE"
echo "Log dir: $LOG_DIR" | tee -a "$LOG_FILE"
echo "Out dir: $OUT_DIR" | tee -a "$LOG_FILE"
echo "Targets: $TARGETS_FILE" | tee -a "$LOG_FILE"
echo "Lang: $LANG" | tee -a "$LOG_FILE"
echo "Campaign: $CAMPAIGN" | tee -a "$LOG_FILE"
echo "Cleanup: $CLEANUP" | tee -a "$LOG_FILE"
echo "Timestamp: $ts" | tee -a "$LOG_FILE"
echo "-------------------------------------" | tee -a "$LOG_FILE"

# Preflight
if [[ -z "$TARGETS_FILE" || ! -f "$TARGETS_FILE" ]]; then
  echo "FATAL: targets file missing: $TARGETS_FILE" | tee -a "$LOG_FILE"
  echo "RESULT_JSON={\"exit\":2,\"error\":\"targets_missing\",\"run_dir\":\"$RUN_DIR\",\"log_file\":\"$LOG_FILE\"}"
  exit 2
fi

if [[ "$LANG" != "ro" && "$LANG" != "en" && "$LANG" != "both" ]]; then
  echo "FATAL: invalid lang: $LANG" | tee -a "$LOG_FILE"
  echo "RESULT_JSON={\"exit\":2,\"error\":\"invalid_lang\",\"run_dir\":\"$RUN_DIR\",\"log_file\":\"$LOG_FILE\"}"
  exit 2
fi

# Choose python: prefer venv if present
PY="$ROOT_DIR/.venv/bin/python"
if [[ ! -x "$PY" ]]; then
  PY="$(command -v python3 || true)"
fi
if [[ -z "$PY" ]]; then
  echo "FATAL: python3 not found" | tee -a "$LOG_FILE"
  echo "RESULT_JSON={\"exit\":2,\"error\":\"python_missing\",\"run_dir\":\"$RUN_DIR\",\"log_file\":\"$LOG_FILE\"}"
  exit 2
fi

echo "PYTHON: $(command -v python3 || true)" | tee -a "$LOG_FILE"
"$PY" -V 2>&1 | tee -a "$LOG_FILE"

# Run engine (capture exit code properly)
set +e
set +o pipefail
"$PY" "$ROOT_DIR/batch.py" \
  --targets "$TARGETS_FILE" \
  --lang "$LANG" \
  --campaign "$CAMPAIGN" 2>&1 | tee -a "$LOG_FILE"
ENGINE_EXIT=${PIPESTATUS[0]}
set -o pipefail
set -e

echo "-------------------------------------" | tee -a "$LOG_FILE"
echo "Engine exit code: $ENGINE_EXIT" | tee -a "$LOG_FILE"
echo "Log file: $LOG_FILE" | tee -a "$LOG_FILE"

# AUTO-SHIP: copy PDFs into Desktop/PDF ready to ship/<YYYY-MM-DD>/<Campaign>/
TODAY="$(date +%F)"
SHIP_BASE="$HOME/Desktop/PDF ready to ship/$TODAY/$CAMPAIGN"
mkdir -p "$SHIP_BASE"

# Collect PDFs from reports/<CAMPAIGN>/**/audit.pdf
REPORTS_DIR="$ROOT_DIR/reports/$CAMPAIGN"
PDFS_JSON="[]"
SHIPPED_PDFS=()

if [[ -d "$REPORTS_DIR" ]]; then
  while IFS= read -r -d '' pdf; do
    rel="${pdf#$REPORTS_DIR/}"
    site_dir="$(echo "$rel" | cut -d'/' -f1)"
    date_dir="$(echo "$rel" | cut -d'/' -f2)"
    out_pdf="$SHIP_BASE/${site_dir}_${date_dir}.pdf"
    cp -f "$pdf" "$out_pdf"
    SHIPPED_PDFS+=("$out_pdf")
  done < <(find "$REPORTS_DIR" -type f -name "audit.pdf" -print0)
fi

# Create ZIP of shipped folder
ZIP_PATH="$HOME/Desktop/PDF ready to ship/$TODAY/${CAMPAIGN}.zip"
rm -f "$ZIP_PATH"
( cd "$HOME/Desktop/PDF ready to ship/$TODAY" && /usr/bin/zip -qr "${CAMPAIGN}.zip" "$CAMPAIGN" ) || true

# Build PDFs JSON array
if [[ ${#SHIPPED_PDFS[@]} -gt 0 ]]; then
  # JSON-escape minimal: replace backslash and quote
  json_escape() {
    echo -n "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
  }
  PDFS_JSON="["
  first=1
  for p in "${SHIPPED_PDFS[@]}"; do
    pj=$(json_escape "$p")
    if [[ $first -eq 1 ]]; then
      PDFS_JSON="${PDFS_JSON}${pj}"
      first=0
    else
      PDFS_JSON="${PDFS_JSON},${pj}"
    fi
  done
  PDFS_JSON="${PDFS_JSON}]"
fi

# Emit contract line (one line)
# NOTE: run_dir may be empty if not provided; still useful.
echo "RESULT_JSON={\"exit\":$ENGINE_EXIT,\"campaign\":\"$CAMPAIGN\",\"today\":\"$TODAY\",\"root\":\"$ROOT_DIR\",\"run_dir\":\"$RUN_DIR\",\"log_file\":\"$LOG_FILE\",\"ship_dir\":\"$SHIP_BASE\",\"zip\":\"$ZIP_PATH\",\"pdfs\":$PDFS_JSON}"

exit "$ENGINE_EXIT"

