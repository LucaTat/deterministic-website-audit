# proof_completeness_shadow.py
from __future__ import annotations

import json
import os
from typing import Any, Dict, List, Optional


SPEC_PATH = os.path.join(
    os.path.dirname(__file__),
    "specs",
    "proof",
    "proof_completeness_spec.v1.json",
)

PROOF_VALUES = {"complete", "partial", "supporting"}


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
            str(x.get("profile_id") or ""),
            str(x.get("proof_completeness") or ""),
            str(x.get("spec_proof_completeness") or ""),
            int(x.get("finding_index") or 0),
        ),
    )

def _resolve_profile_id(finding: Dict[str, Any], spec: Dict[str, Any]) -> Optional[str]:
    bindings = spec.get("bindings") or {}
    if not isinstance(bindings, dict):
        bindings = {}
    default_profile = spec.get("default_profile")
    fid = finding.get("id")
    return bindings.get(fid, default_profile)


def _lookup_profile(profile_id: Optional[str], spec: Dict[str, Any]) -> Dict[str, Any]:
    profiles = spec.get("profiles") or {}
    if not isinstance(profiles, dict):
        return {}
    if profile_id and profile_id in profiles and isinstance(profiles[profile_id], dict):
        return profiles[profile_id]
    return {}


def _passthrough_proof(finding: Dict[str, Any]) -> str:
    proof = finding.get("proof_completeness")
    if proof not in PROOF_VALUES:
        return "partial"
    return proof


def _evaluate_profile(finding: Dict[str, Any], profile: Dict[str, Any]) -> str:
    mode = profile.get("mode")
    if mode == "static":
        value = profile.get("value")
        if value not in PROOF_VALUES:
            return "partial"
        return value
    if mode == "passthrough":
        return _passthrough_proof(finding)
    return _passthrough_proof(finding)


def build_proof_completeness_shadow_report(
    findings: List[Dict[str, Any]] | None,
    spec: Dict[str, Any],
) -> Dict[str, Any]:
    items: List[Dict[str, Any]] = []

    for idx, finding in enumerate(_normalize_findings(findings)):
        proof = finding.get("proof_completeness")
        profile_id = _resolve_profile_id(finding, spec)
        if finding.get("id") == "IDX_SITEMAP_MISSING":
            profile_id = "idx_sitemap_missing_rule_v1"
        profile = _lookup_profile(profile_id, spec)
        spec_proof = _evaluate_profile(finding, profile)
        rule_candidate = None
        if finding.get("id") == "IDX_SITEMAP_MISSING":
            rule_candidate = _evaluate_profile(finding, _lookup_profile("idx_sitemap_missing_rule_v1", spec))
        mismatch = spec_proof != proof
        
        items.append(
            {
                "spec_rule_candidate": rule_candidate,
                "finding_index": idx,
                "id": finding.get("id"),
                "profile_id": profile_id,
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
