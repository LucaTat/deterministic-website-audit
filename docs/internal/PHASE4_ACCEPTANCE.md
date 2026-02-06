# Phase 4 Acceptance (Render-Only Pipeline)

Status: DRAFT until merged, then FREEZE

## Scope
Phase 4 defines render-only deliverable generation from a deterministic payload.
No crawling, no inference, no verdict logic changes.

## Acceptance Checklist

### A) Render Payload
- [ ] `RUN_ABS/render/render_payload.json` exists
- [ ] `schema_version` is `render_payload.v1`
- [ ] `generated_utc` matches run metadata (not current time)
- [ ] `outcome` is `SUCCESS` or `NOT_AUDITABLE`
- [ ] `client_safe` is `true`

### B) Canonical Deliverables
- [ ] `RUN_ABS/deliverables/Decision_Brief_{LANG}.pdf` exists
- [ ] `RUN_ABS/deliverables/Evidence_Appendix_{LANG}.pdf` exists
- [ ] Filenames are canonical (no legacy "Decision Brief - ..." copies)

### C) Content Rules
- [ ] Missing data uses placeholders:
  - RO: `Date indisponibile pentru această secțiune.`
  - EN: `Data not available for this section.`
- [ ] No absolute paths, repo names, or debug strings appear in PDFs
- [ ] Section order is stable and deterministic

### D) Bundle Integrity (SUCCESS + NOT_AUDITABLE)
- [ ] `RUN_ABS/final/client_safe_bundle.zip` exists
- [ ] `RUN_ABS/final/checksums.sha256` exists
- [ ] `verify_bundle_hashes(run_dir)` passes

## Required Manual Validation
1. Run one SUCCESS target (e.g., wikipedia.org).
2. Run one NOT_AUDITABLE target (e.g., booking.com).
3. Open Decision Brief + Evidence Appendix and confirm placeholders + timestamps.

## Freeze Criteria
Phase 4 may be frozen when:
- All checklist items are PASS for SUCCESS and NOT_AUDITABLE runs.
- No legacy deliverable filenames are generated.

## Freeze Tag
Tag name: `scope-v1.0-phase4-render-frozen`
