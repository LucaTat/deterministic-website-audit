from __future__ import annotations

import os
from typing import Any, Mapping
from urllib.parse import urlparse

DEFAULT_USER_AGENT = "SCOPE/1.0 (+contact@astra.example)"
DEFAULT_HEADERS = {"User-Agent": DEFAULT_USER_AGENT}
DEFAULT_TIMEOUT = 15
MAX_HTML_BYTES = 2 * 1024 * 1024
MAX_REDIRECTS = 10

SENSITIVE_HEADERS = {"authorization", "cookie", "set-cookie", "x-api-key"}


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
