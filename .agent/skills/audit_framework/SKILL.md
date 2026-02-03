---
name: audit_framework
description: A comprehensive framework for deterministic website auditing, visual verification, and secure fetching.
---

# Audit Framework Skill

This skill provides a robust, production-grade toolkit for auditing websites. It replaces ad-hoc scripts with reusable, secure, and performant components.

## Components

### 1. Visual Verification (`scripts/visual_engine.py`)
A fast, persistent browser engine using Playwright.
**Usage**:
```python
from visual_engine import VisualVerifier
with VisualVerifier() as vv:
    result = vv.capture("https://example.com", output_path, device_type="mobile")
```

### 2. Signal Detection (`scripts/signal_detector.py`)
Precision keyword matching using Regex word boundaries.
**Usage**:
```python
from signal_detector import detect_page_signals
signals = detect_page_signals(html_content)
# Returns: {'booking_detected': True, ...}
```

### 3. Secure Fetching (`scripts/safe_fetch.py`)
SSRF-proof HTTP client.
**Usage**:
```python
from safe_fetch import safe_get
response = safe_get("https://example.com")
```

### 4. Tech Detective (`scripts/tech_detective.py`)
Identifies CMS, Analytics, and frameworks from HTML/Headers.
**Usage**:
```python
from tech_detective import detect_tech_stack
stack = detect_tech_stack(html, response.headers)
# Returns: {'CMS': ['WordPress'], 'Analytics': ['GA4']}
```

### 5. Accessibility Heuristic (`scripts/accessibility_heuristic.py`)
Python-based checking for common a11y failures (missing alt, empty links).
**Usage**:
```python
from accessibility_heuristic import audit_a11y
report = audit_a11y(html)
# Returns: {'issues': ['Missing <h1>'], 'score_penalty': 10}
```

### 6. Security Sentry (`scripts/security_sentry.py`)
Checks security headers and potential information leakage.
**Usage**:
```python
from security_sentry import check_security_headers
vulns = check_security_headers(response.headers)
# Returns: ['Missing HSTS', ...]
```

### 7. Copy Critic (`scripts/copy_critic.py`)
Analyzes readability (Flesch Score), tone (You/We ratio), and word count.
**Usage**:
```python
from copy_critic import analyze_copy
metrics = analyze_copy(visible_text)
# Returns: {'flesch_score': 65.2, 'tone_label': 'Customer-Centric'}
```

### 8. Web Vitals (`scripts/web_vitals.py`)
Extracts LCP and CLS using injected PerformanceObserver.
**Usage**:
```python
# With active Playwright page
from web_vitals import measure_vitals
metrics = measure_vitals(page)
```

## Integration

To use this skill in a project:
1. Copy the desired script from `scripts/` to your project's `lib/` or `utils/` directory.
2. Import normally.
