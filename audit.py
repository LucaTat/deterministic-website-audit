import requests
from bs4 import BeautifulSoup
import os
import re
from urllib.parse import urlparse
from pdf_export import export_audit_pdf
from client_narrative import build_client_narrative
from social_signals import extract_social_signals
from share_meta import extract_share_meta
from net_guardrails import (
    DEFAULT_HEADERS,
    DEFAULT_TIMEOUT,
    MAX_HTML_BYTES,
    MAX_REDIRECTS,
    ignore_robots,
    parse_robots,
    read_limited_text,
    robots_disallows,
    validate_url,
)
from visual_check import capture_screenshot

HEADERS = DEFAULT_HEADERS

BOOKING_KEYWORDS = [
    "book", "booking", "appointment", "schedule", "reserve",
    "programeaza", "programează", "programare", "programări",
    "rezervare", "rezerva", "rezervă"
]

CONTACT_KEYWORDS = [
    "contact", "call", "phone", "email", "location",
    "contacteaza", "contactează", "telefon", "email",
    "adresa", "adresă", "locatie", "locație"
]


def save_html_evidence(html: str, out_dir: str, filename: str = "home.html") -> str:
    """
    Save HTML evidence to a file and return its path.
    """
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, filename)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(html or "")
    return out_path


class FetchGuardrailError(Exception):
    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


def _site_root(url: str) -> str:
    parsed = urlparse(url)
    if not parsed.scheme or not parsed.netloc:
        return ""
    return f"{parsed.scheme}://{parsed.netloc}".rstrip("/")


def _robots_allows_url(url: str) -> bool:
    if ignore_robots():
        return True
    base = _site_root(url)
    if not base:
        return True
    robots_url = f"{base}/robots.txt"
    session = requests.Session()
    session.max_redirects = MAX_REDIRECTS
    try:
        resp = session.get(robots_url, headers=HEADERS, timeout=DEFAULT_TIMEOUT, stream=True)
        status = resp.status_code
        text, too_large = read_limited_text(resp, MAX_HTML_BYTES)
        if too_large or status != 200:
            return True
        rules = parse_robots(text)
        disallowed, _ = robots_disallows(url, rules)
        return not disallowed
    except Exception:
        return True


def fetch_html(url: str) -> str:
    session = requests.Session()
    session.max_redirects = MAX_REDIRECTS
    try:
        validate_url(url)
        if not _robots_allows_url(url):
            raise FetchGuardrailError("robots_disallowed")
        resp = session.get(url, headers=HEADERS, timeout=DEFAULT_TIMEOUT, stream=True)
        text, too_large = read_limited_text(resp, MAX_HTML_BYTES)
        if too_large:
            raise FetchGuardrailError("too_large")
        resp.raise_for_status()
        return text
    except requests.TooManyRedirects:
        raise FetchGuardrailError("too_many_redirects")


def normalize_text(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip().lower()


def page_signals(html: str) -> dict:
    soup = BeautifulSoup(html, "html.parser")
    text = normalize_text(soup.get_text(" ", strip=True))

    clickable_texts = []
    for el in soup.find_all(["a", "button"]):
        t = el.get_text(" ", strip=True)
        if t:
            clickable_texts.append(normalize_text(t))

    clickable = " ".join(clickable_texts)

    # Updated regex matching for precision
    def has_any(keywords, haystack):
        pattern = r"\b(" + "|".join(map(re.escape, keywords)) + r")\b"
        return bool(re.search(pattern, haystack))

    booking = has_any(BOOKING_KEYWORDS, text) or has_any(BOOKING_KEYWORDS, clickable)
    contact = has_any(CONTACT_KEYWORDS, text) or has_any(CONTACT_KEYWORDS, clickable)

    # Pricing regex (more robust)
    price_pattern = r"(lei|ron|€|eur|price|pret|preț|tarif|tarife)\b"
    has_price = bool(re.search(price_pattern, text))

    # Services regex
    services_pattern = r"(services|servicii|tuns|vopsit|manichiura|manichiură|pedichiura|pedichiură|coafat|tratament|abonament|membership)\b"
    has_services = bool(re.search(services_pattern, text))

    score = 0
    score += 40 if booking else 0
    score += 30 if contact else 0
    score += 15 if has_services else 0
    score += 15 if has_price else 0

    return {
        "booking_detected": booking,
        "contact_detected": contact,
        "services_keywords_detected": has_services,
        "pricing_keywords_detected": has_price,
        "score": score,
    }



def build_all_signals(html: str, page_url: str | None = None) -> dict:
    """
    Returns a single dict containing:
    - conversion clarity signals from page_signals()
    - social presence signals from extract_social_signals()
    - share preview metadata from extract_share_meta() (Open Graph + Twitter cards)

    Deterministic, no external social APIs.
    """
    base = page_signals(html)

    try:
        social = extract_social_signals(html)
    except Exception as e:
        # Conservative fallback: never break the audit because social parsing failed.
        social = {
            "social_extraction_error": str(e),
            "instagram_linked": False, "instagram_urls": [],
            "facebook_linked": False, "facebook_urls": [],
            "tiktok_linked": False, "tiktok_urls": [],
            "whatsapp_linked": False, "whatsapp_urls": [],
            "linkedin_linked": False, "linkedin_urls": [],
            "youtube_linked": False, "youtube_urls": [],
            "x_linked": False, "x_urls": [],
        }

    combined = {}
    combined.update(base)
    combined.update(social)


    # Share preview meta (Open Graph / Twitter). Stored as a nested dict to keep signals readable.
    try:
        combined["share_meta"] = extract_share_meta(html, page_url=page_url)
    except Exception as e:
        combined["share_meta"] = {"error": str(e)}

    # --- NEW SKILLS INTEGRATION ---
    try:
        import tech_detective
        import accessibility_heuristic
        import copy_critic
        import security_sentry

        # 1. Tech Stack
        combined["tech_stack"] = tech_detective.detect_tech_stack(html, {}) 
        
        # 2. Accessibility
        combined["a11y_report"] = accessibility_heuristic.audit_a11y(html)
        
        # 3. Copy Quality (extract text first)
        soup_text = BeautifulSoup(html, "html.parser").get_text(" ", strip=True)
        combined["content_quality"] = copy_critic.analyze_copy(soup_text)

        # 4. Security headers / trust signals
        combined["security_issues"] = security_sentry.check_security_headers(headers or {})
        
    except ImportError:
        pass
    except Exception as e:
        combined["skills_error"] = str(e)

    return combined


def user_insights(signals: dict) -> dict:
    """
    User-facing (internal) diagnosis + plan in English.
    Derived only from deterministic signals.
    """
    booking = bool(signals.get("booking_detected"))
    contact = bool(signals.get("contact_detected"))
    services = bool(signals.get("services_keywords_detected"))
    pricing = bool(signals.get("pricing_keywords_detected"))
    score = int(signals.get("score", 0) or 0)

    # Confidence: simple, deterministic heuristic
    if score < 70:
        confidence = "High"
    elif score < 85:
        confidence = "Medium"
    else:
        confidence = "Low"

    # Primary issue: prioritize biggest conversion blockers
    if not booking:
        primary_issue = "Visitors cannot clearly see how to book or request an appointment."
        recommended_focus = "Make the booking/appointment action obvious on the homepage."
        step1 = "Add a prominent booking button (above the fold) and repeat it in the header/navigation."
    elif not contact:
        primary_issue = "Visitors cannot easily find how to contact the business."
        recommended_focus = "Make contact details visible immediately on the homepage."
        step1 = "Place phone/email/address clearly in the header and add a strong 'Contact' call-to-action."
    else:
        primary_issue = "The website does not clearly guide visitors to take the next step."
        recommended_focus = "Improve conversion clarity on the homepage."
        step1 = "Add a clear primary call-to-action (Book / Call / Get a Quote) and reduce distractions."

    # Secondary issues: list missing items (max 3)
    secondary = []
    if not contact:
        secondary.append("Contact details are not easy to find quickly.")
    if not services:
        secondary.append("Services are not clearly explained for a first-time visitor.")
    if not pricing:
        secondary.append("Pricing guidance is missing or unclear, which reduces trust.")

    # Plan: step 1 always addresses primary issue; then fix services/pricing if missing
    steps = [step1]

    if not services:
        steps.append("Rewrite the services section in simple customer language (what it is, who it’s for, what to expect).")
    else:
        steps.append("Make services easier to scan: short headings, bullet points, and clear benefits.")

    if not pricing:
        steps.append("Add basic pricing ranges or starting prices to reduce uncertainty and increase trust.")
    else:
        steps.append("If pricing exists, make it easy to find and understand (avoid hidden pricing).")

    # Keep it tight: max 3 steps
    steps = steps[:3]

    return {
        "primary_issue": primary_issue,
        "secondary_issues": secondary[:3],
        "confidence": confidence,
        "recommended_focus": recommended_focus,
        "steps": steps,
    }


def human_summary(url: str, signals: dict, mode: str) -> str:
    if mode == "no_website":
        return (
            "Pe scurt: Business-ul nu are un website disponibil.\n"
            "Ce am observat:\n"
            "- Nu există o pagină centrală cu servicii, locație, program și detalii de contact.\n"
            "- Nu există un flux clar de programare (buton / formular / link).\n"
            "De ce contează:\n"
            "Mulți clienți aleg rapid. Fără website, încrederea scade și o parte din oameni aleg competiția.\n"
            "Ce urmează:\n"
            "Un website simplu (1 pagină) cu servicii + locație + CTA „Programează-te” rezolvă problema."
        )

    if mode == "broken":
        return (
            "Pe scurt: Există un link de website, dar pare nefuncțional / inaccesibil.\n"
            "Ce am observat:\n"
            "- La accesare apare o eroare sau pagina nu se încarcă corect.\n"
            "De ce contează:\n"
            "Orice click din Google/Maps care ajunge la eroare înseamnă lead pierdut + scade încrederea.\n"
            "Ce urmează:\n"
            "Rezolvați întâi partea de disponibilitate (hosting/domeniu/SSL).\n"
            "Detaliile tehnice sunt păstrate pentru verificare internă."
        )

    score = signals.get("score", 0)

    issues = []
    if not signals.get("booking_detected"):
        issues.append("- Nu este evident cum se face programarea (booking/appointment).")
    if not signals.get("contact_detected"):
        issues.append("- Datele de contact nu sunt ușor de găsit (telefon/email/locație).")
    if not signals.get("services_keywords_detected"):
        issues.append("- Serviciile nu sunt clar prezentate.")
    if not signals.get("pricing_keywords_detected"):
        issues.append("- Lipsesc prețuri/intervale orientative.")

    if not issues:
        issues = ["- Nu am detectat lipsuri majore la aceste verificări de bază."]

    return (
        f"Pe scurt: verificări de bază finalizate. Scor: {score}/100.\n"
        "Ce am observat:\n"
        + "\n".join(issues[:3]) + "\n"
        "De ce contează:\n"
        "Cu cât este mai ușor să înțelegi oferta și să te programezi, cu atât cresc conversiile.\n"
        "Ce urmează:\n"
        "Clarificați punctele de mai sus și retestați."
    )
