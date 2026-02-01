import os

# Agency Details
AGENCY_NAME = os.getenv("AUDIT_AGENCY_NAME", "Digital Audit Studio")
AGENCY_CONTACT = os.getenv("AUDIT_AGENCY_CONTACT", "contact@digitalaudit.ro")

# Defaults
DEFAULT_CAMPAIGN = os.getenv("AUDIT_DEFAULT_CAMPAIGN", "2025-Q1-outreach")
DEFAULT_LANG = os.getenv("AUDIT_DEFAULT_LANG", "en")

# Logging
LOG_LEVEL = os.getenv("AUDIT_LOG_LEVEL", "INFO").upper()

# Paths
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
ASSETS_DIR = os.path.join(BASE_DIR, "assets")
FONTS_DIR = os.path.join(ASSETS_DIR, "fonts")
