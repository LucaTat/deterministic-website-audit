import io
from pathlib import Path

from reportlab.pdfgen import canvas

from ui.widgets import ScoreGauge


def test_score_gauge_zero_arc_does_not_crash(tmp_path: Path) -> None:
    pdf_path = tmp_path / "gauge.pdf"
    c = canvas.Canvas(str(pdf_path))
    gauge = ScoreGauge(score=0, label="Score", size=40)
    gauge.wrap(0, 0)
    gauge.canv = c
    gauge.draw()
    c.showPage()
    c.save()
    assert pdf_path.exists()
    assert pdf_path.stat().st_size > 0

