#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$ROOT/.git/hooks"
SOURCE="$ROOT/.githooks/pre-push"
TARGET="$HOOKS_DIR/pre-push"

if [[ ! -d "$HOOKS_DIR" ]]; then
  echo "ERROR: .git/hooks not found"
  exit 2
fi

mkdir -p "$ROOT/.githooks"
if [[ ! -f "$SOURCE" ]]; then
  echo "ERROR: missing $SOURCE"
  exit 2
fi

ln -sf "$SOURCE" "$TARGET"
chmod +x "$SOURCE"
echo "OK installed pre-push hook"
