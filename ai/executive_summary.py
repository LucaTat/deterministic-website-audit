# ai/executive_summary.py
from __future__ import annotations

import json
import os
import re
from datetime import datetime, timezone
from typing import Any, Optional

import requests


def build_ai_advisory(
    findings: list[dict[str, Any]],
    signals: dict[str, Any],
    lang: str,
    mode: str,
) -> Optional[dict[str, Any]]:
    """
    Create an AI advisory summary from deterministic findings.

    - Never changes findings or scores.
    - Uses only compact signals + findings.
    - Returns None if AI is not available or fails.
    """
    api_key = os.getenv("OPENAI_API_KEY")
    if not api_key:
        return None
    use_ai = os.getenv("SCOPE_USE_AI", "").strip()
    if use_ai != "1":
        return None

    model = os.getenv("OPENAI_MODEL", "").strip()
    if not model:
     return None
    lang = (lang or "en").lower().strip()
    if lang not in ("en", "ro"):
        lang = "en"

    compact_findings = _compact_findings(findings, lang)
    allowed_ids = [f.get("id", "") for f in compact_findings if f.get("id")]

    prompt = _build_prompt(compact_findings, signals, mode, lang, allowed_ids)
    raw_text = _call_openai(api_key, model, prompt)
    if not raw_text:
        return None

    advisory = _parse_json(raw_text)
    if not advisory:
        return None

    validated = _validate_advisory(advisory, allowed_ids)
    if not validated:
        return None

    validated["model"] = model
    validated["generated_at"] = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return validated


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
    signals: dict[str, Any],
    mode: str,
    lang: str,
    allowed_ids: list[str],
) -> str:
    score = signals.get("score", 0)
    compact_signals = {
        "mode": mode,
        "score": score if mode == "ok" else 0,
        "booking_detected": bool(signals.get("booking_detected")),
        "contact_detected": bool(signals.get("contact_detected")),
        "services_keywords_detected": bool(signals.get("services_keywords_detected")),
        "pricing_keywords_detected": bool(signals.get("pricing_keywords_detected")),
    }

    instruction = (
        "You are an assistant that summarizes deterministic audit findings. "
        "Do NOT create new findings, severities, or scores. "
        "Use only the provided findings and the allowed finding IDs. "
        "Never reference any other IDs. "
        "Return STRICT JSON only with this shape:\n"
        "{\n"
        '  "summary": "2-4 sentences",\n'
        '  "top_findings": [\n'
        '    {"finding_id": "ID", "why_it_matters": "...", "suggested_focus": "..."}\n'
        "  ]\n"
        "}\n"
        "Top findings should be 1-3 items. If there are no findings, return an empty list."
    )

    payload = {
        "language": lang,
        "allowed_finding_ids": allowed_ids,
        "signals": compact_signals,
        "findings": compact_findings,
    }

    return instruction + "\n\n" + json.dumps(payload, ensure_ascii=False, indent=2)


def _call_openai(api_key: str, model: str, prompt: str) -> str:
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
    except Exception:
        return ""

    if resp.status_code >= 400:
        return ""

    data = resp.json()
    if isinstance(data, dict):
        if isinstance(data.get("output_text"), str):
            return data["output_text"]
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
                return "\n".join(texts).strip()
    return ""


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


def _validate_advisory(advisory: dict[str, Any], allowed_ids: list[str]) -> Optional[dict[str, Any]]:
    if not isinstance(advisory, dict):
        return None

    summary = advisory.get("summary")
    if not isinstance(summary, str):
        summary = ""

    top = advisory.get("top_findings")
    if not isinstance(top, list):
        top = []

    allowed = set(allowed_ids)
    cleaned = []
    for item in top:
        if not isinstance(item, dict):
            continue
        fid = item.get("finding_id")
        if fid not in allowed:
            continue
        cleaned.append({
            "finding_id": fid,
            "why_it_matters": str(item.get("why_it_matters") or "").strip(),
            "suggested_focus": str(item.get("suggested_focus") or "").strip(),
        })

    return {
        "summary": summary.strip(),
        "top_findings": cleaned[:3],
    }
