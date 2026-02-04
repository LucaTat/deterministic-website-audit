"""
accessibility_heuristic.py - Lightweight A11y Checks.

Usage:
    report = audit_a11y(html_content)
"""

from bs4 import BeautifulSoup

def audit_a11y(html: str) -> dict:
    soup = BeautifulSoup(html, "html.parser")
    issues = []
    score_penalty = 0

    # 1. Images missing alt
    imgs = soup.find_all("img")
    missing_alt = 0
    for img in imgs:
        if not img.get("alt") and img.get("role") != "presentation":
             # Ignore tracking pixels 1x1
             if img.get("width") == "1" or img.get("height") == "1":
                 continue
             missing_alt += 1
    
    if missing_alt > 0:
        issues.append(f"{missing_alt} images missing 'alt' text.")
        score_penalty += (missing_alt * 2)

    # 2. Document Title
    if not soup.title or not soup.title.string.strip():
        issues.append("Document missing <title>.")
        score_penalty += 10

    # 3. Heading Hierarchy
    headings = soup.find_all(["h1", "h2", "h3", "h4", "h5", "h6"])
    if not headings:
        issues.append("No headings found (structureless).")
    else:
        # Check if exactly one h1
        h1s = [h for h in headings if h.name == "h1"]
        if len(h1s) == 0:
            issues.append("Missing <h1>.")
            score_penalty += 5
        elif len(h1s) > 1:
            issues.append("Multiple <h1> tags found.")
            score_penalty += 2

    # 4. Empty Links / Buttons
    interactives = soup.find_all(["a", "button"])
    empty_interactives = 0
    for el in interactives:
        text = el.get_text(strip=True)
        aria = el.get("aria-label") or el.get("title")
        if not text and not aria:
            empty_interactives += 1
            
    if empty_interactives > 0:
        issues.append(f"{empty_interactives} links/buttons have no text or labels.")
        score_penalty += (empty_interactives * 2)

    return {
        "score_penalty": min(score_penalty, 100), # Cap check
        "issues": issues,
        "total_checks": {
            "images": len(imgs),
            "links": len(interactives),
            "headings": len(headings)
        }
    }
