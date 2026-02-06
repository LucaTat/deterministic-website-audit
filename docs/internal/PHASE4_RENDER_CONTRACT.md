# Phase 4 Render Contract (Draft)

## Goal
Define the strict contract for “render‑only” output generation. Rendering must be deterministic,
client‑safe, and strictly derived from existing data artifacts. No inference, no AI logic, no new facts.

## Inputs (authoritative)
- `deliverables/verdict.json` (resolved via locator)
- Tool PDFs and summaries (if present)
- Evidence metadata produced by Tool 1 (no network access during render)

## Outputs (rendered)
Rendered outputs must be byte‑stable given identical inputs. No timestamps unless sourced from run metadata.

### Success mode
- `Decision_Brief_{LANG}.pdf`
- `Evidence_Appendix_{LANG}.pdf`

### Not Auditable mode
- Same two PDFs, but content states “NOT AUDITABLE” with reason code and observed gate.

## Rendering Rules (non‑negotiable)
1. **No inference:** only data already present in artifacts.
2. **Deterministic:** same inputs = same outputs.
3. **Client‑safe:** no absolute paths, stack traces, or internal diagnostics.
4. **Language correctness:** RO/EN must be explicit; RO supports diacritics.
5. **No network calls:** rendering is offline and reads from run dir only.

## Data Usage
- Verdict text and reason codes are sourced from `verdict.json`.
- Evidence and summaries are sourced from precomputed artifacts only.
- If data is missing, rendering must either:
  - omit that section, or
  - state “Data not available” (client‑safe).

## Fonts / Localization
- RO rendering must use a font with diacritic coverage (e.g., DejaVu).
- EN and RO templates must be separated and deterministic.

## Acceptance Criteria
1. Rendering produces PDFs on every successful run (or NOT_AUDITABLE run).
2. No output contains internal paths or debug strings.
3. Rerendering the same run produces identical PDFs (hash stable).
4. The rendered PDFs reflect the verdict without contradicting evidence.

## Out of Scope
- Changing verdict logic
- Data enrichment or inference
- Content generation beyond provided inputs
