from typing import Dict, Any, List


def enrich_findings(findings: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Centralized, deterministic finding enricher.
    No AI. No speculation. No crawling.
    """
    enriched = []

    for f in findings:
        f = dict(f)  # defensive copy

        # --------------------------------------------------
        # Preserve original intent (internal only)
        # --------------------------------------------------
        f.setdefault("severity_intent", f.get("severity"))

        # --------------------------------------------------
        # Centralized defaults (mirror policy, explicit)
        # --------------------------------------------------
        if f.get("confidence_level") is None:
            f["confidence_level"] = "medium"

        if f.get("proof_completeness") is None:
            f["proof_completeness"] = "partial"

        # --------------------------------------------------
        # Placeholder for future spec-driven logic
        # --------------------------------------------------
        # f["proof_gaps"] = []
        # f["evidence_refs"] = []

        enriched.append(f)

    return enriched
