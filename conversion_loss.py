"""conversion_loss.py

Deterministic, conservative conversion-loss estimation.

Principles:
- Never claim precise numbers.
- Use ranges and clearly state assumptions.
- Only estimate for issues with a direct, defensible conversion mechanism.
- If business inputs (sessions, conversion rate, value) are missing, return % ranges only.

This module does NOT use AI.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional


@dataclass(frozen=True)
class BusinessInputs:
    """Optional business inputs used to translate % impact into absolute numbers."""

    sessions_per_month: Optional[float] = None
    conversion_rate: Optional[float] = None  # 0.02 for 2%
    value_per_conversion: Optional[float] = None


@dataclass(frozen=True)
class LossEstimate:
    issue_id: str
    impact_pct_low: float
    impact_pct_high: float
    confidence: str  # High / Medium / Low
    rationale_en: str
    rationale_ro: str
    assumptions_en: List[str]
    assumptions_ro: List[str]
    evidence: Dict[str, Any]
    baseline_conversions_per_month: Optional[float] = None
    lost_conversions_low: Optional[float] = None
    lost_conversions_high: Optional[float] = None
    lost_value_low: Optional[float] = None
    lost_value_high: Optional[float] = None


def _compute_absolutes(est: LossEstimate, inputs: BusinessInputs) -> LossEstimate:
    sessions = inputs.sessions_per_month
    cr = inputs.conversion_rate
    vpc = inputs.value_per_conversion

    if sessions is None or cr is None:
        return est

    baseline_conv = sessions * cr
    lost_low = baseline_conv * est.impact_pct_low
    lost_high = baseline_conv * est.impact_pct_high

    lost_value_low = (lost_low * vpc) if (vpc is not None) else None
    lost_value_high = (lost_high * vpc) if (vpc is not None) else None

    return LossEstimate(
        issue_id=est.issue_id,
        impact_pct_low=est.impact_pct_low,
        impact_pct_high=est.impact_pct_high,
        confidence=est.confidence,
        rationale_en=est.rationale_en,
        rationale_ro=est.rationale_ro,
        assumptions_en=est.assumptions_en,
        assumptions_ro=est.assumptions_ro,
        evidence=est.evidence,
        baseline_conversions_per_month=baseline_conv,
        lost_conversions_low=lost_low,
        lost_conversions_high=lost_high,
        lost_value_low=lost_value_low,
        lost_value_high=lost_value_high,
    )


def estimate_conversion_loss(
    mode: str,
    signals: Dict[str, Any],
    inputs: Optional[BusinessInputs] = None,
) -> List[Dict[str, Any]]:
    """Return a list of LossEstimate dicts (JSON-serializable)."""
    mode = (mode or "").lower().strip()
    inputs = inputs or BusinessInputs()

    estimates: List[LossEstimate] = []

    # 1) Website unreachable / broken
    if mode in ("broken", "no_website"):
        estimates.append(
            LossEstimate(
                issue_id="CONVLOSS_SITE_UNREACHABLE",
                impact_pct_low=0.70,
                impact_pct_high=0.95,
                confidence="High",
                rationale_en="If the website cannot be accessed reliably, most visitors will abandon immediately.",
                rationale_ro="Dacă website-ul nu poate fi accesat în mod fiabil, majoritatea vizitatorilor vor abandona imediat.",
                assumptions_en=[
                    "Visitors reaching an error page typically do not convert.",
                    "The website link is used as a decision checkpoint (Google/Maps/social).",
                ],
                assumptions_ro=[
                    "Vizitatorii care ajung la o eroare, de regulă, nu convertesc.",
                    "Linkul către website este folosit ca punct de decizie (Google/Maps/social).",
                ],
                evidence={"mode": mode, "reason": (signals or {}).get("reason", "")},
            )
        )

    if mode != "ok":
        return [_compute_absolutes(e, inputs).__dict__ for e in estimates]

    # 2) Booking/appointment CTA not detectable
    if not bool((signals or {}).get("booking_detected")):
        estimates.append(
            LossEstimate(
                issue_id="CONVLOSS_BOOKING_NOT_CLEAR",
                impact_pct_low=0.08,
                impact_pct_high=0.20,
                confidence="Medium",
                rationale_en="If booking is not clearly visible, fewer visitors will take the next step.",
                rationale_ro="Dacă programarea nu este vizibilă clar, mai puțini vizitatori vor face pasul următor.",
                assumptions_en=[
                    "Homepage is a primary landing page for first-time visitors.",
                    "The business relies on appointment/booking inquiries.",
                ],
                assumptions_ro=[
                    "Homepage-ul este o pagină principală de intrare pentru vizitatori noi.",
                    "Business-ul se bazează pe cereri de programare/booking.",
                ],
                evidence={"booking_detected": False},
            )
        )

    # 3) Contact details not detectable
    if not bool((signals or {}).get("contact_detected")):
        estimates.append(
            LossEstimate(
                issue_id="CONVLOSS_CONTACT_NOT_CLEAR",
                impact_pct_low=0.05,
                impact_pct_high=0.15,
                confidence="Medium",
                rationale_en="If contact details are hard to find, interested visitors may drop before reaching out.",
                rationale_ro="Dacă datele de contact sunt greu de găsit, vizitatorii interesați pot renunța înainte să vă contacteze.",
                assumptions_en=[
                    "Some visitors prefer calling/messaging instead of booking forms.",
                    "Contact is expected in header/footer or a clear CTA.",
                ],
                assumptions_ro=[
                    "Unii vizitatori preferă să sune/să scrie în locul formularelor.",
                    "Contactul este așteptat în header/footer sau printr-un CTA clar.",
                ],
                evidence={"contact_detected": False},
            )
        )

    # 4) Pricing guidance not detectable (low confidence, small impact)
    if not bool((signals or {}).get("pricing_keywords_detected")):
        estimates.append(
            LossEstimate(
                issue_id="CONVLOSS_PRICING_NOT_CLEAR",
                impact_pct_low=0.01,
                impact_pct_high=0.05,
                confidence="Low",
                rationale_en="If pricing guidance is missing, some visitors hesitate and delay contacting or booking.",
                rationale_ro="Dacă lipsesc informațiile de preț (măcar orientativ), o parte dintre vizitatori ezită și amână contactul sau programarea.",
                assumptions_en=[
                    "Visitors compare options and look for pricing cues before committing.",
                    "Even partial pricing ranges can reduce uncertainty.",
                ],
                assumptions_ro=[
                    "Vizitatorii compară opțiuni și caută indicii de preț înainte să decidă.",
                    "Chiar și intervale orientative pot reduce incertitudinea.",
                ],
                evidence={"pricing_keywords_detected": False},
            )
        )

    # 5) Services/offer not clearly described (low confidence, small impact)
    if not bool((signals or {}).get("services_keywords_detected")):
        estimates.append(
            LossEstimate(
                issue_id="CONVLOSS_SERVICES_NOT_CLEAR",
                impact_pct_low=0.01,
                impact_pct_high=0.04,
                confidence="Low",
                rationale_en="If services are not clear on the homepage, fewer visitors understand the offer and take action.",
                rationale_ro="Dacă serviciile nu sunt clare pe homepage, mai puțini vizitatori înțeleg oferta și fac pasul următor.",
                assumptions_en=[
                    "Homepage is the first impression for many visitors.",
                    "Clear service descriptions reduce decision friction.",
                ],
                assumptions_ro=[
                    "Homepage-ul este prima impresie pentru mulți vizitatori.",
                    "Descrieri clare reduc fricțiunea deciziei.",
                ],
                evidence={"services_keywords_detected": False},
            )
        )

    # If none of the v1 conversion-loss triggers fired, record that explicitly.
    if not estimates:
        estimates.append(
            LossEstimate(
                issue_id="CONVLOSS_NO_MAJOR_BLOCKERS_V1",
                impact_pct_low=0.0,
                impact_pct_high=0.0,
                confidence="High",
                rationale_en="Within this v1 estimator (booking/contact/offer/pricing/availability), no major conversion blockers were detected.",
                rationale_ro="În cadrul acestui estimator v1 (programare/contact/ofertă/preț/disponibilitate), nu au fost detectate blocaje majore de conversie.",
                assumptions_en=[
                    "This is not a guarantee of perfect conversion performance.",
                    "Other factors (speed, UX, trust, targeting) may still impact results.",
                ],
                assumptions_ro=[
                    "Aceasta nu este o garanție că performanța conversiilor este perfectă.",
                    "Alți factori (viteză, UX, încredere, targeting) pot influența rezultatele.",
                ],
                evidence={},
            )
        )

    return [_compute_absolutes(e, inputs).__dict__ for e in estimates]
