#!/usr/bin/env bash
set -euo pipefail

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
ASTRA_PY="$HOME/Desktop/astra/.venv/bin/python3"

if [[ ! -x "$ASTRA_PY" ]]; then
  echo "FATAL: ASTRA venv python missing: $ASTRA_PY" >&2
  exit 2
fi

mkdir -p "$RUN_DIR/deliverables" "$RUN_DIR/final"

# Run ASTRA master_final (required)
"$ASTRA_PY" -m astra.master_final.run --run-dir "$RUN_DIR"

# Sync ASTRA deliverables
if [[ ! -f "$RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf" ]]; then
  if [[ -f "$RUN_DIR/astra/deliverables/Decision_Brief_${LANG}.pdf" ]]; then
    cp -f "$RUN_DIR/astra/deliverables/Decision_Brief_${LANG}.pdf" "$RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf"
  elif [[ -f "$RUN_DIR/final_decision/ASTRA_Traffic_Readiness_Decision_${LANG}.pdf" ]]; then
    cp -f "$RUN_DIR/final_decision/ASTRA_Traffic_Readiness_Decision_${LANG}.pdf" "$RUN_DIR/deliverables/Decision_Brief_${LANG}.pdf"
  else
    echo "FATAL: missing Decision_Brief_${LANG}.pdf" >&2
    exit 2
  fi
fi

if [[ ! -f "$RUN_DIR/deliverables/Evidence_Appendix_${LANG}.pdf" ]]; then
  if [[ -f "$RUN_DIR/astra/deliverables/Evidence_Appendix_${LANG}.pdf" ]]; then
    cp -f "$RUN_DIR/astra/deliverables/Evidence_Appendix_${LANG}.pdf" "$RUN_DIR/deliverables/Evidence_Appendix_${LANG}.pdf"
  else
    echo "FATAL: missing Evidence_Appendix_${LANG}.pdf" >&2
    exit 2
  fi
fi

if [[ ! -f "$RUN_DIR/deliverables/verdict.json" ]]; then
  if [[ -f "$RUN_DIR/astra/verdict.json" ]]; then
    cp -f "$RUN_DIR/astra/verdict.json" "$RUN_DIR/deliverables/verdict.json"
  elif [[ -f "$RUN_DIR/astra/deliverables/verdict.json" ]]; then
    cp -f "$RUN_DIR/astra/deliverables/verdict.json" "$RUN_DIR/deliverables/verdict.json"
  else
    echo "FATAL: missing verdict.json" >&2
    exit 2
  fi
fi

bash "$REPO_ROOT/scripts/build_master_pdf.sh" "$RUN_DIR"
"$REPO_ROOT/.venv/bin/python3" "$REPO_ROOT/scripts/build_master_bundle.py" --run-dir "$RUN_DIR"
bash "$REPO_ROOT/scripts/package_run_client_safe_zip.sh" "$RUN_DIR"
"$REPO_ROOT/.venv/bin/python3" "$REPO_ROOT/scripts/verify_client_safe_zip.py" "$RUN_DIR/final/client_safe_bundle.zip"

if ! command -v shasum >/dev/null 2>&1; then
  echo "FATAL: shasum not found" >&2
  exit 2
fi

FILES=(
  "final/master.pdf"
  "final/MASTER_BUNDLE.pdf"
  "final/client_safe_bundle.zip"
  "deliverables/Decision_Brief_${LANG}.pdf"
  "deliverables/Evidence_Appendix_${LANG}.pdf"
  "deliverables/verdict.json"
  "audit/report.pdf"
  "action_scope/action_scope.pdf"
  "proof_pack/proof_pack.pdf"
  "regression/regression.pdf"
)

for f in "${FILES[@]}"; do
  if [[ ! -f "$RUN_DIR/$f" ]]; then
    echo "FATAL: missing required: $f" >&2
    exit 2
  fi
done

( cd "$RUN_DIR" && shasum -a 256 "${FILES[@]}" > "$RUN_DIR/final/checksums.sha256" )

echo "OK FINALIZED $RUN_DIR"
