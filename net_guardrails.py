from __future__ import annotations

import os
from typing import Any, Mapping
from urllib.parse import urlparse
import socket
import ipaddress

DEFAULT_USER_AGENT = "SCOPE/1.0 (+contact@astra.example)"
DEFAULT_HEADERS = {"User-Agent": DEFAULT_USER_AGENT}
DEFAULT_TIMEOUT = 15
MAX_HTML_BYTES = 2 * 1024 * 1024
MAX_REDIRECTS = 10

SENSITIVE_HEADERS = {"authorization", "cookie", "set-cookie", "x-api-key"}
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


def ignore_robots() -> bool:
    return os.environ.get("SCOPE_IGNORE_ROBOTS") == "1"


def redact_headers(headers: Mapping[str, Any]) -> dict[str, str]:
    redacted: dict[str, str] = {}
    for key, value in (headers or {}).items():
        key_str = str(key)
        lower = key_str.lower()
        if lower in SENSITIVE_HEADERS:
            redacted[key_str] = "[REDACTED]"
        else:
            redacted[key_str] = str(value)
    return redacted


def validate_url(url: str) -> None:
    """
    Validates that the URL uses a safe scheme and does not resolve to a private IP.
    Raises ValueError if unsafe.
    """
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        raise ValueError(f"Unsafe scheme: {parsed.scheme}")

    if not parsed.hostname:
        raise ValueError("Missing hostname")

    try:
        # Resolve hostname to IP
        # Note: This is a basic check. To be fully robust against TOCTOU (Time-of-check to time-of-use),
        # one would ideally patch the socket connection, but this is a good first line of defense.
        ip_list = socket.getaddrinfo(parsed.hostname, None)
        for _, _, _, _, sockaddr in ip_list:
            ip_str = sockaddr[0]
            ip_obj = ipaddress.ip_address(ip_str)
            for private_range in PRIVATE_IP_RANGES:
                if ip_obj in private_range:
                    raise ValueError(f"Target resolves to private IP: {ip_str}")
    except socket.gaierror:
        # Failsafe: if we can't resolve it, we can't verify it's not a private IP.
        # Fail closed for security.
        raise ValueError(f"DNS resolution failed for {parsed.hostname}")


def read_limited_text(resp: Any, max_bytes: int | None) -> tuple[str, bool]:
    if max_bytes is not None:
        content_length = resp.headers.get("Content-Length")
        try:
            if content_length and int(content_length) > max_bytes:
                return "", True
        except Exception:
            pass
    chunks: list[bytes] = []
    size = 0
    for chunk in resp.iter_content(chunk_size=16384):
        if not chunk:
            continue
        chunks.append(chunk)
        size += len(chunk)
        if max_bytes is not None and size > max_bytes:
            return "", True
    data = b"".join(chunks)
    encoding = resp.encoding or "utf-8"
    try:
        return data.decode(encoding, errors="replace"), False
    except Exception:
        return data.decode("utf-8", errors="replace"), False


def parse_robots(text: str) -> dict[str, list[str]]:
    ua_rules: dict[str, list[str]] = {}
    current_uas: list[str] = []
    for raw in (text or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        if "#" in line:
            line = line.split("#", 1)[0].strip()
        if not line:
            continue
        lower = line.lower()
        if lower.startswith("user-agent:"):
            ua = line.split(":", 1)[1].strip().lower()
            current_uas = [ua]
            ua_rules.setdefault(ua, [])
            continue
        if lower.startswith("disallow:"):
            rule = line.split(":", 1)[1].strip()
            if not current_uas:
                current_uas = ["*"]
            for ua in current_uas:
                ua_rules.setdefault(ua, []).append(rule)
    return ua_rules


def robots_disallows(url: str, ua_rules: dict[str, list[str]]) -> tuple[bool, str | None]:
    path = urlparse(url).path or "/"
    rules = (ua_rules.get("*", []) or []) + (ua_rules.get("scope", []) or [])
    for rule in rules:
        rule = (rule or "").strip()
        if not rule:
            continue
        if rule == "/":
            return True, rule
        if rule.startswith("/") and path.startswith(rule):
            return True, rule
    return False, None
