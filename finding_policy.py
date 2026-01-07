from typing import Dict, Any, List
from typing import Any, Dict, List

ALLOWED_SEVERITIES = {"fail", "warning", "info"}
CONFIDENCE_LEVELS = {"high", "medium", "low"}
PROOF_COMPLETENESS = {"complete", "partial", "supporting"}


def enforce_finding_policy(finding: Dict[str, Any]) -> Dict[str, Any]:
    """
    Enforces governance rules on a single finding.
    This function is authoritative and deterministic.
    """

    # ------------------------------------------------------------------
    # ENFORCE DEFAULTS (MANDATORY, DO NOT REMOVE)
    # ------------------------------------------------------------------
    if finding.get("confidence_level") is None:
        finding["confidence_level"] = "medium"

    if finding.get("proof_completeness") is None:
        finding["proof_completeness"] = "partial"
    # ------------------------------------------------------------------

    confidence = finding["confidence_level"]
    proof = finding["proof_completeness"]
    severity = finding.get("severity")

    # Normalize severity
    if severity not in ALLOWED_SEVERITIES:
        severity = "info"
        finding["severity"] = severity

    # Ensure policy_notes exists
    finding.setdefault("policy_notes", [])
    finding.setdefault("policy_actions", [])

    # ------------------------------------------------------------------
    # FAIL GATE: FAIL allowed ONLY if high confidence + complete proof
    # ------------------------------------------------------------------
    if severity == "fail":
        if not (confidence == "high" and proof == "complete"):
            original = severity
            finding["severity"] = "warning"

            finding["policy_notes"].append(
                "Severity downgraded from 'fail' to 'warning' by policy: "
                "FAIL requires high confidence and complete proof."
            )

            finding["policy_actions"].append({
                "type": "severity_clamp",
                "from": original,
                "to": "warning",
                "reason": "confidence_proof_gate",
                "confidence_level": confidence,
                "proof_completeness": proof,
            })

    return finding


def enforce_policy_on_findings(findings: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Apply enforce_finding_policy() to every finding deterministically.
    Must never crash. Must never reference a loop variable outside the loop.
    """
    if not findings:
        return []

    out: List[Dict[str, Any]] = []
    for f in findings:
        # Defensive: ensure we always return a dict
        if not isinstance(f, dict):
            continue
        out.append(enforce_finding_policy(f))
    return out

