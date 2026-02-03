"""
tech_detective.py - Identify CMS, Analytics, and Libraries.

Usage:
    tech = detect_tech_stack(html_content, headers_dict)
"""

import re
from typing import Dict, List

# Signatures for detection
# Format: "Category": {"Technology": [Regex/Checks]}
SIGNATURES = {
    "CMS": {
        "WordPress": [
            r"wp-content", r"wp-includes", r"generator.*WordPress"
        ],
        "Shopify": [
            r"cdn\.shopify\.com", r"Shopify\.shop", r"shopify-section"
        ],
        "Wix": [
            r"wix\.com", r"X-Wix-Request-Id"
        ],
        "Squarespace": [
            r"squarespace\.com", r"static1\.squarespace"
        ],
        "Joomla": [
            r"generator.*Joomla"
        ],
        "Drupal": [
            r"Drupal", r"sites/all/modules"
        ],
        "Webflow": [
            r"webflow\.com", r"w-nav-overlay"
        ]
    },
    "Analytics": {
        "Google Analytics 4": [
            r"googletagmanager\.com/gtag/js", r"G-[A-Z0-9]{10}"
        ],
        "Google Tag Manager": [
            r"googletagmanager\.com/gtm\.js", r"GTM-[A-Z0-9]+"
        ],
        "Segment": [
            r"cdn\.segment\.com", r"analytics\.load"
        ],
        "Hotjar": [
            r"static\.hotjar\.com", r"hj\('identify'\)"
        ],
        "Facebook Pixel": [
            r"connect\.facebook\.net/en_US/fbevents\.js", r"fbq\('init'"
        ]
    },
    "Marketing": {
        "HubSpot": [
            r"hs-scripts\.com", r"hs-cta-wrapper"
        ],
        "Klaviyo": [
            r"static\.klaviyo\.com", r"klaviyo\.push"
        ],
        "Mailchimp": [
            r"chimpstatic\.com", r"mc-validate"
        ],
        "Intercom": [
            r"widget\.intercom\.io"
        ],
        "Drift": [
            r"driftt\.com"
        ]
    },
    "Infrastructure": {
        "Cloudflare": [
            r"server: cloudflare", r"cf-ray"
        ],
        "Netlify": [
            r"server: Netlify"
        ],
        "Vercel": [
            r"server: Vercel"
        ],
        "Nginx": [
            r"server: nginx"
        ],
        "Apache": [
            r"server: Apache"
        ]
    },
    "Libraries": {
        "React": [
            r"react-dom", r"data-reactroot"
        ],
        "Vue.js": [
            r"data-v-", r"vue\.bak"
        ],
        "jQuery": [
            r"jquery\.min\.js", r"jquery\.js"
        ],
        "Bootstrap": [
            r"bootstrap\.min\.css", r"bootstrap\.css"
        ],
        "Tailwind CSS": [
            r"tailwindcss"
        ]
    }
}

def detect_tech_stack(html: str, headers: Dict[str, str] = None) -> Dict[str, List[str]]:
    """
    Analyzes HTML and Headers to return identified technologies.
    Returns: {"CMS": ["WordPress"], "Analytics": ["GA4", "Hotjar"], ...}
    """
    if headers is None:
        headers = {}
    
    # Combine HTML and Headers for simple regex searching
    # (Headers converted to string usually helps matching)
    header_str = str(headers)
    content = html + " " + header_str
    
    detected: Dict[str, List[str]] = {}
    
    for category, techs in SIGNATURES.items():
        detected[category] = []
        for tech_name, patterns in techs.items():
            for pattern in patterns:
                # Case insensitive search
                if re.search(pattern, content, re.IGNORECASE):
                    detected[category].append(tech_name)
                    break # Found this tech, move to next
                    
    return detected
