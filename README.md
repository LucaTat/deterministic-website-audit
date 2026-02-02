# Deterministic Website Audit

## Overview
Deterministic website audit tool built for agencies auditing local business websites.
Focus: high-signal issues that directly impact conversions.

No AI is used in analysis. All outputs are deterministic.

## Setup
1. **Bootstrap (First Run):**
   ```bash
   bash scripts/bootstrap_venv.sh
   ```
2. **Activate:**
   ```bash
   source .venv/bin/activate
   ```
3. **Never reuse virtualenvs between `astra` and `deterministic-website-audit`.**

## Outputs
- audit.pdf → client-facing, clean, consultant-grade
- audit.json → technical evidence and raw signals

## Design Principles
- Determinism over prediction
- Clarity over completeness
- Client-facing output must be sendable without explanation
- Technical evidence must exist, but not be exposed by default

## Language Support
- Romanian (RO)
- English (EN)

## Error Handling
- Raw technical errors (SSL, DNS, timeouts, stack traces) are:
  - Stored in audit.json
  - Humanized in PDF output
- Client never sees raw stack traces

## Key Files
- batch.py → orchestration, audit logic
- pdf_export.py → PDF rendering
- humanize_fetch_error() → converts raw errors to client-friendly explanations

## Workflow
1. Add URLs to urls.txt
2. Run:
   python3 batch.py --lang ro --campaign <name> --targets urls.txt
3. Find reports in /reports/<campaign>/

## Security Gate (pre-push)
Run locally:
```bash
scripts/sec_gate.sh
```

Run with a specific run dir for bundle checks:
```bash
SEC_GATE_RUN=/path/to/RUN_DIR scripts/sec_gate.sh
```

Install git pre-push hook:
```bash
scripts/install_hooks.sh
```

## Constraints
- Do not add AI-based analysis
- Do not refactor core logic unless necessary
- Do not expose raw technical errors in PDF
- Keep audits high-signal and short

## Status
- v1 stable
- agency-ready
