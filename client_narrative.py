# client_narrative.py

def build_client_narrative(signals: dict, lang: str = "en") -> dict:
    """
    Client-facing narrative in EN or RO.
    Deterministic based on signals.
    """
    lang = (lang or "en").lower().strip()
    if lang not in ("en", "ro"):
        lang = "en"

    booking = bool(signals.get("booking_detected"))
    contact = bool(signals.get("contact_detected"))
    services = bool(signals.get("services_keywords_detected"))
    pricing = bool(signals.get("pricing_keywords_detected"))
    score = int(signals.get("score", 0) or 0)

    # Shared flags (used mainly in EN, but safe here)
    essentials_ok = booking and contact and score >= 85
    fully_covered = booking and contact and services and pricing and score >= 90

    # -------------------------
    # RO
    # -------------------------
    if lang == "ro":
               # Overview (must match signals)
        if fully_covered:
            overview = [
                "Acest website are elementele esențiale pe care vizitatorii le caută atunci când decid să contacteze sau să se programeze.",
                "Oportunitatea principală nu este completarea informațiilor lipsă, ci creșterea clarității și a accentului pe acțiune pentru conversii mai bune."
            ]
        elif essentials_ok:
            overview = [
                "Acest website include bazele necesare pentru ca vizitatorii să poată acționa.",
                "Oportunitatea principală este să faceți programarea/contactul mai evident și să reduceți ezitarea (mai ales pe mobil)."
            ]
        else:
            overview = [
                "Acest website creează interes, dar nu ghidează clar vizitatorii către contact sau programare.",
                "Rezultatul: potențiali clienți pot pleca fără să acționeze, chiar dacă sunt interesați."
            ]


        # Primary issue
                # Primary issue (must match signals)
        if fully_covered:
            primary_issue = {
                "title": "Nu am detectat probleme majore în verificările de bază pentru conversie",
                "impact": (
                    "Elementele esențiale sunt prezente (programare/contact/servicii/prețuri). "
                    "Oportunitatea principală este optimizarea clarității și a accentului pe CTA pentru a crește conversia, "
                    "nu repararea unor lipsuri evidente."
                ),
            }
        elif not booking:
            primary_issue = {
                "title": "Nu există un pas următor clar pentru vizitatori",
                "impact": (
                    "Vizitatorii nu sunt îndrumați clar ce să facă după ce devin interesați. "
                    "Lipsește un CTA dominant care să iasă în evidență. "
                    "Asta reduce direct cererile și programările, mai ales pe mobil."
                ),
            }
        elif not contact:
            primary_issue = {
                "title": "Datele de contact nu sunt vizibile imediat",
                "impact": (
                    "Vizitatorii care vor să vă contacteze rapid trebuie să caute. "
                    "Asta creează fricțiune și crește șansa să abandoneze pagina."
                ),
            }
        elif not services:
            primary_issue = {
                "title": "Serviciile nu sunt suficient de clare pentru un vizitator nou",
                "impact": (
                    "Vizitatorii nu înțeleg rapid ce oferiți și pentru cine este, "
                    "așa că ezită în loc să se programeze."
                ),
            }
        elif not pricing:
            primary_issue = {
                "title": "Lipsa prețurilor orientative crește ezitarea",
                "impact": (
                    "Fără un context de preț, vizitatorii nu știu la ce să se aștepte și sunt mai puțin tentați să se programeze."
                ),
            }
        else:
            primary_issue = {
                "title": "Website-ul nu ghidează suficient vizitatorii către acțiune",
                "impact": (
                    "Informațiile există, dar programarea/contactul nu sunt evidențiate acolo unde se ia decizia."
                ),
            }


        # Secondary issues
        secondary_issues = []
        if not services:
            secondary_issues.append(
                "Serviciile sunt menționate, dar nu sunt explicate clar ca rezultate pentru client."
            )
        if not pricing:
            secondary_issues.append(
                "Lipsesc prețuri orientative, ceea ce crește ezitarea și incertitudinea."
            )
        if not contact:
            secondary_issues.append(
                "Informațiile de contact există, dar nu sunt evidențiate în zonele de decizie."
            )
        secondary_issues = secondary_issues[:3]

                # Plan
        if fully_covered:
            plan = [
                "Întăriți CTA-ul principal: să fie dominant vizual și repetat în header/meniu.",
                "Reduceți fricțiunea pe mobil: secțiuni mai scurte, text mai ușor de scanat și CTA mereu la îndemână.",
                "Adăugați elemente de încredere lângă CTA (review-uri, rezultate, locație/program, garanții).",
            ]
        else:
            plan = []
            if not booking:
                plan.append("Adăugați un CTA principal sus în pagină (Programează-te / Cere ofertă).")
            if not contact:
                plan.append("Faceți contactul imediat vizibil (telefon, adresă, program) și link clar către pagina Contact.")
            if not services:
                plan.append("Clarificați serviciile în limbaj simplu: pentru cine sunt și ce rezultat obține clientul.")
            if not pricing:
                plan.append("Adăugați intervale de preț sau „de la…” pentru a reduce ezitarea și a crește încrederea.")
            plan = plan[:3]

        # Confidence
        if score < 70:
            confidence = "Ridicată"
        elif score < 85:
            confidence = "Medie"
        else:
            confidence = "Scăzută"

        # Scope note (RO)
        scope_note = (
            "Această evaluare se bazează pe textul și link-urile vizibile pe homepage "
            "la momentul auditului."
        )

        return {
            "overview": overview,
            "primary_issue": primary_issue,
            "secondary_issues": secondary_issues,
            "plan": plan,
            "confidence": confidence,
            "scope_note": scope_note,
        }

    # -------------------------
    # EN (default)
    # -------------------------

    # Overview (must match signals)
    if fully_covered:
        overview = [
            "This website covers the essential elements visitors expect when deciding to contact or book a service.",
            "The main opportunity is not fixing missing information, but improving clarity and emphasis to maximize conversions."
        ]
    elif essentials_ok:
        overview = [
            "This website includes the key basics visitors need to take action.",
            "The main opportunity is to make the booking/contact path more obvious and reduce hesitation (especially on mobile)."
        ]
    else:
        overview = [
            "This website creates interest, but it does not clearly guide visitors toward contacting you or booking a service.",
            "As a result, potential customers may leave without taking action, even if they are interested."
        ]

    # Primary issue (must match signals)
    if fully_covered:
        primary_issue = {
            "title": "No major issues detected in the basic conversion checks",
            "impact": (
                "The essentials are present (booking/contact/services/pricing). "
                "The main opportunity is improving clarity and emphasis to increase conversion, "
                "not fixing missing information."
            ),
        }
    elif not booking:
        primary_issue = {
            "title": "No clear next step for visitors",
            "impact": (
                "Visitors are not clearly told what to do once they decide they are interested. "
                "There is no dominant call-to-action that stands out. "
                "This directly reduces inquiries and bookings, especially from mobile visitors."
            ),
        }
    elif not contact:
        primary_issue = {
            "title": "Contact details are not immediately visible",
            "impact": (
                "Visitors who want to reach you quickly cannot do so without searching. "
                "This creates friction and causes potential customers to abandon the page."
            ),
        }
    elif not services:
        primary_issue = {
            "title": "Services are not clear for first-time visitors",
            "impact": (
                "Visitors cannot quickly tell what you offer and who it is for, so they hesitate instead of booking."
            ),
        }
    elif not pricing:
        primary_issue = {
            "title": "No pricing guidance increases hesitation",
            "impact": (
                "Without any price context, visitors are unsure what to expect and are less likely to book."
            ),
        }
    else:
        primary_issue = {
            "title": "The website does not guide visitors toward action",
            "impact": (
                "Information exists, but the path to booking/contact is not emphasized where decisions are made."
            ),
        }

    # Secondary issues
    secondary_issues = []
    if not services:
        secondary_issues.append(
            "Services are mentioned, but not clearly explained in terms of outcomes for the customer."
        )
    if not pricing:
        secondary_issues.append(
            "No pricing guidance is provided, which increases hesitation and uncertainty."
        )
    if not contact:
        secondary_issues.append(
            "Contact information exists, but it is not emphasized where decisions are made."
        )
    secondary_issues = secondary_issues[:3]

    # Recommended plan
    if fully_covered:
        plan = [
            "Strengthen the primary call-to-action: make it visually dominant and repeat it in the header.",
            "Reduce friction on mobile: shorten sections, increase scannability, and keep booking/contact always reachable.",
            "Add trust reinforcement near the CTA (reviews, results, guarantees, location/hours).",
        ]
    else:
        plan = []
        if not booking:
            plan.append("Add a single, clear primary call-to-action above the fold (Book / Request a quote).")
        if not contact:
            plan.append("Make contact details immediately visible (phone, address, hours) and add a clear Contact link.")
        if not services:
            plan.append("Clarify services in simple customer language: who it’s for and what result they get.")
        if not pricing:
            plan.append("Add pricing ranges or starting prices to reduce hesitation and build trust.")
        plan = plan[:3]

    # Confidence
    if score < 70:
        confidence = "High"
    elif score < 85:
        confidence = "Medium"
    else:
        confidence = "Low"

    # Scope note (EN)
    scope_note = (
        "This assessment is based on the visible homepage text and links "
        "available at the time of the audit."
    )

    return {
        "overview": overview,
        "primary_issue": primary_issue,
        "secondary_issues": secondary_issues,
        "plan": plan,
        "confidence": confidence,
        "scope_note": scope_note,
    }


def build_positive_validation_narrative(lang: str, confidence: str) -> dict:
    """
    Deterministic positive validation narrative for structurally sound sites.
    """
    lang = (lang or "en").lower().strip()
    if lang not in ("en", "ro"):
        lang = "en"

    if lang == "ro":
        overview = [
            "Structura de bază este solidă: informațiile esențiale sunt prezente și accesibile.",
            "Prioritatea nu este repararea unor lipsuri, ci menținerea clarității și a ritmului de decizie."
        ]
        primary_issue = {
            "title": "Validare pozitivă: nu există blocaje majore de conversie în verificările de bază",
            "impact": (
                "Fundamentul este stabil, ceea ce reduce fricțiunea pentru vizitatori și susține programările/contactul. "
                "Câștigurile vin din ajustări fine, nu din remedieri critice."
            ),
        }
        plan = [
            "Păstrați structura actuală, dar întăriți ierarhia vizuală a CTA-ului principal.",
            "Monitorizați performanța pe mobil și actualizați periodic secțiunile-cheie pentru claritate."
        ]
        disclaimer = "Narațiune deterministă. Constatările deterministice rămân autoritare."
    else:
        overview = [
            "The site’s core structure is solid: essential decision information is present and accessible.",
            "Priority is optimization, not fixes: preserve clarity and decision momentum as traffic increases."
        ]
        primary_issue = {
            "title": "Positive validation: no major conversion blockers in baseline checks",
            "impact": (
                "The site is suitable to support paid traffic without obvious structural risk. "
                "Gains come from fine-tuning, not critical remediation."
            ),
        }
        plan = [
            "Keep the current structure, but reinforce the primary CTA’s visual hierarchy.",
            "Monitor mobile performance and refresh key sections periodically for clarity."
        ]
        disclaimer = "Automated report based on accessible content at the time of the run."

    return {
        "overview": overview,
        "primary_issue": primary_issue,
        "secondary_issues": [],
        "plan": plan,
        "confidence": confidence,
        "disclaimer": disclaimer,
    }
