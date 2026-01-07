# proof_completeness_shadow.py
from __future__ import annotations

import json
import os
from typing import Any, Dict, List


SPEC_PATH = os.path.join(
    os.path.dirname(__file__),
    "specs",
    "proof",
    "proof_completeness_spec.v1.json",
)


def load_proof_completeness_spec(path: str = SPEC_PATH) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _normalize_findings(findings: List[Dict[str, Any]] | None) -> List[Dict[str, Any]]:
    if not findings:
        return []
    return [f for f in findings if isinstance(f, dict)]


def _sorted_items(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    return sorted(
        items,
        key=lambda x: (
            str(x.get("id") or ""),
            str(x.get("proof_completeness") or ""),
            str(x.get("spec_proof_completeness") or ""),
            int(x.get("finding_index") or 0),
        ),
    )


def build_proof_completeness_shadow_report(
    findings: List[Dict[str, Any]] | None,
    spec: Dict[str, Any],
) -> Dict[str, Any]:
    items: List[Dict[str, Any]] = []

    for idx, finding in enumerate(_normalize_findings(findings)):
        proof = finding.get("proof_completeness")
        spec_proof = proof  # passthrough default
        mismatch = spec_proof != proof

        items.append(
            {
                "finding_index": idx,
                "id": finding.get("id"),
                "proof_completeness": proof,
                "spec_proof_completeness": spec_proof,
                "mismatch": mismatch,
            }
        )

    items = _sorted_items(items)
    mismatch_count = sum(1 for item in items if item.get("mismatch"))

    return {
        "spec_version": spec.get("version"),
        "spec_mode": spec.get("mode"),
        "default_behavior": spec.get("default_behavior"),
        "mismatch_count": mismatch_count,
        "items": items,
    }


def write_proof_completeness_shadow(
    findings: List[Dict[str, Any]] | None,
    out_path: str,
    spec_path: str = SPEC_PATH,
) -> Dict[str, Any]:
    spec = load_proof_completeness_spec(spec_path)
    report = build_proof_completeness_shadow_report(findings, spec)

    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2, sort_keys=True)

    return report
