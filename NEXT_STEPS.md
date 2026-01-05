# Next steps (short)

## What changed
- Social signals are now deterministic and include evidence URLs.
- `audit.build_all_signals(html)` merges conversion signals + social signals.
- `batch.py` now uses `build_all_signals`.
- AI experiments moved to `experiments/ai_playground.py` (optional).
- `test_ai.py` removed from the main repo path.

## How to run
- Your usual batch workflow still works.
- Social signals will appear in the JSON output under keys like `instagram_linked`, `instagram_urls`, etc.

## Where AI fits
- Add AI as a post-processing step that reads the deterministic output.
- Do not let AI decide pass/fail or scores.
