import hashlib
import os
import subprocess
import sys
import zipfile
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
    deliverables_dir = run_dir / "deliverables"
    deliverables_dir.mkdir(parents=True, exist_ok=True)
    (deliverables_dir / "verdict.json").write_text(
        '{"status":"ok","summary":"test verdict"}',
        encoding="utf-8",
    )
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


def test_finalize_run_creates_checksums(tmp_path: Path) -> None:
    run_dir = tmp_path / "run_ro"
    deliverables_dir = run_dir / "deliverables"
    deliverables_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "audit").mkdir(parents=True, exist_ok=True)

    (run_dir / "audit" / "verdict.json").write_text(
        '{"status":"ok","summary":"test verdict"}',
        encoding="utf-8",
    )
    (deliverables_dir / "verdict.json").write_text(
        '{"status":"ok","summary":"test verdict"}',
        encoding="utf-8",
    )

    write_pdf(run_dir / "audit" / "report.pdf", 1)
    write_pdf(deliverables_dir / "Decision_Brief_RO.pdf", 1)
    write_pdf(deliverables_dir / "Evidence_Appendix_RO.pdf", 1)
    write_pdf(run_dir / "action_scope" / "action_scope.pdf", 1)
    write_pdf(run_dir / "proof_pack" / "proof_pack.pdf", 1)
    write_pdf(run_dir / "regression" / "regression.pdf", 1)

    write_pdf(run_dir / "final" / "master.pdf", 1)
    write_pdf(run_dir / "final" / "MASTER_BUNDLE.pdf", 1)

    zip_path = run_dir / "final" / "client_safe_bundle.zip"
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    zip_entries = [
        "audit/report.pdf",
        "action_scope/action_scope.pdf",
        "proof_pack/proof_pack.pdf",
        "regression/regression.pdf",
        "deliverables/Decision_Brief_RO.pdf",
        "deliverables/Evidence_Appendix_RO.pdf",
        "deliverables/verdict.json",
        "final/master.pdf",
        "final/MASTER_BUNDLE.pdf",
    ]
    with zipfile.ZipFile(zip_path, "w") as zf:
        for rel in zip_entries:
            zf.write(run_dir / rel, rel)

    script = Path(__file__).resolve().parents[1] / "scripts" / "finalize_run.sh"
    result = subprocess.run(
        ["bash", str(script), str(run_dir), "RO"],
        capture_output=True,
        text=True,
        env={**os.environ, "SCOPE_FINALIZE_SKIP_BUILD": "1"},
    )
    assert result.returncode == 0, result.stderr

    checksums_path = run_dir / "final" / "checksums.sha256"
    assert checksums_path.is_file()

    lines = [line.strip() for line in checksums_path.read_text().splitlines() if line.strip()]
    entries: dict[str, str] = {}
    for line in lines:
        digest, name = line.split(None, 1)
        entries[name] = digest

    with zipfile.ZipFile(zip_path, "r") as zf:
        names = [n for n in zf.namelist() if not n.endswith("/")]
        for name in names:
            data = zf.read(name)
            expected = hashlib.sha256(data).hexdigest()
            assert entries.get(name) == expected


def test_finalize_run_missing_required(tmp_path: Path) -> None:
    run_dir = tmp_path / "run_ro"
    deliverables_dir = run_dir / "deliverables"
    deliverables_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "audit").mkdir(parents=True, exist_ok=True)

    (run_dir / "audit" / "verdict.json").write_text(
        '{"status":"ok","summary":"test verdict"}',
        encoding="utf-8",
    )
    (deliverables_dir / "verdict.json").write_text(
        '{"status":"ok","summary":"test verdict"}',
        encoding="utf-8",
    )

    write_pdf(run_dir / "audit" / "report.pdf", 1)
    write_pdf(deliverables_dir / "Decision_Brief_RO.pdf", 1)
    write_pdf(deliverables_dir / "Evidence_Appendix_RO.pdf", 1)
    write_pdf(run_dir / "action_scope" / "action_scope.pdf", 1)
    write_pdf(run_dir / "proof_pack" / "proof_pack.pdf", 1)
    # regression.pdf intentionally missing

    script = Path(__file__).resolve().parents[1] / "scripts" / "finalize_run.sh"
    result = subprocess.run(
        ["bash", str(script), str(run_dir), "RO"],
        capture_output=True,
        text=True,
        env={**os.environ, "SCOPE_FINALIZE_SKIP_BUILD": "1"},
    )
    assert result.returncode != 0


def test_finalize_run_no_cross_run_fallback(tmp_path: Path) -> None:
    run_a = tmp_path / "run_a"
    run_b = tmp_path / "run_b"

    deliverables_a = run_a / "deliverables"
    deliverables_b = run_b / "deliverables"
    deliverables_a.mkdir(parents=True, exist_ok=True)
    deliverables_b.mkdir(parents=True, exist_ok=True)
    (run_a / "audit").mkdir(parents=True, exist_ok=True)
    (run_b / "audit").mkdir(parents=True, exist_ok=True)

    (run_a / "audit" / "verdict.json").write_text("{}", encoding="utf-8")
    (run_b / "audit" / "verdict.json").write_text("{}", encoding="utf-8")
    (deliverables_a / "verdict.json").write_text("{}", encoding="utf-8")
    (deliverables_b / "verdict.json").write_text("{}", encoding="utf-8")

    write_pdf(run_a / "audit" / "report.pdf", 1)
    write_pdf(run_a / "action_scope" / "action_scope.pdf", 1)
    write_pdf(run_a / "proof_pack" / "proof_pack.pdf", 1)
    # regression.pdf intentionally missing in run_a
    write_pdf(deliverables_a / "Decision_Brief_RO.pdf", 1)
    write_pdf(deliverables_a / "Evidence_Appendix_RO.pdf", 1)

    write_pdf(run_b / "audit" / "report.pdf", 1)
    write_pdf(run_b / "action_scope" / "action_scope.pdf", 1)
    write_pdf(run_b / "proof_pack" / "proof_pack.pdf", 1)
    write_pdf(run_b / "regression" / "regression.pdf", 1)
    write_pdf(deliverables_b / "Decision_Brief_RO.pdf", 1)
    write_pdf(deliverables_b / "Evidence_Appendix_RO.pdf", 1)

    script = Path(__file__).resolve().parents[1] / "scripts" / "finalize_run.sh"
    result = subprocess.run(
        ["bash", str(script), str(run_a), "RO"],
        capture_output=True,
        text=True,
        env={**os.environ, "SCOPE_FINALIZE_SKIP_BUILD": "1"},
    )
    assert result.returncode != 0


def test_verify_client_safe_zip_allowlist(tmp_path: Path) -> None:
    run_dir = tmp_path / "run_ro"
    deliverables_dir = run_dir / "deliverables"
    deliverables_dir.mkdir(parents=True, exist_ok=True)

    write_pdf(run_dir / "audit" / "report.pdf", 1)
    write_pdf(run_dir / "action_scope" / "action_scope.pdf", 1)
    write_pdf(run_dir / "proof_pack" / "proof_pack.pdf", 1)
    write_pdf(run_dir / "regression" / "regression.pdf", 1)
    write_pdf(deliverables_dir / "Decision_Brief_RO.pdf", 1)
    write_pdf(deliverables_dir / "Evidence_Appendix_RO.pdf", 1)
    (deliverables_dir / "verdict.json").write_text("{}", encoding="utf-8")
    write_pdf(run_dir / "final" / "master.pdf", 1)
    write_pdf(run_dir / "final" / "MASTER_BUNDLE.pdf", 1)

    zip_path = run_dir / "final" / "client_safe_bundle.zip"
    zip_path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "w") as zf:
        zf.write(run_dir / "audit" / "report.pdf", "audit/report.pdf")
        zf.write(run_dir / "action_scope" / "action_scope.pdf", "action_scope/action_scope.pdf")
        zf.write(run_dir / "proof_pack" / "proof_pack.pdf", "proof_pack/proof_pack.pdf")
        zf.write(run_dir / "regression" / "regression.pdf", "regression/regression.pdf")
        zf.write(deliverables_dir / "Decision_Brief_RO.pdf", "deliverables/Decision_Brief_RO.pdf")
        zf.write(deliverables_dir / "Evidence_Appendix_RO.pdf", "deliverables/Evidence_Appendix_RO.pdf")
        zf.write(deliverables_dir / "verdict.json", "deliverables/verdict.json")
        zf.write(run_dir / "final" / "master.pdf", "final/master.pdf")
        zf.write(run_dir / "final" / "MASTER_BUNDLE.pdf", "final/MASTER_BUNDLE.pdf")
        zf.writestr("unexpected.txt", "nope")

    script = Path(__file__).resolve().parents[1] / "scripts" / "verify_client_safe_zip.py"
    result = subprocess.run(
        [sys.executable, str(script), str(zip_path)],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
