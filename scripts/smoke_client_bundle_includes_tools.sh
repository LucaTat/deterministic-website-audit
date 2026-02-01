#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

RUN_DIR="$TMP_DIR/run_ro"
mkdir -p "$RUN_DIR/audit" "$RUN_DIR/astra/deliverables" "$RUN_DIR/action_scope" "$RUN_DIR/proof_pack" "$RUN_DIR/regression" "$RUN_DIR/final"

python3 - <<'PY' "$RUN_DIR"
import os
import sys
from reportlab.lib.pagesizes import letter
from reportlab.pdfgen import canvas

run_dir = sys.argv[1]

def make_pdf(path):
    c = canvas.Canvas(path, pagesize=letter)
    c.drawString(72, 720, "Smoke PDF")
    c.showPage()
    c.save()

make_pdf(os.path.join(run_dir, "audit", "report.pdf"))
make_pdf(os.path.join(run_dir, "astra", "deliverables", "Decision_Brief_RO.pdf"))
make_pdf(os.path.join(run_dir, "action_scope", "Action_Scope_RO.pdf"))
make_pdf(os.path.join(run_dir, "proof_pack", "Implementation_Proof_RO.pdf"))
make_pdf(os.path.join(run_dir, "regression", "Regression_Guard_RO.pdf"))
make_pdf(os.path.join(run_dir, "final", "master.pdf"))

with open(os.path.join(run_dir, "astra", "pipeline.log"), "w", encoding="utf-8") as f:
    f.write("should not ship")
PY

echo '{"version":"v1"}' > "$RUN_DIR/final/manifest.json"
echo "deadbeef  master.pdf" > "$RUN_DIR/final/checksums.sha256"

bash "$ROOT/scripts/package_run_client_safe_zip.sh" "$RUN_DIR"
ZIP_PATH="$RUN_DIR/final/client_safe_bundle.zip"
python3 "$ROOT/scripts/verify_client_safe_zip.py" "$ZIP_PATH" >/dev/null

python3 - <<'PY' "$ZIP_PATH"
import sys
import zipfile

zip_path = sys.argv[1]
required = [
    "audit/report.pdf",
    "action_scope/",
    "proof_pack/",
    "regression/",
    "final/master.pdf",
    "final/manifest.json",
    "final/checksums.sha256",
    "astra/deliverables/Decision_Brief_RO.pdf",
]
with zipfile.ZipFile(zip_path, "r") as zf:
    names = zf.namelist()
    def has_prefix(prefix):
        return any(n.startswith(prefix) for n in names)
    for item in required:
        if item.endswith("/"):
            if not has_prefix(item):
                print(f"FATAL: missing {item}")
                raise SystemExit(2)
        else:
            if item not in names:
                print(f"FATAL: missing {item}")
                raise SystemExit(2)
    if any(n.startswith("astra/scope/") for n in names):
        print("FATAL: astra/scope should not be included")
        raise SystemExit(2)
    bad = [n for n in names if n.endswith(".log") or "__pycache__" in n or n.endswith(".pyc")]
    if bad:
        print(f"FATAL: forbidden entries present: {bad}")
        raise SystemExit(2)

print("Smoke OK")
PY
