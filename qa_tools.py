# qa_tools.py
from __future__ import annotations

import argparse
import json
import os
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional, Tuple


SEVERITIES = {"fail", "warning", "info"}
CONFIDENCE = {"high", "medium", "low"}
PROOF = {"complete", "partial", "supporting"}


@dataclass(frozen=True)
class LintIssue:
    level: str            # "error" | "warn"
    code: str             # stable issue code
    finding_id: str       # finding id or "(audit)"
    message: str
    path: str             # JSON path-ish string


def _read_json(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def _iter_audit_json_files(root: str) -> Iterable[str]:
    if os.path.isfile(root) and root.endswith(".json"):
        yield root
        return

    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            if name == "audit.json":
                yield os.path.join(dirpath, name)


def _extract_findings(audit: Dict[str, Any]) -> List[Dict[str, Any]]:
    findings = audit.get("findings") or []
    if not isinstance(findings, list):
        return []
    return [f for f in findings if isinstance(f, dict)]


def _parse_policy_note(note: str) -> Optional[Tuple[str, str]]:
    # "Severity downgraded from 'fail' to 'warning' by policy ..."
    m = re.search(r"from '(\w+)' to '(\w+)'", note or "")
    if not m:
        return None
    return m.group(1), m.group(2)


def lint_audit(audit: Dict[str, Any], audit_path: str = "") -> List[LintIssue]:
    issues: List[LintIssue] = []
    findings = _extract_findings(audit)

    if not findings:
        # Empty states are valid, but still report if findings is missing entirely.
        if "findings" not in audit:
            issues.append(LintIssue("error", "AUDIT_MISSING_FINDINGS", "(audit)",
                                    "Audit JSON has no 'findings' field.", "findings"))
        return issues

    for i, f in enumerate(findings):
        fid = str(f.get("id") or "")
        base_path = f"findings[{i}]"

        def err(code: str, msg: str, path: str):
            issues.append(LintIssue("error", code, fid or "(missing_id)", msg, f"{base_path}.{path}"))

        def warn(code: str, msg: str, path: str):
            issues.append(LintIssue("warn", code, fid or "(missing_id)", msg, f"{base_path}.{path}"))

        # Required fields
        for k in ("id", "category", "severity"):
            if not f.get(k):
                err("FINDING_MISSING_FIELD", f"Missing required field '{k}'.", k)

        sev = str(f.get("severity") or "")
        if sev and sev not in SEVERITIES:
            err("FINDING_BAD_SEVERITY", f"Invalid severity '{sev}'.", "severity")

        cl = f.get("confidence_level")
        pc = f.get("proof_completeness")
        if cl not in CONFIDENCE:
            err("FINDING_BAD_CONFIDENCE", f"Invalid or missing confidence_level '{cl}'.", "confidence_level")
        if pc not in PROOF:
            err("FINDING_BAD_PROOF", f"Invalid or missing proof_completeness '{pc}'.", "proof_completeness")

        # Fail gate must hold (post-policy this should always be true; keep as regression guard)
        if sev == "fail":
            if cl != "high" or pc != "complete":
                err("FINDING_FAIL_GATE_BROKEN",
                    "FAIL requires confidence_level=high and proof_completeness=complete.",
                    "severity")

        # Language presence (at least one of EN/RO per field group)
        for group in (("title_en", "title_ro"), ("description_en", "description_ro"), ("recommendation_en", "recommendation_ro")):
            if not (f.get(group[0]) or f.get(group[1])):
                warn("FINDING_MISSING_LANGUAGE_VARIANT",
                     f"Missing both {group[0]} and {group[1]}.", group[0])

        # Evidence presence
        if "evidence" not in f:
            err("FINDING_MISSING_EVIDENCE", "Missing 'evidence' field.", "evidence")
            continue

        ev = f.get("evidence")
        if not isinstance(ev, dict):
            err("FINDING_BAD_EVIDENCE_TYPE", "Evidence must be an object/dict.", "evidence")
            continue

        ev_type = ev.get("type")
        if ev_type == "html_tag":
            if not ev.get("url"):
                warn("EVIDENCE_HTML_TAG_MISSING_URL", "html_tag evidence should include 'url'.", "evidence.url")
            if not (ev.get("snippet") or ev.get("attrs") or "found_count" in ev):
                warn("EVIDENCE_HTML_TAG_THIN", "html_tag evidence is thin (no snippet/attrs/found_count).", "evidence")

        if ev_type == "response_headers":
            hs = ev.get("headers_subset")
            if not isinstance(hs, dict) or not hs:
                warn("EVIDENCE_HEADERS_THIN", "response_headers evidence should include non-empty headers_subset.", "evidence.headers_subset")

        # Policy downgrade detection (string-based for now)
        notes = f.get("policy_notes") or []
        if isinstance(notes, list) and notes:
            parsed = [_parse_policy_note(n) for n in notes if isinstance(n, str)]
            parsed = [p for p in parsed if p]
            if parsed:
                frm, to = parsed[0]
                warn("FINDING_POLICY_DOWNGRADE",
                     f"Policy downgraded severity from '{frm}' to '{to}'.", "policy_notes")
            else:
                warn("FINDING_POLICY_NOTE_PRESENT",
                     "Policy notes present (could indicate downgrade).", "policy_notes")

    return issues


def explain_finding(audit: Dict[str, Any], finding_id: str) -> Dict[str, Any]:
    findings = _extract_findings(audit)
    target = None
    for f in findings:
        if str(f.get("id")) == finding_id:
            target = f
            break

    if not target:
        return {"error": f"Finding '{finding_id}' not found.", "available_ids": sorted({str(f.get('id')) for f in findings if f.get("id")})}

    return {
        "id": target.get("id"),
        "category": target.get("category"),
        "severity": target.get("severity"),
        "confidence_level": target.get("confidence_level"),
        "proof_completeness": target.get("proof_completeness"),
        "titles": {"en": target.get("title_en"), "ro": target.get("title_ro")},
        "evidence": target.get("evidence"),
        "policy_notes": target.get("policy_notes") or [],
    }


def coverage(root: str) -> Dict[str, Any]:
    by_id = Counter()
    sev = Counter()
    conf = Counter()
    proof = Counter()
    policy_downgrades = Counter()

    missing_conf = Counter()
    missing_proof = Counter()
    missing_evidence = Counter()

    legacy_missing_conf = Counter()
    legacy_missing_proof = Counter()

    total_audits = 0
    total_findings = 0

    for path in _iter_audit_json_files(root):
        audit = _read_json(path)
        total_audits += 1
        findings = _extract_findings(audit)
        total_findings += len(findings)

        for f in findings:
            fid = str(f.get("id") or "")

            if fid:
                by_id[fid] += 1

            sev[str(f.get("severity") or "")] += 1

            # Accept both new and legacy field names (deterministic)
            cl = f.get("confidence_level")
            if cl is None:
                cl = f.get("confidence")  # legacy fallback (if any)
            conf[str(cl or "")] += 1

            pc = f.get("proof_completeness")
            if pc is None:
                pc = f.get("proof")  # legacy fallback (if any)
            proof[str(pc or "")] += 1

            # Legacy detection: older audits may not have these fields at all
            if fid:
                if "confidence_level" not in f:
                    legacy_missing_conf[fid] += 1
                if "proof_completeness" not in f:
                    legacy_missing_proof[fid] += 1

            # Missing governance fields (canonical keys only)
            if f.get("confidence_level") is None:
                if fid:
                    missing_conf[fid] += 1

            if f.get("proof_completeness") is None:
                if fid:
                    missing_proof[fid] += 1

            # Evidence sanity
            if "evidence" not in f or not isinstance(f.get("evidence"), dict):
                if fid:
                    missing_evidence[fid] += 1

            # Policy downgrades (policy-native)
            actions = f.get("policy_actions") or []
            if isinstance(actions, list):
                for a in actions:
                    if not isinstance(a, dict):
                        continue
                    if a.get("type") == "severity_clamp":
                        frm = str(a.get("from") or "")
                        to = str(a.get("to") or "")
                        if fid and frm and to:
                            policy_downgrades[f"{fid}:{frm}→{to}"] += 1

    # Keep output deterministic: sort keys
    def _sorted_counter(c: Counter) -> List[Tuple[str, int]]:
        return sorted(c.items(), key=lambda x: (-x[1], x[0]))

    return {
        "root": root,
        "total_audits": total_audits,
        "total_findings": total_findings,
        "by_id_top": _sorted_counter(by_id)[:50],
        "severity_dist": _sorted_counter(sev),
        "confidence_dist": _sorted_counter(conf),
        "proof_dist": _sorted_counter(proof),
        "policy_downgrades_top": _sorted_counter(policy_downgrades)[:50],
        "missing_confidence_top": _sorted_counter(missing_conf)[:50],
        "missing_proof_top": _sorted_counter(missing_proof)[:50],
        "missing_evidence_top": _sorted_counter(missing_evidence)[:50],
        "legacy_missing_confidence_top": _sorted_counter(legacy_missing_conf)[:50],
        "legacy_missing_proof_top": _sorted_counter(legacy_missing_proof)[:50],
    }



def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_lint = sub.add_parser("lint", help="Lint a single audit.json or a folder containing audit.json files")
    p_lint.add_argument("path")
    p_lint.add_argument("--json", action="store_true", help="Emit JSON output")
    p_lint.add_argument("--warn-as-error", action="store_true", help="Treat warnings as errors")

    p_explain = sub.add_parser("explain", help="Explain one finding from an audit.json")
    p_explain.add_argument("audit_json")
    p_explain.add_argument("--id", required=True)

    p_cov = sub.add_parser("coverage", help="Aggregate coverage stats for a folder containing audit.json files")
    p_cov.add_argument("root")

    args = ap.parse_args()

    if args.cmd == "lint":
        paths = list(_iter_audit_json_files(args.path))
        if not paths:
            print(f"No audit.json found under: {args.path}")
            raise SystemExit(1)

        all_issues: List[LintIssue] = []
        for p in paths:
            audit = _read_json(p)
            all_issues.extend(lint_audit(audit, audit_path=p))

        # Deterministic ordering
        all_issues.sort(key=lambda x: (x.level, x.code, x.finding_id, x.path, x.message))

        if args.json:
            payload = {
                "path": args.path,
                "issue_count": len(all_issues),
                "issues": [x.__dict__ for x in all_issues],
            }
            print(json.dumps(payload, ensure_ascii=False, indent=2))
        else:
            for x in all_issues:
                print(f"[{x.level.upper()}] {x.code} {x.finding_id} @ {x.path} :: {x.message}")

            print(f"\nIssues: {len(all_issues)}")

        has_error = any(i.level == "error" for i in all_issues)
        has_warn = any(i.level == "warn" for i in all_issues)
        if has_error or (args.warn_as_error and has_warn):
            raise SystemExit(2)
        raise SystemExit(0)

    if args.cmd == "explain":
        audit = _read_json(args.audit_json)
        payload = explain_finding(audit, args.id)
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        raise SystemExit(0)

    if args.cmd == "coverage":
        payload = coverage(args.root)
        print(json.dumps(payload, ensure_ascii=False, indent=2))
        raise SystemExit(0)


if __name__ == "__main__":
    main()
