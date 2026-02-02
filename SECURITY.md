# SECURITY

## Security model
This project is deterministic and evidence-first. Security controls reduce common audit-run risks (command execution, SSRF, unsafe XML parsing) without changing audit verdict logic.

## Guarantees (operator-stable security line)
- No shell-based command execution for ASTRA runs from SCOPE.app (reduces shell injection vectors).
- Network fetching hardening:
  - URL validation enforced before requests
  - redirects handled with strict limits
  - proxy environment variables are not trusted
- XML parsing hardened via defusedxml (reduces XXE/entity expansion risks).

## Security gate
A single deterministic gate is enforced:
- `scripts/sec_gate.sh` runs:
  - `pytest`
  - smoke test(s)
- Pre-push hook executes the gate to prevent insecure/regressed changes from being pushed.

## Reporting
If you find a security issue:
- Report privately if possible.
- Do not include client data or secrets in reports.
