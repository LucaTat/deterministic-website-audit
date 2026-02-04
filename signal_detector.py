"""
signal_detector.py - Regex-based intent detection for audit signals.

Usage:
    signals = detect_page_signals(html_text)
"""

import re
from bs4 import BeautifulSoup

def normalize_text(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip().lower()

# Regex Patterns
# \b boundary ensures we match "book" but not "bookkeeper" (unless desired)
PATTERNS = {
    "booking": r"\b(book|booking|bookings|appointment|appointments|reservation|reservations|schedule|programare|programari|rezervare|rezervari)\b",
    "contact": r"\b(contact|contacts|contact us|contacteaza|contactează|email|phone|call|whatsapp|adresă|adresa|locație|locatie|location|locations)\b",
    "pricing": r"\b(price|prices|pricing|cost|costs|rates|lei|ron|eur|€|preț|pret|prețuri|preturi|tarif|tarife)\b",
    "services": r"\b(services|service|servicii|serviciu|menu|oferta|oferte|tuns|vopsit|manichiura|pedichiura|coafat|tratament|tratamente)\b"
}

def detect_page_signals(html: str) -> dict:
    """
    Analyzes HTML content for business signals using robust regex.
    """
    soup = BeautifulSoup(html, "html.parser")
    text = normalize_text(soup.get_text(" ", strip=True))
    
    # Also check clickable elements specifically
    clickable_texts = []
    for el in soup.find_all(["a", "button"]):
        t = el.get_text(" ", strip=True)
        if t:
            clickable_texts.append(normalize_text(t))
    clickable = " ".join(clickable_texts)

    results = {}
    for key, pattern in PATTERNS.items():
        # Check in general text or specifically in clickable elements
        found = bool(re.search(pattern, text, re.IGNORECASE)) or \
                bool(re.search(pattern, clickable, re.IGNORECASE))
        results[f"{key}_detected"] = found

    # Legacy scoring compatibility
    score = 0
    if results.get("booking_detected"): score += 40
    if results.get("contact_detected"): score += 30
    if results.get("services_detected"): score += 15
    if results.get("pricing_detected"): score += 15
    results["score"] = score

    return results

def detect_url_signals(url: str) -> dict:
    """
    Analyzes URL string for business signals.
    """
    text = normalize_text(url)
    results = {}
    found_any = False
    
    for key, pattern in PATTERNS.items():
        found = bool(re.search(pattern, text, re.IGNORECASE))
        results[f"{key}_detected"] = found
        if found:
            found_any = True
            
    results["found_any"] = found_any
    return results
