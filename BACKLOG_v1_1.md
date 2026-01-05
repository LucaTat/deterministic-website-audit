# v1.1 Backlog (Proposed)

This file lists potential post-v1.0 improvements.
Nothing here is implemented until explicitly approved.

## High-priority (defensible, deterministic)
- HTTP security headers detection (CSP, HSTS, X-Frame-Options, Referrer-Policy)
- hreflang validation (only if tags already exist)
- Pagination indexability signals (rel=next / rel=prev detection)
- Canonical ↔ hreflang consistency (only when both are present)

## Medium-priority
- robots.txt Allow rule validation
- Sitemap lastmod sanity checks (presence + format only)
- Detection of indexable thank-you / confirmation pages

## Explicitly rejected (non-goals)
- PageSpeed / Lighthouse / CWV
- Accessibility scoring
- SEO scores or grades
- Keyword rankings
- Backlink analysis
- Content quality scoring
- AI-generated findings or severity
