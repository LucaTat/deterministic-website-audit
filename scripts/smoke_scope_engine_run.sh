#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$RUN_DIR"
}
trap cleanup EXIT

set +e
"$ROOT_DIR/scripts/scope_engine_run.sh" --url "https://example.com" --run-dir "$RUN_DIR" --lang EN --max-pages 5
code=$?
set -e
if [[ "$code" -eq 23 ]]; then
  echo "OK expected exit 23"
  exit 0
fi
echo "ERROR expected exit 23, got $code"
exit 1
