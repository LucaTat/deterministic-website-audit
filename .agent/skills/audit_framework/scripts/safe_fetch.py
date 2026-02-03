"""
safe_fetch.py - SSRF-protected HTTP client.

Usage:
    resp = safe_get("https://example.com")
"""

import socket
import ipaddress
import requests
from urllib.parse import urlparse

DEFAULT_TIMEOUT = 10
MAX_REDIRECTS = 5
USER_AGENT = "AuditBot/1.0 (+http://example.com)"

PRIVATE_IP_RANGES = [
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    ipaddress.ip_network("127.0.0.0/8"),
    ipaddress.ip_network("169.254.0.0/16"),
    ipaddress.ip_network("::1/128"),
    ipaddress.ip_network("fc00::/7"),
    ipaddress.ip_network("fe80::/10"),
]

def validate_url(url: str) -> None:
    """
    Raises ValueError if URL is unsafe (scheme or private IP).
    """
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError(f"Unsafe scheme: {parsed.scheme}")

    hostname = parsed.hostname
    if not hostname:
        raise ValueError("Missing hostname")

    try:
        # Resolve to IP
        # NOTE: This is vulnerable to DNS Rebinding (TOCTOU).
        # For max security, use a custom TransportAdapter that pins the IP.
        for _, _, _, _, sockaddr in socket.getaddrinfo(hostname, None):
            ip_str = sockaddr[0]
            ip_obj = ipaddress.ip_address(ip_str)
            for private_range in PRIVATE_IP_RANGES:
                if ip_obj in private_range:
                    raise ValueError(f"Target resolves to private IP: {ip_str}")
    except socket.gaierror:
        # Fail closed
        raise ValueError(f"DNS resolution failed for {hostname}")

def safe_get(url: str, **kwargs) -> requests.Response:
    """
    Wrapper around requests.get that performs SSRF checks first.
    """
    validate_url(url)
    
    kwargs.setdefault("timeout", DEFAULT_TIMEOUT)
    headers = kwargs.get("headers", {})
    headers.setdefault("User-Agent", USER_AGENT)
    kwargs["headers"] = headers
    
    session = requests.Session()
    session.max_redirects = MAX_REDIRECTS
    
    # We must handle redirects manually to check intermediate URLs
    resp = session.get(url, allow_redirects=False, **kwargs)
    
    # Basic redirect loop handling
    history = []
    while resp.is_redirect and len(history) < MAX_REDIRECTS:
        location = resp.headers.get("Location")
        if not location:
            break
            
        # Handle relative redirects
        if location.startswith("/"):
            parsed = urlparse(url)
            location = f"{parsed.scheme}://{parsed.netloc}{location}"
            
        validate_url(location) # Check the NEXT url
        history.append(resp)
        resp = session.get(location, allow_redirects=False, **kwargs)
        
    resp.history = history
    return resp
