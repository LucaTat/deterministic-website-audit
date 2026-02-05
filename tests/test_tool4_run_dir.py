from __future__ import annotations

import json
import os
import stat
import subprocess
from pathlib import Path


def test_run_tool4_passes_run_dir(tmp_path: Path) -> None:
    repo_root = Path(__file__).resolve().parents[1]
    run_dir = tmp_path / "run"
    (run_dir / "audit").mkdir(parents=True, exist_ok=True)
    (run_dir / "audit" / "verdict.json").write_text(
        json.dumps(
            {
                "url_input": "https://example.com",
                "final_url": "https://example.com",
                "timestamp_utc": "2026-02-04T00:00:00Z",
                "lang": "RO",
                "verdict": "GO",
                "categories": {},
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    fake_home = tmp_path / "home"
    astra_bin = fake_home / "Desktop" / "astra" / ".venv" / "bin"
    astra_bin.mkdir(parents=True, exist_ok=True)
    capture_path = tmp_path / "captured.txt"
    fake_python = astra_bin / "python3"
    fake_python.write_text(
        "\n".join(
            [
                "#!/usr/bin/env bash",
                "capture=\"${CAPTURE_PATH:-}\"",
                "run_dir=\"\"",
                "prev=\"\"",
                "for arg in \"$@\"; do",
                "  if [[ \"$prev\" == \"--run-dir\" ]]; then",
                "    run_dir=\"$arg\"",
                "    break",
                "  fi",
                "  prev=\"$arg\"",
                "done",
                "if [[ -n \"$capture\" ]]; then",
                "  echo \"$run_dir\" > \"$capture\"",
                "fi",
                "if [[ -n \"$run_dir\" ]]; then",
                "  echo \"ASTRA_RUN_DIR=$run_dir\"",
                "  echo \"ASTRA_AUDIT_DIR=$run_dir/audit\"",
                "fi",
                "exit 0",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    fake_python.chmod(fake_python.stat().st_mode | stat.S_IXUSR)

    env = os.environ.copy()
    env["HOME"] = str(fake_home)
    env["CAPTURE_PATH"] = str(capture_path)

    result = subprocess.run(
        ["bash", str(repo_root / "scripts" / "run_tool4_regression.sh"), str(run_dir)],
        cwd=repo_root,
        env=env,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert capture_path.read_text(encoding="utf-8").strip() == str(run_dir)
