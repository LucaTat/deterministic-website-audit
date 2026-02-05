# Release Notes v1.0

## Summary
Version 1.0 delivers a deterministic, evidence-first audit workflow with a single pinned run folder per URL and a client-safe delivery bundle.

## Delivery Contract (Canonical Outputs)
Each successful run produces one run folder that contains:

- `deliverables/Decision_Brief_{LANG}.pdf`
- `deliverables/Evidence_Appendix_{LANG}.pdf`
- `deliverables/verdict.json`
- `final/master.pdf`
- `final/MASTER_BUNDLE.pdf`
- `final/client_safe_bundle.zip`
- `final/checksums.sha256`

All delivery buttons open files from this run folder only.

## Outcomes
Two explicit outcomes exist:

1. **SUCCESS**
   - Full audit completed.
   - Bundle contains tool PDFs and all deliverables.

2. **NOT AUDITABLE**
   - Evidence gate failed (identity mismatch, placeholder domain, or insufficient evidence).
   - A minimal, client-safe bundle is still produced with a clear “not auditable” decision.

## Client-Safe Bundle
- Strict allowlist packaging (no extra files).
- Checksums are generated and verified for all shipped artifacts.

## Evidence Gates (Fail-Closed)
A run stops if any of the following occurs:
- Final host does not match the requested host (except www/non-www).
- Placeholder domain detected.
- Evidence size too small to be reliable.

## Language Support
- English and Romanian deliverables are supported.
- Romanian diacritics are supported in client PDFs.

## Operator Notes
- A run is considered completed only when final artifacts exist in `final/`.
- NOT AUDITABLE is a completed deliverable, not a silent failure.
