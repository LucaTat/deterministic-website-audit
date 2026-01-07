# HANDOFF — Deterministic Audit CLI (Proof Completeness Spec Migration)

## Authoritative Context
- CONTEXT.md in repo root is authoritative.
- Deterministic signals are authoritative.
- Every finding must be evidence-backed and reproducible.
- False positives unacceptable.
- No behavior change during this phase.

## Current Phase
We are replacing per-finding `proof_completeness` logic with a spec-driven system.
Migration is in **shadow mode**: spec results are computed and compared to legacy, but do not change audit outputs.

## How Shadow Mode Works
- Run: `python3 batch.py --targets targets_ok2.txt --proof-spec shadow`
- Output includes: `proof_completeness_shadow.json` in each report folder.
- Parity requirement: `mismatch_count` MUST remain 0.

## Spec Location
- `specs/proof/proof_completeness_spec.v1.json`

## Findings Bound Under Spec Control (Static Profiles, value=partial)
- CONVLOSS_SITE_UNREACHABLE -> convloss_site_unreachable_v1
- IDX_SITEMAP_MISSING -> idx_sitemap_missing_v1
- IDX_CANONICAL_MISSING -> idx_canonical_missing_v1
- SOCIAL_TWITTER_CARD_MISSING -> social_twitter_card_missing_v1
- SOCIAL_NO_PROFILES_DETECTED -> social_no_profiles_detected_v1
- SOCIAL_OG_MISSING_CORE_TAGS -> social_og_missing_core_tags_v1

All are `mode: static`, `value: "partial"` to preserve legacy behavior.

## Latest Verification Evidence (2026-01-07)
- Ran `python3 batch.py --targets targets_ok2.txt --proof-spec shadow`
- Targets: getts.ro, wikipedia.org, httpbin.org/html
- Result: all `[OK]`
- Shadow parity: mismatch_count = 0
- SOCIAL bindings confirmed applied in shadow report
- Commit: "Bind SOCIAL proof completeness findings to spec profiles (shadow parity)" (0eb7b66)

## Non-Negotiables
- Do NOT change audit.json/audit.pdf behavior yet.
- Do NOT re-litigate product decisions in CONTEXT.md.
- Keep governance: FAIL only when confidence=high AND proof_completeness=complete.
- Changes must be deterministic and reviewable.

## Next Intended Step
Introduce first rule-based (inventory-driven) proof profile, likely starting with IDX_SITEMAP_MISSING:
- Build minimal deterministic proof inventory from existing signals only (no crawling creep).
- Add `mode: rule` profile (keep shadow parity at 0).
- Only later consider switching default behavior after parity proven across representative targets.
