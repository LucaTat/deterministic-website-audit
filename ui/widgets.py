"""
widgets.py - Custom visual elements for reports.
"""

from reportlab.platypus import Flowable, Table, TableStyle
import math

from reportlab.lib import colors
from reportlab.graphics.shapes import Drawing, Circle, String, Wedge
from reportlab.lib.units import mm
from .theme import Theme

class ScoreGauge(Flowable):
    """
    Draws a circular score gauge.
    """
    def __init__(self, score: int, label: str = "Score", size: int = 40):
        super().__init__()
        self.score = score
        self.label = label
        self.size = size
        self.width = size * 2
        self.height = size * 2

    def draw(self):
        score_value = 0.0
        try:
            score_value = float(self.score)
        except (TypeError, ValueError):
            score_value = 0.0

        if not math.isfinite(score_value):
            score_value = 0.0

        score_value = max(0.0, min(100.0, score_value))
        display_score = int(round(score_value))

        # Determine Color
        c = Theme.ERROR
        if score_value > 50:
            c = Theme.WARNING
        if score_value > 80:
            c = Theme.SUCCESS
        
        cx, cy = self.size, self.size
        r_outer = self.size
        r_inner = self.size * 0.85
        
        # Background Circle (Light)
        # Handle HexColor to Color conversion for fading
        bg_color = colors.Color(c.red, c.green, c.blue, alpha=0.15)
        self.canv.setFillColor(bg_color)
        self.canv.circle(cx, cy, r_outer, stroke=0, fill=1)
        
        # Segment (Arc)
        # 360 degrees. Start at 90 (top).
        # ReportLab Wedge: (cx, cy, radius, startAng, extent)
        angle = 3.6 * score_value
        draw_arc = angle > 0.001
        
        # We want to emulate a stroke, so we draw a wedge then a white circle inside
        if draw_arc:
            self.canv.setFillColor(c)
            self.canv.saveState()
            p = self.canv.beginPath()
            p.moveTo(cx, cy)
            p.arc(cx-r_outer, cy-r_outer, cx+r_outer, cy+r_outer, 90, -angle) # Negative creates clockwise
            p.lineTo(cx, cy)
            p.close()
            self.canv.drawPath(p, fill=1, stroke=0)
            self.canv.restoreState()
        
        # Inner White Circle (Donut)
        self.canv.setFillColor(colors.white)
        self.canv.circle(cx, cy, r_inner, stroke=0, fill=1)
        
        # Text
        self.canv.setFillColor(Theme.PRIMARY)
        self.canv.setFont("DejaVuSans-Bold", self.size * 0.5)
        self.canv.drawCentredString(cx, cy - (self.size*0.1), str(display_score))
        
        self.canv.setFillColor(Theme.TEXT_LIGHT)
        self.canv.setFont("DejaVuSans", self.size * 0.2)
        self.canv.drawCentredString(cx, cy - (self.size*0.4), self.label)

def create_card_table(data, col_widths=None):
    """
    Returns a Table formatted like a generic UI card.
    """
    t = Table(data, colWidths=col_widths)
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), colors.white),
        ('FONTNAME', (0,0), (-1,0), 'DejaVuSans-Bold'), # Header
        ('TEXTCOLOR', (0,0), (-1,0), Theme.PRIMARY),
        ('BOTTOMPADDING', (0,0), (-1,-1), 8),
        ('TOPPADDING', (0,0), (-1,-1), 8),
        ('GRID', (0,0), (-1,-1), 0.5, Theme.BORDER),
        ('ALIGN', (0,0), (-1,-1), 'LEFT'),
        ('VALIGN', (0,0), (-1,-1), 'TOP'),
    ]))
    return t
