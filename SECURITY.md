# SECURITY

## Security model
SCOPE/ASTRA is designed to be deterministic and evidence-first. Security controls are applied to reduce common audit-run risks (command execution, SSRF, unsafe XML parsing) without changing audit verdict logic.

## Key guarantees (operator-stable security line)
- No shell-based command execution for ASTRA runs from SCOPE.app (prevents shell injection vectors).
- Network fetching is hardened:
  - URL validation is enforced before requests
  - redirects are handled with strict limits
  - proxy environment variables are not trusted (prevents proxy-based request hijacking)
- XML parsing is hardened using defusedxml (prevents XXE-style entity expansion attacks).

## Security gate
A single deterministic gate is enforced:
- `scripts/sec_gate.sh` runs:
  - `pytest`
  - smoke test(s)
- Pre-push hook executes the gate to prevent insecure/regressed changes from being pushed.

## Reporting
If you find a security issue:
- Create a private report (preferred) or open an issue with "SECURITY" in the title and minimal reproduction steps.
- Do not include client data or any secrets in reports.
