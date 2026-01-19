# ai/advisory.py
from __future__ import annotations

import json
import os
import re
from datetime import datetime, timezone
from typing import Any, Optional

import requests


DISCLAIMER_EN = "AI-generated advisory. Deterministic findings remain authoritative."
DISCLAIMER_RO = "Recomandări generate de AI. Constatările deterministice rămân autoritare."


def build_ai_advisory(audit_result: dict[str, Any]) -> Optional[dict[str, Any]]:
    """
    Build AI advisory v1 using only deterministic findings and safe signals.

    Returns None when OPENAI_API_KEY is missing.
    When AI output is invalid or references unknown IDs, falls back to a deterministic advisory.
    """
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        return None
    use_ai = os.getenv("SCOPE_USE_AI", "").strip()
    if use_ai != "1":
        return None

    lang = _normalize_lang(audit_result.get("lang"))
    findings = audit_result.get("findings", []) or []
    signals = audit_result.get("signals", {}) or {}
    allowed_ids = [f.get("id", "") for f in findings if f.get("id")]

    compact_findings = _compact_findings(findings, lang)
    compact_signals = _safe_signals(signals, audit_result.get("mode", "ok"))

    prompt = _build_prompt(compact_findings, compact_signals, lang, allowed_ids)
    raw_text, err = _call_openai(api_key, prompt)

    if raw_text:
        parsed = _parse_json(raw_text)
        validated = _validate_advisory(parsed, allowed_ids)
        if validated:
            adjusted = _apply_priority_rules(validated, findings)
            return _finalize_advisory(adjusted, lang, None, "ok")

    fallback = _deterministic_fallback(findings, lang)
    return _finalize_advisory(fallback, lang, err or "invalid_ai_output", "fallback")


def _normalize_lang(lang: Any) -> str:
    lang = (lang or "en").lower().strip()
    return lang if lang in ("en", "ro") else "en"


def _safe_signals(signals: dict[str, Any], mode: str) -> dict[str, Any]:
    score = signals.get("score", 0)
    return {
        "mode": mode,
        "score": score if mode == "ok" else 0,
        "booking_detected": bool(signals.get("booking_detected")),
        "contact_detected": bool(signals.get("contact_detected")),
        "services_keywords_detected": bool(signals.get("services_keywords_detected")),
        "pricing_keywords_detected": bool(signals.get("pricing_keywords_detected")),
    }


def _compact_findings(findings: list[dict[str, Any]], lang: str) -> list[dict[str, Any]]:
    compact = []
    for f in findings or []:
        fid = f.get("id") or ""
        if not fid:
            continue
        title = f.get("title_ro") if lang == "ro" else f.get("title_en")
        rec = f.get("recommendation_ro") if lang == "ro" else f.get("recommendation_en")
        compact.append({
            "id": fid,
            "category": f.get("category"),
            "severity": f.get("severity"),
            "title": title or "",
            "recommendation": rec or "",
        })
    return compact


def _build_prompt(
    compact_findings: list[dict[str, Any]],
    compact_signals: dict[str, Any],
    lang: str,
    allowed_ids: list[str],
) -> str:
    instruction = (
        "You summarize deterministic audit findings. Do NOT invent findings, severities, or impact. "
        "Use only the provided findings and allowed finding IDs. "
        "Never reference unknown IDs. Do not include conversion impact estimates. "
        "Exclude IDs that indicate no major blockers or only social profiles present. "
        "If Open Graph core tags are missing, place that finding in fix_now. "
        "Return STRICT JSON only with this shape:\n"
        "{\n"
        '  "executive_summary": "2-4 sentences",\n'
        '  "priorities": [\n'
        '    {"level": "fix_now", "finding_ids": ["ID", "..."]},\n'
        '    {"level": "fix_soon", "finding_ids": ["ID", "..."]},\n'
        '    {"level": "monitor", "finding_ids": ["ID", "..."]}\n'
        "  ]\n"
        "}\n"
        "If there are no findings, use empty lists for each level."
    )

    payload = {
        "language": lang,
        "allowed_finding_ids": allowed_ids,
        "signals": compact_signals,
        "findings": compact_findings,
    }

    return instruction + "\n\n" + json.dumps(payload, ensure_ascii=False, indent=2)


def _call_openai(api_key: str, prompt: str) -> tuple[str, str | None]:
    model = os.getenv("OPENAI_MODEL", "").strip()
    if not model:
     return "", "missing_openai_model"
    try:
        resp = requests.post(
            "https://api.openai.com/v1/responses",
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": model,
                "input": [
                    {"role": "system", "content": [{"type": "text", "text": "Return JSON only."}]},
                    {"role": "user", "content": [{"type": "text", "text": prompt}]},
                ],
                "temperature": 0,
            },
            timeout=30,
        )
    except Exception as exc:
        return "", str(exc)

    if resp.status_code >= 400:
        return "", f"http_{resp.status_code}"

    try:
        data = resp.json()
    except Exception:
        return "", "invalid_json_response"

    if isinstance(data, dict):
        if isinstance(data.get("output_text"), str):
            return data["output_text"], None
        output = data.get("output") or []
        if isinstance(output, list):
            texts = []
            for item in output:
                if not isinstance(item, dict):
                    continue
                content = item.get("content") or []
                if isinstance(content, list):
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "output_text":
                            texts.append(c.get("text", ""))
            if texts:
                return "\n".join(texts).strip(), None

    return "", "missing_output_text"


def _parse_json(text: str) -> Optional[dict[str, Any]]:
    try:
        return json.loads(text)
    except Exception:
        pass

    match = re.search(r"\{.*\}", text, re.DOTALL)
    if not match:
        return None
    try:
        return json.loads(match.group(0))
    except Exception:
        return None


def _validate_advisory(advisory: Optional[dict[str, Any]], allowed_ids: list[str]) -> Optional[dict[str, Any]]:
    if not isinstance(advisory, dict):
        return None

    exec_summary = advisory.get("executive_summary")
    if not isinstance(exec_summary, str) or not exec_summary.strip():
        return None

    priorities = advisory.get("priorities")
    if not isinstance(priorities, list):
        return None

    allowed = set(allowed_ids)
    seen_levels = set()
    cleaned_priorities = []
    for item in priorities:
        if not isinstance(item, dict):
            return None
        level = item.get("level")
        ids = item.get("finding_ids")
        if level not in ("fix_now", "fix_soon", "monitor"):
            return None
        if not isinstance(ids, list):
            return None
        cleaned_ids = []
        for fid in ids:
            if not isinstance(fid, str) or fid not in allowed:
                return None
            cleaned_ids.append(fid)
        seen_levels.add(level)
        cleaned_priorities.append({"level": level, "finding_ids": cleaned_ids})

    if seen_levels != {"fix_now", "fix_soon", "monitor"}:
        return None

    return {
        "executive_summary": exec_summary.strip(),
        "priorities": cleaned_priorities,
    }


def _deterministic_fallback(findings: list[dict[str, Any]], lang: str) -> dict[str, Any]:
    priorities = _prioritize_findings(findings)
    fix_now = _priority_ids(priorities, "fix_now")
    fix_soon = _priority_ids(priorities, "fix_soon")
    monitor = _priority_ids(priorities, "monitor")

    if lang == "ro":
        summary = (
            "Am revizuit constatări deterministice și am prioritizat acțiunile cu impact rapid asupra încrederii și conversiei. "
            "Începeți cu elementele care afectează modul în care site-ul apare în share-uri și previzualizări sociale. "
            "Continuați cu clarificări de mesaj și consistență vizuală pentru a reduce fricțiunea în decizie. "
            "Restul poate fi monitorizat pentru a menține o prezență coerentă. "
            "Această sinteză nu modifică severitățile și nu introduce concluzii noi."
        )
    else:
        summary = (
            "We reviewed deterministic findings and prioritized actions with the fastest impact on trust and conversion. "
            "Start with issues that affect how the site appears in shares and social previews. "
            "Then improve message clarity and visual consistency to reduce decision friction. "
            "Monitor the remaining items to keep the presence stable. "
            "This summary does not change severities or introduce new conclusions."
        )

    return {
        "executive_summary": summary,
        "priorities": [
            {"level": "fix_now", "finding_ids": fix_now},
            {"level": "fix_soon", "finding_ids": fix_soon},
            {"level": "monitor", "finding_ids": monitor},
        ],
    }


def _finalize_advisory(
    core: dict[str, Any],
    lang: str,
    error: Optional[str],
    status: str,
) -> dict[str, Any]:
    advisory = {
        "version": "v1",
        "language": lang,
        "executive_summary": core.get("executive_summary", ""),
        "priorities": core.get("priorities", []),
        "disclaimer": DISCLAIMER_RO if lang == "ro" else DISCLAIMER_EN,
        "error_summary": "AI unavailable; fallback advisory generated." if status == "fallback" else None,
        "ai_status": status,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    if status == "fallback" and error:
        advisory["_debug"] = {"error": error}
    return advisory


def _prioritize_findings(findings: list[dict[str, Any]]) -> list[dict[str, Any]]:
    excluded = ("_NO_MAJOR_BLOCKERS_", "_PROFILES_PRESENT")
    share_meta_missing = "SOCIAL_OG_MISSING_CORE_TAGS"
    fix_now = []
    fix_soon = []
    monitor = []

    for f in findings or []:
        fid = f.get("id")
        if not isinstance(fid, str) or not fid:
            continue
        if any(x in fid for x in excluded):
            continue
        severity = (f.get("severity") or "").lower().strip()
        category = f.get("category")

        if fid == share_meta_missing:
            fix_now.append(fid)
            continue

        if severity == "fail":
            fix_now.append(fid)
        elif severity == "warning":
            fix_soon.append(fid)
        elif severity == "info":
            if category != "conversion_loss":
                monitor.append(fid)

    return [
        {"level": "fix_now", "finding_ids": _unique(fix_now)},
        {"level": "fix_soon", "finding_ids": _unique(fix_soon)},
        {"level": "monitor", "finding_ids": _unique(monitor)},
    ]


def _apply_priority_rules(advisory: dict[str, Any], findings: list[dict[str, Any]]) -> dict[str, Any]:
    excluded = ("_NO_MAJOR_BLOCKERS_", "_PROFILES_PRESENT")
    allowed = {f.get("id") for f in findings if f.get("id")}
    share_meta_missing = "SOCIAL_OG_MISSING_CORE_TAGS"

    by_level = {"fix_now": [], "fix_soon": [], "monitor": []}
    for group in advisory.get("priorities", []):
        level = group.get("level")
        ids = group.get("finding_ids", [])
        if level not in by_level or not isinstance(ids, list):
            continue
        for fid in ids:
            if fid not in allowed or any(x in fid for x in excluded):
                continue
            by_level[level].append(fid)

    if share_meta_missing in allowed:
        if share_meta_missing not in by_level["fix_now"]:
            by_level["fix_now"].append(share_meta_missing)
        for level in ("fix_soon", "monitor"):
            if share_meta_missing in by_level[level]:
                by_level[level] = [f for f in by_level[level] if f != share_meta_missing]

    return {
        "executive_summary": advisory.get("executive_summary", ""),
        "priorities": [
            {"level": "fix_now", "finding_ids": _unique(by_level["fix_now"])},
            {"level": "fix_soon", "finding_ids": _unique(by_level["fix_soon"])},
            {"level": "monitor", "finding_ids": _unique(by_level["monitor"])},
        ],
    }


def _priority_ids(priorities: list[dict[str, Any]], level: str) -> list[str]:
    for group in priorities:
        if group.get("level") == level:
            return group.get("finding_ids", []) or []
    return []


def _unique(items: list[str]) -> list[str]:
    seen = set()
    out = []
    for item in items:
        if item in seen:
            continue
        seen.add(item)
        out.append(item)
    return out
