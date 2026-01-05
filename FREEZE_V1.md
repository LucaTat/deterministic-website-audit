# Audit Tool – V1 FREEZE

## Frozen as of
2026-01-02

## Scope
- Homepage-only conversion readiness audit
- Deterministic signals (no AI)
- Client-facing narrative (EN + RO)
- Agency-grade PDF output
- Evidence snapshot (home.html)

## Contract
- audit.json is the canonical truth
- audit.pdf renders ONLY from audit.json
- Narrative must NOT invent problems when essentials are present

## Frozen Logic
- page_signals()
- scoring thresholds
- primary issue selection
- overview tone rules
- PDF structure and sections

## Allowed Changes
- Bug fixes
- New signals in separate sections
- New narrative sections (social, local, tracking)

## NOT Allowed (without version bump)
- Changing meanings of existing signals
- Rewriting narrative logic
- Adding speculative estimates (loss €, traffic)

Signed: v1 locked
