# Usage Guide

## What this tool does
This tool generates a client‑ready website audit (PDF + JSON) that highlights key risks and opportunities for visibility, trust, and conversion.

## Requirements
- python3
- Optional for the safety gate: `jq` and `pdftotext` (Poppler)

## Quick start (3 steps)
1) Create `urls.txt` (see format below).
2) Run the audit:
```bash
./scripts/run.sh --lang ro --targets urls.txt --campaign 2025-Q1-outreach
```
3) Open the PDF in the reports folder.

## Create urls.txt
Each line can be either:

- Name + URL:
```
Acme Dental,https://example.com/
```
- URL only:
```
https://example.com/
```

## Run audits
Use the helper script:
```bash
./scripts/run.sh --lang ro --targets urls.txt --campaign 2025-Q1-outreach
```

Defaults:
- `--lang en`
- `--targets urls.txt`
- `--campaign 2025-Q1-outreach`

## Where outputs are saved
```
reports/<campaign>/<client>/<date>/
```

## What each file means
- `audit.pdf`: client‑ready report
- `audit.json`: full structured output (for internal use)
- `evidence/home.html`: snapshot of the homepage (when available)

## Safety gate (smoke test)
Run:
```bash
./scripts/smoke_test.sh
```
This checks that audits generate valid outputs and that PDFs don’t leak technical error strings.

## Troubleshooting
- Python not found: use `python3` or install Python 3.
- Missing `jq` or `pdftotext` (Poppler): install them with your package manager.
