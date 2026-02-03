"""
theme.py - Premium Design System for PDF Reports.
"""

from reportlab.lib.colors import HexColor, Color
from reportlab.lib.styles import StyleSheet1, ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_RIGHT
from reportlab.lib.units import mm

class Theme:
    # Color Palette (Modern Slate/Blue)
    PRIMARY = HexColor("#0f172a")    # Slate 900
    SECONDARY = HexColor("#334155")  # Slate 700
    ACCENT = HexColor("#2563eb")     # Blue 600
    
    TEXT_MAIN = HexColor("#1e293b")  # Slate 800
    TEXT_LIGHT = HexColor("#64748b") # Slate 500
    
    BG_LIGHT = HexColor("#f8fafc")   # Slate 50
    BORDER = HexColor("#e2e8f0")     # Slate 200
    
    SUCCESS = HexColor("#16a34a")
    WARNING = HexColor("#d97706")
    ERROR = HexColor("#dc2626")

    @classmethod
    def get_stylesheet(cls):
        s = StyleSheet1()
        
        # Base Body
        s.add(ParagraphStyle(
            name='Body',
            fontName='DejaVuSans',
            fontSize=10,
            leading=14,
            textColor=cls.TEXT_MAIN,
            spaceAfter=6
        ))
        
        # Heading 1 (Section Title)
        s.add(ParagraphStyle(
            name='H1',
            parent=s['Body'],
            fontName='DejaVuSans-Bold',
            fontSize=16,
            leading=20,
            textColor=cls.PRIMARY,
            spaceBefore=18,
            spaceAfter=12,
            borderPadding=(0, 0, 8, 0), # Bottom border padding
            borderWidth=0,
            borderColor=cls.ACCENT
        ))

        # Heading 2 (Subsection)
        s.add(ParagraphStyle(
            name='H2',
            parent=s['Body'],
            fontName='DejaVuSans-Bold',
            fontSize=12,
            leading=16,
            textColor=cls.SECONDARY,
            spaceBefore=12,
            spaceAfter=6
        ))

        # Small Text
        s.add(ParagraphStyle(
            name='Small',
            parent=s['Body'],
            fontSize=8,
            leading=10,
            textColor=cls.TEXT_LIGHT
        ))
        
        # Badge/Label
        s.add(ParagraphStyle(
            name='Label',
            parent=s['Body'],
            fontName='DejaVuSans-Bold',
            fontSize=9,
            textColor=cls.ACCENT
        ))

        return s
