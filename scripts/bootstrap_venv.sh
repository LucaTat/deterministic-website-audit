#!/bin/bash
set -euo pipefail

# Repo root
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VENV_PATH="$ROOT/.venv"

echo "== Bootstrapping .venv =="

# Create venv if missing
if [ ! -d "$VENV_PATH" ]; then
    echo "Creating virtual environment at .venv..."
    python3 -m venv "$VENV_PATH"
fi

# We can't verify 'active' inside the script same way shell does, 
# but we can use the python binary inside .venv
PYTHON="$VENV_PATH/bin/python3"
PIP="$VENV_PATH/bin/pip"

if [ ! -f "$PYTHON" ]; then
    echo "Error: Python binary not found at $PYTHON"
    exit 1
fi

echo "Using Python: $PYTHON"
"$PYTHON" --version

echo "Upgrading pip..."
"$PIP" install --upgrade pip

echo "Installing requirements..."
"$PIP" install -r "$ROOT/requirements.txt"
if [ -f "$ROOT/requirements-dev.txt" ]; then
    echo "Installing dev requirements..."
    "$PIP" install -r "$ROOT/requirements-dev.txt"
fi

echo
echo "== Bootstrap Complete =="
echo "Active Python: $("$PYTHON" -c 'import sys; print(sys.executable)')"
echo "Active Pip: $("$PIP" --version)"
echo "To run tests/tools, use: source .venv/bin/activate"
