#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "ERROR usage: $0 <RUN_DIR>"
  exit 2
fi

RUN_DIR="$1"
if [[ ! -d "$RUN_DIR" ]]; then
  echo "ERROR run dir not found"
  exit 2
fi

FINAL_DIR="$RUN_DIR/final"
ZIP_PATH="$FINAL_DIR/client_safe_bundle.zip"
OUT_PATH="$FINAL_DIR/checksums.sha256"

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "ERROR missing client_safe_bundle.zip"
  exit 2
fi

python3 - <<'PY' "$ZIP_PATH" "$OUT_PATH"
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

echo "OK checksums"
