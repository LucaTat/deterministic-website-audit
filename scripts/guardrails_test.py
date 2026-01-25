#!/usr/bin/env python3
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from net_guardrails import parse_robots, robots_disallows, redact_headers


def test_robots_disallows():
    robots_txt = """
    User-agent: *
    Disallow: /private
    User-agent: SCOPE
    Disallow: /secret
    """
    rules = parse_robots(robots_txt)
    disallowed, _ = robots_disallows("https://example.com/private/page", rules)
    assert disallowed is True
    disallowed, _ = robots_disallows("https://example.com/secret/page", rules)
    assert disallowed is True
    disallowed, _ = robots_disallows("https://example.com/public", rules)
    assert disallowed is False


def test_redact_headers():
    headers = {
        "Authorization": "Bearer abc",
        "Cookie": "session=abc",
        "Set-Cookie": "session=abc",
        "X-Api-Key": "secret",
        "Content-Type": "text/html",
    }
    redacted = redact_headers(headers)
    assert redacted["Authorization"] == "[REDACTED]"
    assert redacted["Cookie"] == "[REDACTED]"
    assert redacted["Set-Cookie"] == "[REDACTED]"
    assert redacted["X-Api-Key"] == "[REDACTED]"
    assert redacted["Content-Type"] == "text/html"


def main() -> int:
    test_robots_disallows()
    test_redact_headers()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
