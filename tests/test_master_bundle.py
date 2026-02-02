import subprocess
import sys
from pathlib import Path

from pypdf import PdfReader, PdfWriter


def write_pdf(path: Path, pages: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    writer = PdfWriter()
    for _ in range(pages):
        writer.add_blank_page(width=72, height=72)
    with path.open("wb") as f:
        writer.write(f)


def test_build_master_bundle_success(tmp_path: Path) -> None:
    run_dir = tmp_path / "run_ro"
    write_pdf(run_dir / "audit" / "report.pdf", 1)
    write_pdf(run_dir / "action_scope" / "action_scope.pdf", 1)
    write_pdf(run_dir / "proof_pack" / "proof_pack.pdf", 1)
    write_pdf(run_dir / "regression" / "regression.pdf", 1)
    write_pdf(run_dir / "final" / "master.pdf", 1)

    script = Path(__file__).resolve().parents[1] / "scripts" / "build_master_bundle.py"
    result = subprocess.run(
        [sys.executable, str(script), "--run-dir", str(run_dir)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0

    out_pdf = run_dir / "final" / "MASTER_BUNDLE.pdf"
    assert out_pdf.is_file()
    reader = PdfReader(str(out_pdf))
    assert len(reader.pages) == 5


def test_build_master_bundle_missing_input(tmp_path: Path) -> None:
    run_dir = tmp_path / "run_ro"
    write_pdf(run_dir / "audit" / "report.pdf", 1)
    write_pdf(run_dir / "action_scope" / "action_scope.pdf", 1)
    write_pdf(run_dir / "proof_pack" / "proof_pack.pdf", 1)
    write_pdf(run_dir / "final" / "master.pdf", 1)

    script = Path(__file__).resolve().parents[1] / "scripts" / "build_master_bundle.py"
    result = subprocess.run(
        [sys.executable, str(script), "--run-dir", str(run_dir)],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
