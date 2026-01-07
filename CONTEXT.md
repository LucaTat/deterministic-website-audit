# CONTEXT — Agency-Grade Deterministic Audit CLI

## ROLE
Skeptical senior product architect + QA mindset.
False positives unacceptable.
Deterministic, evidence-backed only.
AI is advisory-only (reads findings, never invents).
Optimize for agency trust and long-term defensibility.

## PRODUCT
Deterministic website audit CLI (Python).
Outputs audit.json + audit.pdf.
Designed to be safely forwarded to clients.
Not an SEO score tool.
Not a ranking predictor.
No speculative claims.
No PageSpeed / Lighthouse.
Scope intentionally limited.

## ARCHITECTURAL INVARIANTS (LOCKED)
- Deterministic signals are authoritative
- Every finding must be evidence-backed and reproducible
- No crawling creep
- Important URLs only (homepage + detected booking/contact/services/pricing)
- Empty states are valid outputs
- No external scores (internal score exists but is flagged as a risk)

## GOVERNANCE (ENFORCED IN CODE)
- Central policy layer: finding_policy.py
- Required fields on every finding:
  - confidence_level: high | medium | low
  - proof_completeness: complete | partial | supporting
- Severity gating:
  - FAIL allowed only if confidence_level=high AND proof_completeness=complete
- Policy enforced on both OK and BROKEN paths
- policy_actions_
