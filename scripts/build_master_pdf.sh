#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <RUN_DIR>"
  exit 2
fi

RUN_DIR="$1"
if [[ ! -d "$RUN_DIR" ]]; then
  echo "FATAL: run dir not found: $RUN_DIR"
  exit 2
fi

OUT_PDF="$RUN_DIR/final/master.pdf"
mkdir -p "$RUN_DIR/final"

python3 -m scope.master_final --run-dir "$RUN_DIR" --out "$OUT_PDF"
