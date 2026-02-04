#!/usr/bin/env bash
set -euo pipefail

# Finalize Run — Produces master.pdf, MASTER_BUNDLE.pdf, client_safe_bundle.zip, checksums

if [[ $# -lt 2 ]]; then
  echo "FATAL: usage: $0 <RUN_DIR_ABS> <LANG>" >&2
  exit 2
fi

RUN_DIR="$1"
LANG="$2"

if [[ ! -d "$RUN_DIR" ]]; then
  echo "FATAL: run dir not found" >&2
  exit 2
fi

if [[ "$LANG" != "RO" && "$LANG" != "EN" ]]; then
  echo "FATAL: invalid LANG (use RO or EN)" >&2
  exit 2
fi

RUN_DIR="$(cd "$RUN_DIR" && pwd)"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Detect effective run dir and verdict.json location
# Support multiple folder structures:
# 1. RUN_DIR/astra/verdict.json (campaign folder with astra/ subfolder)
# 2. RUN_DIR/astra/audit/verdict.json (alternative location)
# 3. RUN_DIR/audit/verdict.json (direct Astra run)
# 4. RUN_DIR/verdict.json (legacy/simple format)
if [[ -f "$RUN_DIR/astra/verdict.json" ]]; then
  EFFECTIVE_RUN_DIR="$RUN_DIR/astra"
  VERDICT_PATH="$RUN_DIR/astra/verdict.json"
  echo "Detected campaign folder structure (astra/verdict.json)"
elif [[ -f "$RUN_DIR/astra/audit/verdict.json" ]]; then
  EFFECTIVE_RUN_DIR="$RUN_DIR/astra"
  VERDICT_PATH="$RUN_DIR/astra/audit/verdict.json"
  echo "Detected campaign folder structure (astra/audit/verdict.json)"
elif [[ -f "$RUN_DIR/audit/verdict.json" ]]; then
  EFFECTIVE_RUN_DIR="$RUN_DIR"
  VERDICT_PATH="$RUN_DIR/audit/verdict.json"
  echo "Detected direct run folder structure"
elif [[ -f "$RUN_DIR/verdict.json" ]]; then
  EFFECTIVE_RUN_DIR="$RUN_DIR"
  VERDICT_PATH="$RUN_DIR/verdict.json"
  echo "Detected legacy folder structure"
else
  echo "MISSING_REQUIRED: deliverables/verdict.json" >&2
  exit 2
fi

# Ensure audit folder has verdict.json for Astra tools
if [[ ! -f "$EFFECTIVE_RUN_DIR/audit/verdict.json" ]]; then
  mkdir -p "$EFFECTIVE_RUN_DIR/audit"
  cp "$VERDICT_PATH" "$EFFECTIVE_RUN_DIR/audit/verdict.json"
  echo "Copied verdict.json to audit/"
fi

ASTRA_PY="$HOME/Desktop/astra/.venv/bin/python3"

if [[ ! -x "$ASTRA_PY" ]]; then
  echo "WARN: ASTRA venv python missing - using fallback" >&2
  ASTRA_PY="$REPO_ROOT/.venv/bin/python3"
fi

mkdir -p "$EFFECTIVE_RUN_DIR/deliverables" "$EFFECTIVE_RUN_DIR/final"

AUDIT_BRIEF="$EFFECTIVE_RUN_DIR/audit/report.pdf"
AUDIT_BRIEF_LANG="$EFFECTIVE_RUN_DIR/audit/Decision_Brief_${LANG}.pdf"
AUDIT_EVID="$EFFECTIVE_RUN_DIR/audit/Evidence_Appendix_${LANG}.pdf"

# Sync deliverables from astra subdirectory if needed
DELIVERABLES_SRC=""
if [[ -d "$EFFECTIVE_RUN_DIR/deliverables" ]]; then
  DELIVERABLES_SRC="$EFFECTIVE_RUN_DIR/deliverables"
elif [[ -d "$EFFECTIVE_RUN_DIR/final_decision" ]]; then
  DELIVERABLES_SRC="$EFFECTIVE_RUN_DIR/final_decision"
fi

# Generate audit/report.pdf or deliverables if missing
need_report_gen=0
if [[ ! -f "$EFFECTIVE_RUN_DIR/audit/report.pdf" ]]; then
  need_report_gen=1
fi
if [[ ! -f "$EFFECTIVE_RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf" || ! -f "$EFFECTIVE_RUN_DIR/deliverables/Evidence_Appendix_${LANG}.pdf" ]]; then
  need_report_gen=1
fi
if [[ "$need_report_gen" -eq 1 ]]; then
  echo "Generating audit/report.pdf from verdict.json..."
  "$ASTRA_PY" "$REPO_ROOT/scripts/generate_report_from_verdict.py" "$EFFECTIVE_RUN_DIR" --lang "$LANG" || {
    echo "WARN: Could not generate audit/report.pdf"
  }
fi

# Copy Decision Brief if missing
if [[ ! -f "$EFFECTIVE_RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf" ]]; then
  if [[ -f "$AUDIT_BRIEF_LANG" ]]; then
    cp -f "$AUDIT_BRIEF_LANG" "$EFFECTIVE_RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf"
  elif [[ -f "$AUDIT_BRIEF" ]]; then
    cp -f "$AUDIT_BRIEF" "$EFFECTIVE_RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf"
  elif [[ -n "$DELIVERABLES_SRC" && -f "$DELIVERABLES_SRC/Decision_Brief_${LANG}.pdf" ]]; then
    cp -f "$DELIVERABLES_SRC/Decision_Brief_${LANG}.pdf" "$EFFECTIVE_RUN_DIR/deliverables/"
  elif [[ -f "$EFFECTIVE_RUN_DIR/final_decision/ASTRA_Traffic_Readiness_Decision_${LANG}.pdf" ]]; then
    cp -f "$EFFECTIVE_RUN_DIR/final_decision/ASTRA_Traffic_Readiness_Decision_${LANG}.pdf" "$EFFECTIVE_RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf"
  fi
fi

# Copy Evidence Appendix if missing
if [[ ! -f "$EFFECTIVE_RUN_DIR/deliverables/Evidence_Appendix_${LANG}.pdf" ]]; then
  if [[ -f "$AUDIT_EVID" ]]; then
    cp -f "$AUDIT_EVID" "$EFFECTIVE_RUN_DIR/deliverables/Evidence_Appendix_${LANG}.pdf"
  elif [[ -n "$DELIVERABLES_SRC" && -f "$DELIVERABLES_SRC/Evidence_Appendix_${LANG}.pdf" ]]; then
    cp -f "$DELIVERABLES_SRC/Evidence_Appendix_${LANG}.pdf" "$EFFECTIVE_RUN_DIR/deliverables/"
  fi
fi

# Copy verdict.json if missing
if [[ ! -f "$EFFECTIVE_RUN_DIR/deliverables/verdict.json" ]]; then
  if [[ -f "$EFFECTIVE_RUN_DIR/audit/verdict.json" ]]; then
    cp -f "$EFFECTIVE_RUN_DIR/audit/verdict.json" "$EFFECTIVE_RUN_DIR/deliverables/verdict.json"
  fi
fi

# audit/report.pdf is required; generation handled above

# Validate required inputs (fail-closed)
missing_required=()
require_file() {
  local rel="$1"
  if [[ ! -f "$EFFECTIVE_RUN_DIR/$rel" ]]; then
    missing_required+=("$rel")
  fi
}

require_file "deliverables/Decision_Brief_${LANG}.pdf"
require_file "deliverables/Evidence_Appendix_${LANG}.pdf"
require_file "deliverables/verdict.json"
require_file "audit/report.pdf"
require_file "action_scope/action_scope.pdf"
require_file "proof_pack/proof_pack.pdf"
require_file "regression/regression.pdf"

if [[ ${#missing_required[@]} -gt 0 ]]; then
  printf "MISSING_REQUIRED: %s\n" "$(IFS=,; echo "${missing_required[*]}")" >&2
  exit 2
fi

# Run ASTRA master_final (required)
echo "Running master_final..."
if ! "$ASTRA_PY" -m astra.master_final.run --run-dir "$EFFECTIVE_RUN_DIR" 2>&1; then
  echo "ERROR: master_final failed" >&2
  exit 2
fi

# Build master bundle and client-safe zip
echo "Building master bundle..."
bash "$REPO_ROOT/scripts/build_master_pdf.sh" "$EFFECTIVE_RUN_DIR"
"$REPO_ROOT/.venv/bin/python3" "$REPO_ROOT/scripts/build_master_bundle.py" --run-dir "$EFFECTIVE_RUN_DIR"
bash "$REPO_ROOT/scripts/package_run_client_safe_zip.sh" "$EFFECTIVE_RUN_DIR"
"$REPO_ROOT/.venv/bin/python3" "$REPO_ROOT/scripts/verify_client_safe_zip.py" "$EFFECTIVE_RUN_DIR/final/client_safe_bundle.zip"

missing_outputs=()
require_output() {
  local rel="$1"
  if [[ ! -f "$EFFECTIVE_RUN_DIR/$rel" ]]; then
    missing_outputs+=("$rel")
  fi
}
require_output "final/master.pdf"
require_output "final/MASTER_BUNDLE.pdf"
require_output "final/client_safe_bundle.zip"
if [[ ${#missing_outputs[@]} -gt 0 ]]; then
  printf "MISSING_REQUIRED: %s\n" "$(IFS=,; echo "${missing_outputs[*]}")" >&2
  exit 2
fi

# Generate checksums
if command -v shasum >/dev/null 2>&1; then
  CHECKSUM_FILES=()
  for f in "final/master.pdf" "final/MASTER_BUNDLE.pdf" "final/client_safe_bundle.zip" \
           "deliverables/Decision_Brief_${LANG}.pdf" "deliverables/Evidence_Appendix_${LANG}.pdf" \
           "audit/report.pdf" "action_scope/action_scope.pdf" "proof_pack/proof_pack.pdf" "regression/regression.pdf"; do
    if [[ -f "$EFFECTIVE_RUN_DIR/$f" ]]; then
      CHECKSUM_FILES+=("$f")
    fi
  done
  
  if [[ ${#CHECKSUM_FILES[@]} -gt 0 ]]; then
    ( cd "$EFFECTIVE_RUN_DIR" && shasum -a 256 "${CHECKSUM_FILES[@]}" > "$EFFECTIVE_RUN_DIR/final/checksums.sha256" )
    echo "Checksums written to final/checksums.sha256"
  fi
fi

echo "OK FINALIZED $EFFECTIVE_RUN_DIR"
