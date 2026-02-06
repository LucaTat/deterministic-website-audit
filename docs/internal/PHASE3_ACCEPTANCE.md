# Phase 3 Acceptance Checklist (UI / Workflow)

## Scope
This checklist validates the operator UI lifecycle (Audit → Plan → Verify → Guard) and the
artifact‑truthful outcome rules (SUCCESS vs NOT_AUDITABLE) for a single canonical run dir.

## Preconditions
- SCOPE.app configured with Engine repo and ASTRA repo folders.
- Runs are written under a canonical `RUN_ABS` and are pinned for the session.
- No “latest run” fallbacks in UI.

## Required Artifacts
### Tool outputs (under `RUN_ABS/`)
- `audit/report.pdf` (real or stub)
- `action_scope/action_scope.pdf`
- `proof_pack/proof_pack.pdf`
- `regression/regression.pdf`

### Deliverables (under `RUN_ABS/deliverables/`)
- `Decision_Brief_{LANG}.pdf` (canonical) or legacy alias
- `Evidence_Appendix_{LANG}.pdf` (canonical) or legacy alias
- `verdict.json` (resolved via locator)

### Final bundle (under `RUN_ABS/final/`)
- `master.pdf`
- `MASTER_BUNDLE.pdf`
- `client_safe_bundle.zip`
- `checksums.sha256`

## Acceptance Runs (manual)
Run these in SCOPE.app (same campaign, same language):

1) **SUCCESS run (bundle present)**
   - Status: `SUCCESS`
   - Ready‑to‑send: **true**
   - Bundle exists + hashes OK

2) **NOT_AUDITABLE run (bundle present)**
   - Status: `NOT AUDITABLE`
   - Ready‑to‑send: **true**
   - Bundle exists + hashes OK

3) **Bundle missing case**
   - Delete or move `final/client_safe_bundle.zip`
   - Status: `SUCCESS (bundle missing)` or `NOT AUDITABLE (bundle missing)`
   - Ready‑to‑send: **false**
   - Hint shows “Finalize pending…”

## UI Rules (must hold)
- Outcome comes only from `verdict.json` (via locator).
- Bundle presence controls readiness, not outcome classification.
- Baseline selection is explicit; eligibility: same domain + lang + SUCCESS + audit complete.
- NOT_AUDITABLE is treated as a completed deliverable, not a failure.
- No absolute paths appear in user‑visible alerts.

## CLI Verification Snippets
Use these with the latest run:

```bash
BASE="$HOME/Desktop/deterministic-website-audit/deliverables/Campaigns/<campaign>/runs"
RUN="$(ls -t "$BASE" | head -n 1)"
ls -la "$BASE/$RUN/final"
unzip -l "$BASE/$RUN/final/client_safe_bundle.zip" | sed -n '1,200p'
```

If ASTRA is available, verify hashes:

```bash
RUN_DIR="$BASE/$RUN"
python3 -c "from pathlib import Path; from astra.master_final.run import verify_bundle_hashes; verify_bundle_hashes(Path('$RUN_DIR')); print('verify_bundle_hashes: OK')"
```

## Pass/Fail
- **PASS** if all three acceptance runs behave as specified and UI reflects truth.
- **FAIL** if any outcome is inferred without verdict, or if bundle presence is treated as success.
