"""
marketing_pitch.py - Generates a high-conversion pitch based on audit results.
"""

def generate_pitch(audit_result: dict, lang: str = "en") -> str:
    verdict = audit_result.get("verdict", "N/A")
    url = audit_result.get("url", "the website")
    tech = audit_result.get("signals", {}).get("tech_stack", {})
    
    cms = tech.get("CMS", ["Custom"])[0]
    
    if lang == "ro":
        pitch = f"Subiect: Analiză Website {url} - Oportunități de Optimizare\n\n"
        pitch += f"Bună,\n\nAm finalizat analiza tehnică a site-ului {url}. Verdictul este {verdict}.\n"
        pitch += f"Am observat că folosiți {cms}. "
        if verdict == "GO":
            pitch += "Site-ul stă foarte bine și este pregătit pentru campanii de scalare."
        else:
            pitch += "Am identificat câteva puncte critice care pot bloca rata de conversie."
        pitch += "\n\nPutem discuta scurt despre cum să implementăm aceste fix-uri?\n\nCele bune."
    else:
        pitch = f"Subject: Website Audit for {url} - Actionable Insights\n\n"
        pitch += f"Hi,\n\nI just ran a deep dive on {url}. Verdict: {verdict}.\n"
        pitch += f"Current stack: {cms}. "
        if verdict == "GO":
            pitch += "The site is robust and ready for aggressive growth campaigns."
        else:
            pitch += "We found a few conversion blockers that should be fixed before scaling spend."
        pitch += "\n\nWould you like to review the full premium report together?\n\nBest."
        
    return pitch
