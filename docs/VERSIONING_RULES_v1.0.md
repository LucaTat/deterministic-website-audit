# Versioning Rules v1.0

## Scope
These rules apply to product behavior and client-visible deliverables.

## Version Format
Use semantic-style versions:

- **MAJOR**: breaking changes to deliverables, outputs, or contract.
- **MINOR**: new capabilities that do not break the existing contract.
- **PATCH**: fixes and small improvements with no contract changes.

## When to Bump
- **MAJOR** when file lists, output locations, or outcome semantics change.
- **MINOR** when adding new sections, tools, or deliverables that keep backward compatibility.
- **PATCH** for stability fixes, performance improvements, and UI copy changes.

## Documentation Updates
Update release notes and versioning rules when:
- The delivery contract changes.
- Outcome semantics change (e.g., SUCCESS vs NOT AUDITABLE).
- A release is tagged.

## Compatibility
- Client-safe bundles must remain deterministic and verifiable.
- New outputs must not invalidate existing verification rules unless the version is bumped accordingly.
