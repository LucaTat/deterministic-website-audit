#!/usr/bin/env python3
import os
import sys

# Ensure root directory is in python path
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from net_guardrails import parse_robots, robots_disallows, redact_headers
from safe_fetch import safe_get
import signal_detector


def test_robots_disallows():
    print("Testing robots.txt logic...")
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
    print("PASS: robots.txt logic")


def test_redact_headers():
    print("Testing header redaction...")
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
    print("PASS: header redaction")


def test_safe_fetch_logic():
    print("Testing safe_fetch logic...")

    # 1. Test Private IP Check (Should BLOCK)
    try:
        print("Testing 127.0.0.1 (Private)...")
        try:
            safe_get("http://127.0.0.1")
            print("FAIL: safe_get accepted 127.0.0.1")
            sys.exit(1)
        except ValueError as e:
            print(f"SUCCESS: safe_get blocked 127.0.0.1: {e}")
            if "private IP" not in str(e):
                    print(f"FAIL: Wrong error message: {e}")
                    sys.exit(1)
    except Exception as e:
        print(f"FAIL: Unexpected error on private IP: {e}")
        sys.exit(1)


    # 2. Test Public IP Check (Should PASS validation, might fail connection)
    try:
        print("Testing 8.8.8.8 (Public)...")
        try:
            safe_get("http://8.8.8.8", timeout=1)
            print("SUCCESS: safe_get connected to 8.8.8.8")
        except ValueError as e:
            print(f"FAIL: safe_get blocked 8.8.8.8: {e}")
            sys.exit(1)
        except Exception as e:
            print(f"SUCCESS: safe_get accepted 8.8.8.8 (connection failed as expected/allowed: {e})")
    
    except Exception as e:
        print(f"FAIL: Unexpected error on public IP: {e}")
        sys.exit(1)

    print("PASS: safe_fetch logic")


def test_signals():
    print("Testing signal detector...")
    
    # Test URL signals
    cases = [
        ("https://example.com/contact-us", "contact"),
        ("https://example.com/book-now", "booking"),
        ("https://example.com/prices", "pricing"),
        ("https://example.com/services", "services"),
        ("https://example.com/programare", "booking"), # RO
        ("https://example.com/contacteaza-ne", "contact"), # RO
        ("https://example.com/some-random-page", None),
    ]
    
    for url, expected in cases:
        signals = signal_detector.detect_url_signals(url)
        if expected:
            key = f"{expected}_detected"
            if not signals.get(key):
                print(f"FAIL: {url} expected {expected} but got {signals}")
                sys.exit(1)
            print(f"PASS: {url} -> {expected}")
        else:
            if signals.get("found_any"):
                 print(f"FAIL: {url} expected None but got {signals}")
                 sys.exit(1)
            print(f"PASS: {url} -> None")

    print("PASS: signal detection")


def main() -> int:
    test_robots_disallows()
    test_redact_headers()
    test_safe_fetch_logic()
    test_signals()
    print("\nAll Guardrails Tests Passed!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
