"""conversion_loss_findings.py

Creates agency-grade Findings from deterministic conversion-loss estimates.
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from conversion_loss import BusinessInputs, estimate_conversion_loss


def _fmt_pct(x: float) -> str:
    # x=0.05 -> "5%"
    try:
        return f"{round(x * 100)}%"
    except Exception:
        return ""


def _fmt_range_pct(lo: float, hi: float) -> str:
    return f"{_fmt_pct(lo)}–{_fmt_pct(hi)}"


def _fmt_num(x: Optional[float]) -> str:
    if x is None:
        return ""
    # keep it conservative: round to 1 decimal for conversions, 0 for money
    return f"{x:.1f}"


def _fmt_money(x: Optional[float]) -> str:
    if x is None:
        return ""
    return f"{x:.0f}"


def build_conversion_loss(
    mode: str,
    signals: Dict[str, Any],
    business_inputs: Optional[Dict[str, Any]] = None,
) -> List[Dict[str, Any]]:
    """Returns the raw conversion-loss estimates to store in audit.json."""
    bi = business_inputs or {}
    inputs = BusinessInputs(
        sessions_per_month=_to_float(bi.get("sessions_per_month")),
        conversion_rate=_to_float(bi.get("conversion_rate")),
        value_per_conversion=_to_float(bi.get("value_per_conversion")),
    )
    return estimate_conversion_loss(mode=mode, signals=signals or {}, inputs=inputs)


def _to_float(x: Any) -> Optional[float]:
    try:
        if x is None:
            return None
        if isinstance(x, (int, float)):
            return float(x)
        s = str(x).strip().replace(",", ".")
        if not s:
            return None
        return float(s)
    except Exception:
        return None


def build_conversion_loss_findings(
    mode: str,
    signals: Dict[str, Any],
    business_inputs: Optional[Dict[str, Any]] = None,
    lang: str = "en",
) -> List[Dict[str, Any]]:
    """Build Findings objects (EN/RO) from conversion loss estimates."""
    estimates = build_conversion_loss(mode=mode, signals=signals, business_inputs=business_inputs)

    findings: List[Dict[str, Any]] = []
    for e in estimates:
        issue_id = e.get("issue_id", "")
        lo = float(e.get("impact_pct_low", 0) or 0)
        hi = float(e.get("impact_pct_high", 0) or 0)
        pct_range = _fmt_range_pct(lo, hi)

        conf = (e.get("confidence") or "").lower().strip()
        # Map confidence text to severity conservatively
        if issue_id == "CONVLOSS_SITE_UNREACHABLE":
            severity = "fail"
        elif issue_id == "CONVLOSS_NO_MAJOR_BLOCKERS_V1":
            severity = "info"
        else:
            severity = "warning" if conf in ("high", "medium") else "info"

        # Optional absolutes
        lost_conv_lo = e.get("lost_conversions_low")
        lost_conv_hi = e.get("lost_conversions_high")
        lost_val_lo = e.get("lost_value_low")
        lost_val_hi = e.get("lost_value_high")

        abs_conv = ""
        abs_val = ""
        if lost_conv_lo is not None and lost_conv_hi is not None:
            abs_conv = f" (~{_fmt_num(float(lost_conv_lo))}–{_fmt_num(float(lost_conv_hi))} conversions/month)"
        if lost_val_lo is not None and lost_val_hi is not None:
            abs_val = f" (~{_fmt_money(float(lost_val_lo))}–{_fmt_money(float(lost_val_hi))} value/month)"

        title_en = "Estimated conversion loss (conservative)"
        title_ro = "Estimare pierdere conversii (conservator)"

        if issue_id == "CONVLOSS_SITE_UNREACHABLE":
            title_en = "Website appears unreachable: high conversion loss risk"
            title_ro = "Website aparent inaccesibil: risc mare de pierdere conversii"
        elif issue_id == "CONVLOSS_BOOKING_NOT_CLEAR":
            title_en = "Booking is not clear: conversion loss risk"
            title_ro = "Programarea nu este clară: risc de pierdere conversii"
        elif issue_id == "CONVLOSS_CONTACT_NOT_CLEAR":
            title_en = "Contact is not clear: conversion loss risk"
            title_ro = "Contactul nu este clar: risc de pierdere conversii"
        elif issue_id == "CONVLOSS_PRICING_NOT_CLEAR":
            title_en = "Pricing guidance is missing: small conversion loss risk"
            title_ro = "Lipsesc indicii de preț: risc mic de pierdere conversii"
        elif issue_id == "CONVLOSS_SERVICES_NOT_CLEAR":
            title_en = "Services are not clear: small conversion loss risk"
            title_ro = "Serviciile nu sunt clare: risc mic de pierdere conversii"
        elif issue_id == "CONVLOSS_NO_MAJOR_BLOCKERS_V1":
            title_en = "No major conversion blockers detected (v1 estimator)"
            title_ro = "Nu s-au detectat blocaje majore (estimator v1)"

        desc_en = (
            f"Estimated potential conversion impact: {pct_range}{abs_conv}{abs_val}. "

            f"Rationale: {e.get('rationale_en','')}"
        ).strip()

        desc_ro = (
            f"Impact potențial estimat asupra conversiilor: {pct_range}{abs_conv}{abs_val}. "

            f"Motivare: {e.get('rationale_ro','')}"
        ).strip()

        rec_en = "Address the underlying issue first, then retest and compare results over time."
        rec_ro = "Rezolvați mai întâi cauza, apoi retestați și comparați rezultatele în timp."

        use_ro = lang.strip().lower() == "ro"
        title_en_out = title_ro if use_ro else title_en
        desc_en_out = desc_ro if use_ro else desc_en
        rec_en_out = rec_ro if use_ro else rec_en

        findings.append(
            {
                "id": issue_id,
                "category": "conversion_loss",
                "severity": severity,
                "title_en": title_en_out,
                "title_ro": title_ro,
                "description_en": desc_en_out,
                "description_ro": desc_ro,
                "recommendation_en": rec_en_out,
                "recommendation_ro": rec_ro,
                "evidence": {
                    "impact_pct_low": lo,
                    "impact_pct_high": hi,
                    "confidence": e.get("confidence"),
                    "assumptions_en": e.get("assumptions_en", []),
                    "assumptions_ro": e.get("assumptions_ro", []),
                    "baseline_conversions_per_month": e.get("baseline_conversions_per_month"),
                    "lost_conversions_low": e.get("lost_conversions_low"),
                    "lost_conversions_high": e.get("lost_conversions_high"),
                    "lost_value_low": e.get("lost_value_low"),
                    "lost_value_high": e.get("lost_value_high"),
                },
            }
        )

    return findings
