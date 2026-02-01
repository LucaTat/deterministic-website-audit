#!/usr/bin/env python3
import json
import os
import sys
from datetime import datetime, timezone


def _best_lang(run_dir: str, run_base: str) -> str:
    base_lower = run_base.lower()
    if base_lower.endswith("_ro"):
        return "RO"
    if base_lower.endswith("_en"):
        return "EN"
    verdict_path = os.path.join(run_dir, "astra", "verdict.json")
    if os.path.isfile(verdict_path):
        try:
            with open(verdict_path, "r", encoding="utf-8") as f:
                data = json.load(f)
            lang = (data.get("lang") or "").strip().upper()
            if lang in ("RO", "EN"):
                return lang
        except Exception:
            pass
    return ""


def _best_domain(run_base: str) -> str:
    parts = run_base.split("_")
    if len(parts) < 2:
        return run_base
    last = parts[-1].lower()
    if last in ("ro", "en"):
        return parts[-2]
    return parts[-1]


def _has_pdf(dir_path: str) -> bool:
    if not os.path.isdir(dir_path):
        return False
    for name in os.listdir(dir_path):
        if name.lower().endswith(".pdf"):
            return True
    return False


def main() -> int:
    if len(sys.argv) != 2:
        print("ERROR usage: write_final_manifest.py <RUN_DIR>")
        return 2
    run_dir = os.path.abspath(sys.argv[1])
    if not os.path.isdir(run_dir):
        print("ERROR run dir not found")
        return 2

    final_dir = os.path.join(run_dir, "final")
    os.makedirs(final_dir, exist_ok=True)

    run_base = os.path.basename(run_dir)
    manifest = {
        "run_dir": run_base,
        "domain": _best_domain(run_base),
        "lang": _best_lang(run_dir, run_base),
        "artifacts": {
            "audit_report_pdf": os.path.isfile(os.path.join(run_dir, "audit", "report.pdf")),
            "astra_decision_pdf": _has_pdf(os.path.join(run_dir, "astra", "deliverables")),
            "tool2": _has_pdf(os.path.join(run_dir, "action_scope")),
            "tool3": _has_pdf(os.path.join(run_dir, "proof_pack")),
            "tool4": _has_pdf(os.path.join(run_dir, "regression")),
            "master_pdf": os.path.isfile(os.path.join(final_dir, "master.pdf")),
            "bundle_zip": os.path.isfile(os.path.join(final_dir, "client_safe_bundle.zip")),
        },
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "version": "v1",
    }

    out_path = os.path.join(final_dir, "manifest.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, sort_keys=True, separators=(",", ":"))
        f.write("\n")
    print("OK manifest")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
