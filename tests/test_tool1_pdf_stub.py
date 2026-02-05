from pathlib import Path

import scope_engine.run_tool1 as run_tool1


def test_tool1_stub_pdf_on_render_failure(monkeypatch, tmp_path: Path, capsys) -> None:
    run_dir = tmp_path / "run"

    def fake_fetch(url: str):
        return "x" * 6000, url, 200

    def fake_capture(url: str, out_dir: str) -> None:
        return None

    def fake_audit_one(url: str, lang: str, max_pages: int = 15):
        return {
            "lang": lang,
            "signals": {"score": 0},
            "crawl_v1": {},
            "mode": "ok",
            "meta": {"timestamp_utc": "2026-02-05T00:00:00Z"},
        }

    def fake_export(*_args, **_kwargs):
        raise RuntimeError("boom")

    monkeypatch.setattr(run_tool1, "_fetch_home", fake_fetch)
    monkeypatch.setattr(run_tool1, "_capture_visual_evidence", fake_capture)
    monkeypatch.setattr(run_tool1, "audit_one", fake_audit_one)
    monkeypatch.setattr(run_tool1, "export_audit_pdf", fake_export)

    code = run_tool1.main([
        "--url",
        "https://example.com",
        "--run-dir",
        str(run_dir),
        "--lang",
        "EN",
    ])

    assert code == 26
    report_pdf = run_dir / "audit" / "report.pdf"
    assert report_pdf.exists()
    assert report_pdf.stat().st_size > 0
    out = capsys.readouterr().out
    assert "TOOL1_PDF_RENDER_FAILED" in out
