"""
security_sentry.py - Passive Security Analysis.

Usage:
    issues = check_security_headers(headers_dict)
"""

from typing import Dict, List, Any

REQUIRED_HEADERS = {
    "Strict-Transport-Security": "Missing HSTS (HTTPS enforcement).",
    "Content-Security-Policy": "Missing Content Security Policy (XSS protection).",
    "X-Frame-Options": "Missing Clickjacking protection (iframe).",
    "X-Content-Type-Options": "Missing MIME sniffing protection.",
    "Referrer-Policy": "Missing Referrer Policy."
}

def check_security_headers(headers: Dict[str, Any]) -> List[str]:
    """
    Checks for missing or misconfigured security headers.
    """
    issues = []
    # Normalize headers to lowercase for easy lookup
    h_lower = {k.lower(): v for k, v in headers.items()}
    
    for header, msg in REQUIRED_HEADERS.items():
        if header.lower() not in h_lower:
            issues.append(msg)
            
    # Check for info leakage
    server = h_lower.get("server", "").lower()
    if any(char.isdigit() for char in server):
        issues.append(f"Server version leakage: '{server}'.")
        
    powered_by = h_lower.get("x-powered-by", "")
    if powered_by:
        issues.append(f"Tech stack leakage (X-Powered-By): '{powered_by}'.")
        
    return issues

def check_sensitive_files(status_codes: Dict[str, int]) -> List[str]:
    """
    If you ran a probe on /.git, /.env, analyse the codes.
    Expects dict: {'/.git': 200, '/.env': 403}
    """
    findings = []
    for path, code in status_codes.items():
        if code == 200:
            findings.append(f"CRITICAL: Sensitive file exposed: {path}")
        elif code == 403:
            findings.append(f"INFO: Protected sensitive path: {path} (403 Forbidden)")
    return findings
