# Agency Delivery Protocol

Client-safe, deterministic delivery workflow for paid audits.

## Canonical Artifacts
- `final/master.pdf`
- `final/client_safe_bundle.zip`

## Pre‑Flight Checklist
- Repo clean and on `main`.
- Venv active: `source .venv/bin/activate`.
- (Optional) Run smoke tests:
  - `./scripts/smoke_test.sh`
  - `./scripts/smoke_master_pdf.sh`

## Operator Steps (Paid Audit Delivery)
1) Locate the run directory:
   - `<RUN_DIR>` is the run folder for the audit.
2) Build the master PDF:
   - `bash scripts/build_master_pdf.sh "<RUN_DIR>"`
   - Output: `<RUN_DIR>/final/master.pdf`
3) Package client-safe ZIP:
   - `bash scripts/package_run_client_safe_zip.sh "<RUN_DIR>"`
   - Output: `<RUN_DIR>/client_safe_bundle_<run_basename>.zip`
4) Move ZIP to canonical location:
   - `mkdir -p "<RUN_DIR>/final"`
   - `mv "<RUN_DIR>/client_safe_bundle_<run_basename>.zip" "<RUN_DIR>/final/client_safe_bundle.zip"`
5) Verify ZIP:
   - `python3 scripts/verify_client_safe_zip.py "<RUN_DIR>/final/client_safe_bundle.zip"`
6) Final check:
   - Open `final/master.pdf` and confirm it renders correctly.
   - Open the ZIP and confirm files look correct and client‑safe.

## Delivery Checklist
- `final/master.pdf` exists and opens.
- `final/client_safe_bundle.zip` exists and verifies clean.
- ZIP contains only allowed files (PDFs + optional client-safe JSON).
- No internal logs or stack traces present.
- Deterministic paths confirmed under `<RUN_DIR>/final/`.

## What We Never Send
- Any `*.log`, `scope_run.log`, `pipeline.log`, `run.log`.
- Internal stack traces or debug dumps.
- Internal state files like `.run_state.json` or `version.json`.
- Raw HTML dumps.

## Notes
- Keep outputs deterministic and client‑safe.
- Never create a new run for delivery.
