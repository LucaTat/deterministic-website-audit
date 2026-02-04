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
SKIP_BUILD="${SCOPE_FINALIZE_SKIP_BUILD:-0}"

# Detect source run dir and verdict.json location
# Support multiple folder structures:
# 1. RUN_DIR/astra/verdict.json (campaign folder with astra/ subfolder)
# 2. RUN_DIR/astra/audit/verdict.json (alternative location)
# 3. RUN_DIR/audit/verdict.json (direct Astra run)
# 4. RUN_DIR/verdict.json (legacy/simple format)
SOURCE_RUN_DIR=""
if [[ -f "$RUN_DIR/astra/verdict.json" ]]; then
  SOURCE_RUN_DIR="$RUN_DIR/astra"
  VERDICT_PATH="$RUN_DIR/astra/verdict.json"
  echo "Detected campaign folder structure (astra/verdict.json)"
elif [[ -f "$RUN_DIR/astra/audit/verdict.json" ]]; then
  SOURCE_RUN_DIR="$RUN_DIR/astra"
  VERDICT_PATH="$RUN_DIR/astra/audit/verdict.json"
  echo "Detected campaign folder structure (astra/audit/verdict.json)"
elif [[ -f "$RUN_DIR/audit/verdict.json" ]]; then
  SOURCE_RUN_DIR="$RUN_DIR"
  VERDICT_PATH="$RUN_DIR/audit/verdict.json"
  echo "Detected direct run folder structure"
elif [[ -f "$RUN_DIR/verdict.json" ]]; then
  SOURCE_RUN_DIR="$RUN_DIR"
  VERDICT_PATH="$RUN_DIR/verdict.json"
  echo "Detected legacy folder structure"
else
  echo "MISSING_REQUIRED: deliverables/verdict.json" >&2
  exit 2
fi

mkdir -p "$RUN_DIR/audit" "$RUN_DIR/deliverables" "$RUN_DIR/final"

sync_dir() {
  local src="$1"
  local dest="$2"
  if [[ -d "$src" ]]; then
    mkdir -p "$dest"
    cp -a "$src/." "$dest/" 2>/dev/null || true
  fi
}

if [[ "$SOURCE_RUN_DIR" != "$RUN_DIR" ]]; then
  sync_dir "$SOURCE_RUN_DIR/audit" "$RUN_DIR/audit"
  sync_dir "$SOURCE_RUN_DIR/action_scope" "$RUN_DIR/action_scope"
  sync_dir "$SOURCE_RUN_DIR/proof_pack" "$RUN_DIR/proof_pack"
  sync_dir "$SOURCE_RUN_DIR/regression" "$RUN_DIR/regression"
  sync_dir "$SOURCE_RUN_DIR/deliverables" "$RUN_DIR/deliverables"
fi

# Ensure audit folder has verdict.json for Astra tools
if [[ ! -f "$RUN_DIR/audit/verdict.json" ]]; then
  cp "$VERDICT_PATH" "$RUN_DIR/audit/verdict.json"
  echo "Copied verdict.json to audit/"
fi

VENV_PATH="$REPO_ROOT/.venv"
if [[ "$SKIP_BUILD" != "1" && ! -x "$VENV_PATH/bin/python3" ]]; then
  if [[ -x "$REPO_ROOT/scripts/bootstrap_venv.sh" ]]; then
    echo "Bootstrapping .venv..."
    bash "$REPO_ROOT/scripts/bootstrap_venv.sh" || {
      echo "ERROR: bootstrap_venv failed" >&2
      exit 2
    }
  fi
fi

PYTHON_BIN="$VENV_PATH/bin/python3"
if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="python3"
fi

ASTRA_PY="$HOME/Desktop/astra/.venv/bin/python3"
if [[ ! -x "$ASTRA_PY" ]]; then
  ASTRA_PY="$PYTHON_BIN"
fi

AUDIT_BRIEF="$RUN_DIR/audit/report.pdf"
AUDIT_BRIEF_LANG="$RUN_DIR/audit/Decision_Brief_${LANG}.pdf"
AUDIT_EVID="$RUN_DIR/audit/Evidence_Appendix_${LANG}.pdf"

# Sync deliverables from source if needed
DELIVERABLES_SRC=""
if [[ -d "$SOURCE_RUN_DIR/deliverables" ]]; then
  DELIVERABLES_SRC="$SOURCE_RUN_DIR/deliverables"
elif [[ -d "$SOURCE_RUN_DIR/final_decision" ]]; then
  DELIVERABLES_SRC="$SOURCE_RUN_DIR/final_decision"
fi

# Generate audit/report.pdf or deliverables if missing
need_report_gen=0
if [[ ! -f "$RUN_DIR/audit/report.pdf" ]]; then
  need_report_gen=1
fi
if [[ ! -f "$RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf" || ! -f "$RUN_DIR/deliverables/Evidence_Appendix_${LANG}.pdf" ]]; then
  need_report_gen=1
fi
if [[ "$need_report_gen" -eq 1 ]]; then
  echo "Generating audit/report.pdf from verdict.json..."
  "$PYTHON_BIN" "$REPO_ROOT/scripts/generate_report_from_verdict.py" "$RUN_DIR" --lang "$LANG" || {
    echo "WARN: Could not generate audit/report.pdf"
  }
fi

# Copy Decision Brief if missing
if [[ ! -f "$RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf" ]]; then
  if [[ -f "$AUDIT_BRIEF_LANG" ]]; then
    cp -f "$AUDIT_BRIEF_LANG" "$RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf"
  elif [[ -f "$AUDIT_BRIEF" ]]; then
    cp -f "$AUDIT_BRIEF" "$RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf"
  elif [[ -n "$DELIVERABLES_SRC" && -f "$DELIVERABLES_SRC/Decision_Brief_${LANG}.pdf" ]]; then
    cp -f "$DELIVERABLES_SRC/Decision_Brief_${LANG}.pdf" "$RUN_DIR/deliverables/"
  elif [[ -f "$SOURCE_RUN_DIR/final_decision/ASTRA_Traffic_Readiness_Decision_${LANG}.pdf" ]]; then
    cp -f "$SOURCE_RUN_DIR/final_decision/ASTRA_Traffic_Readiness_Decision_${LANG}.pdf" "$RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf"
  fi
fi

# Copy Evidence Appendix if missing
if [[ ! -f "$RUN_DIR/deliverables/Evidence_Appendix_${LANG}.pdf" ]]; then
  if [[ -f "$AUDIT_EVID" ]]; then
    cp -f "$AUDIT_EVID" "$RUN_DIR/deliverables/Evidence_Appendix_${LANG}.pdf"
  elif [[ -n "$DELIVERABLES_SRC" && -f "$DELIVERABLES_SRC/Evidence_Appendix_${LANG}.pdf" ]]; then
    cp -f "$DELIVERABLES_SRC/Evidence_Appendix_${LANG}.pdf" "$RUN_DIR/deliverables/"
  fi
fi

# Copy verdict.json if missing
if [[ ! -f "$RUN_DIR/deliverables/verdict.json" ]]; then
  if [[ -f "$RUN_DIR/audit/verdict.json" ]]; then
    cp -f "$RUN_DIR/audit/verdict.json" "$RUN_DIR/deliverables/verdict.json"
  elif [[ -f "$VERDICT_PATH" ]]; then
    cp -f "$VERDICT_PATH" "$RUN_DIR/deliverables/verdict.json"
  fi
fi

# audit/report.pdf is required; generation handled above

# Validate required inputs (fail-closed)
missing_required=()
require_file() {
  local rel="$1"
  if [[ ! -f "$RUN_DIR/$rel" ]]; then
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

if [[ "$SKIP_BUILD" != "1" ]]; then
  # Run ASTRA master_final (required)
  echo "Running master_final..."
  if ! "$ASTRA_PY" -m astra.master_final.run --run-dir "$RUN_DIR" 2>&1; then
    echo "ERROR: master_final failed" >&2
    exit 2
  fi

  # Build master bundle and client-safe zip
  echo "Building master bundle..."
  bash "$REPO_ROOT/scripts/build_master_pdf.sh" "$RUN_DIR"
  "$PYTHON_BIN" "$REPO_ROOT/scripts/build_master_bundle.py" --run-dir "$RUN_DIR"
  bash "$REPO_ROOT/scripts/package_run_client_safe_zip.sh" "$RUN_DIR"
  "$PYTHON_BIN" "$REPO_ROOT/scripts/verify_client_safe_zip.py" "$RUN_DIR/final/client_safe_bundle.zip"
else
  echo "WARN: skipping build steps (SCOPE_FINALIZE_SKIP_BUILD=1)" >&2
fi

missing_outputs=()
require_output() {
  local rel="$1"
  if [[ ! -f "$RUN_DIR/$rel" ]]; then
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

# Generate checksums for every file included in the client-safe bundle
if [[ ! -f "$RUN_DIR/final/client_safe_bundle.zip" ]]; then
  echo "ERROR: client_safe_bundle.zip missing" >&2
  exit 2
fi

"$PYTHON_BIN" - <<'PY' "$RUN_DIR/final/client_safe_bundle.zip" "$RUN_DIR/final/checksums.sha256"
import hashlib
import sys
import zipfile

zip_path = sys.argv[1]
out_path = sys.argv[2]

with zipfile.ZipFile(zip_path, "r") as zf:
    names = [name for name in zf.namelist() if not name.endswith("/")]
    names.sort()
    lines = []
    for name in names:
        data = zf.read(name)
        digest = hashlib.sha256(data).hexdigest()
        lines.append(f"{digest}  {name}")

with open(out_path, "w", encoding="utf-8") as f:
    if lines:
        f.write("\n".join(lines))
        f.write("\n")
PY

if [[ ! -f "$RUN_DIR/final/checksums.sha256" ]]; then
  echo "ERROR: checksums.sha256 missing" >&2
  exit 2
fi
echo "Checksums written to final/checksums.sha256"

echo "OK FINALIZED $RUN_DIR"
