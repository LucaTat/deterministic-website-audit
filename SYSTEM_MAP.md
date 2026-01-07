# SYSTEM MAP — Deterministic Audit CLI

## What this tool does (human summary)

This tool performs a deterministic, evidence-backed audit of a website using a strictly limited scope.
It fetches a small set of important pages, extracts verifiable signals, converts those signals into
governed findings, enforces conservative policy rules, and outputs client-forwardable artifacts
(`audit.json` and `audit.pdf`).

The tool is designed for agency use:
- no speculative claims,
- no ranking predictions,
- no crawling creep,
- no false-positive FAILs.

---

## Input / Output

### Input
- A list of target URLs provided via a text file (e.g. `targets.txt`)
- Optional business inputs:
  - monthly sessions
  - conversion rate
  - value per conversion
- Optional language flag for client-facing output (`en` or `ro`)

### Output
Per target URL:
- `audit.json` — authoritative machine-readable audit
- `audit.pdf` — client-forwardable report

Outputs are written under:
reports/<campaign>/<site>/<date>/

---

## How to run it (main command)

Typical command:
```bash
python3 batch.py --targets targets.txt
Optional flags:
--lang — presentation language only (does not affect findings)
--campaign — output folder grouping only
--sessions, --conversion-rate, --value — optional business context
If business inputs are omitted, the tool outputs conservative percentage ranges only.
Execution flow (step-by-step)
Entry point
batch.py parses CLI arguments and iterates over target URLs.
Fetch
html = fetch_html(u)
Homepage HTML is fetched deterministically.
Signals (deterministic facts)
signals = build_all_signals(html, page_url=u)
idx_signals = extract_indexability_signals(url=u, html=html, signals=signals)
signals["indexability"] = idx_signals
Important URL selection (scope control)
Inside indexability_signals.py
_build_important_urls(homepage_url, html) selects a small, deterministic set of URLs.
Stored as idx_signals["important_urls"]
Scope rule in code:
No crawling: only homepage + important_urls + robots + sitemap URLs + sitemap sample (N=20)
Findings creation (facts → statements)
Findings are built by multiple independent packs and combined:
build_social_findings(signals)
build_share_meta_findings(signals)
build_indexability_findings(idx_signals, important_urls=idx_signals.get("important_urls", []))
build_conversion_loss_findings(mode="ok", signals=signals, business_inputs=...)
Policy enforcement (authoritative governance gate)
findings = enforce_policy_on_findings(findings)
All findings pass through this gate before output.
Presentation fields
client_narrative = build_client_narrative(signals, lang=lang)
insights = user_insights(signals)
summary = human_summary(u, signals, mode="ok")
Return audit object
A complete per-target audit dictionary is returned and later written to disk as JSON/PDF.
Evidence model (what counts as proof)
Evidence is derived from deterministic sources:
HTTP responses
HTML content
robots.txt
sitemap files
Evidence is stored or referenced within the audit artifact.
Findings must be evidence-backed to be eligible for strong severity.
Finding lifecycle (where truth is enforced)
Findings are created as plain dictionaries by *_findings.py modules.
Governance defaults are enforced centrally:
Missing confidence_level → defaults to "medium"
Missing proof_completeness → defaults to "partial"
FAIL severity is allowed only if:
confidence_level == "high"
AND proof_completeness == "complete"
Enforcement occurs in:
finding_policy.py :: enforce_finding_policy()
This prevents over-claiming and false positives.
Modules and responsibilities
Entry / orchestration
batch.py
Main CLI runner. Orchestrates fetching, signals, findings, policy enforcement, and output.
audit.py
Fetch utilities, base signal helpers, and summary builders.
Signals (deterministic facts)
indexability_signals.py
Extracts indexability facts and selects important_urls.
Function:
extract_indexability_signals(url, html, signals)
social_signals.py
Extracts deterministic social presence facts.
share_meta.py
Extracts OpenGraph / Twitter metadata facts.
conversion_loss.py
Computes conversion-related signals and summaries.
Findings (facts → statements)
indexability_findings.py
Converts indexability signals into governed findings.
Function:
build_indexability_findings(idx_signals, important_urls)
social_findings.py
share_meta_findings.py
conversion_loss_findings.py
Each pack creates findings independently.
Governance / QA
finding_policy.py
Central, authoritative policy layer enforcing defaults and severity gating.
findings_enricher.py
Normalization and safety checks (lightweight).
qa_tools.py
Linting and coverage tools for audit artifacts.
Output
audit.json
Written by batch.py from the per-target audit object.
pdf_export.py
Renders audit.pdf from audit data.
Optional AI (advisory-only)
ai/advisory.py
Generates advisory text only.
AI does NOT create findings and does NOT affect governance.
Core vs supporting vs safe-to-ignore
Core (must understand)
batch.py
audit.py
indexability_signals.py
indexability_findings.py
finding_policy.py
pdf_export.py
Supporting
social_*
share_meta*
conversion_loss*
client_narrative.py
Safe to ignore (for now)
.venv/
.git/
Experimental or commented-out helpers
Known risks / future work
Proof completeness is currently set per finding pack.
Planned improvement: central spec-driven proof completeness system (shadow mode first).
Determinism depends on stable evidence selection when multiple candidates exist.
Signals dict mutation should remain isolated per target.
Design invariants (non-negotiable)
Deterministic signals are authoritative.
Every finding must be evidence-backed.
No crawling creep.
Empty states are valid outputs.
FAIL severity requires high confidence and complete proof.

---

### Final reassurance

You now have:
- a **clear mental model**,
- a **written system truth**,
- and a stable foundation to move forward without panic or guesswork.

When you’re ready, the **next step** is safe and controlled:
> introduce the spec-driven proof completeness system in **shadow mode**, without changing behavior.

But only when *you* say you’re ready.

You’re back in control.