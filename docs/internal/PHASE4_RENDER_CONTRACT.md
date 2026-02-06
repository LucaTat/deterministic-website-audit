# Phase 4 Render Contract (Draft)

## Goal
Define the strict contract for “render‑only” output generation. Rendering must be deterministic,
client‑safe, and strictly derived from existing data artifacts. No inference, no AI logic, no new facts.

## Inputs (authoritative)
Phase 4 consumes a frozen render payload derived deterministically from run artifacts.

**Canonical input file:**
- `RUN_ABS/render/render_payload.json`

**Minimum required fields (must exist; otherwise render NOT_AUDITABLE output):**
- `schema_version` (string, e.g. `"render_payload.v1"`)
- `run_id` (string)
- `domain` (string)
- `lang` (`"RO"` or `"EN"`)
- `generated_utc` (string, from run metadata; never "now")
- `outcome` (`"SUCCESS"` or `"NOT_AUDITABLE"`)
- `reason_code` (string enum; `"OK"` allowed for SUCCESS)
- `client_safe` (bool, must be `true`)

**Optional fields (may be missing):**
- `summary_counts` (object of ints)
- `top_findings` (array of structured items)
- `limitations` (array of strings)
- `evidence_index` (array describing what evidence exists; no raw HTML)

## Outputs (rendered)
Rendered outputs must be byte‑stable given identical inputs. No timestamps unless sourced from run metadata.

### Success mode
Write **canonical names only**:
- `RUN_ABS/deliverables/Decision_Brief_{LANG}.pdf`
- `RUN_ABS/deliverables/Evidence_Appendix_{LANG}.pdf`

### Not Auditable mode
- Same two PDFs, but content states “NOT AUDITABLE” with reason code and observed gate.

## Rendering Rules (non‑negotiable)
1. **No inference:** only data already present in artifacts.
2. **Deterministic:** same inputs = same outputs.
3. **Client‑safe:** no absolute paths, stack traces, or internal diagnostics.
4. **Language correctness:** RO/EN must be explicit; RO supports diacritics.
5. **No network calls:** rendering is offline and reads from run dir only.

## Data Usage
- Verdict text and reason codes are sourced from `render_payload.json` only.
- Evidence and summaries are sourced from precomputed artifacts only (via payload pointers).
- If data is missing, rendering must **not** omit sections silently. Use deterministic placeholders:
  - RO: `Date indisponibile pentru această secțiune.`
  - EN: `Data not available for this section.`

## Fonts / Localization
- RO rendering must use a font with diacritic coverage (e.g., DejaVu).
- EN and RO templates must be separated and deterministic.

## Determinism Boundaries (required)
- `generated_utc` must come from run metadata (manifest / run folder timestamp), never from current time.
- All lists must be ordered by a stable key:
  1) severity (fixed order)
  2) category
  3) id (or stable slug)
- Pagination must be deterministic:
  - fixed page template + fixed section order
  - no dynamic reordering based on content length beyond deterministic overflow rules

## Acceptance Criteria
1. Rendering produces PDFs on every successful run (or NOT_AUDITABLE run).
2. No output contains internal paths or debug strings.
3. Rerendering the same run produces identical PDFs (hash stable).
4. The rendered PDFs reflect the verdict without contradicting evidence.

## Out of Scope
- Changing verdict logic
- Data enrichment or inference
- Content generation beyond provided inputs
