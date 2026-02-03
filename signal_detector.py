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
    "booking": r"\b(book|appointment|reservation|schedule|programare|rezervare)\b",
    "contact": r"\b(contact|email|phone|call|whatsapp|adresă|locație|location)\b",
    "pricing": r"\b(price|pricing|cost|rates|lei|ron|eur|€|preț|tarif|tarife)\b",
    "services": r"\b(services|servicii|menu|oferta|tuns|vopsit|manichiura|pedichiura|coafat|tratament)\b"
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
