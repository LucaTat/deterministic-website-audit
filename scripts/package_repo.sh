#!/usr/bin/env bash
set -euo pipefail

OUT="/tmp/deterministic-website-audit_clean.zip"
rm -f "$OUT"

zip -r "$OUT" . \
  -x ".git/*" ".git/**" \
  -x ".venv/*" ".venv/**" \
  -x "build/*" "build/**" \
  -x "DerivedData/*" "DerivedData/**" \
  -x "__pycache__/*" "__pycache__/**" "*/__pycache__/*" \
  -x "*.pyc" \
  -x ".ruff_cache/*" ".ruff_cache/**" \
  -x ".pytest_cache/*" ".pytest_cache/**" \
  -x ".mypy_cache/*" ".mypy_cache/**" \
  -x "reports/*" "reports/**"

echo "Wrote $OUT"
