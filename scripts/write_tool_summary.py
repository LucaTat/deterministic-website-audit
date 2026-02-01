#!/usr/bin/env python3
import json
import os
import sys
from datetime import datetime, timezone


TOOL_BY_FOLDER = {
    "action_scope": "tool2",
    "proof_pack": "tool3",
    "regression": "tool4",
}


def main() -> int:
    if len(sys.argv) != 4:
        print("ERROR usage: write_tool_summary.py <RUN_DIR> <tool_folder> <pdf_rel_path>")
        return 2
    run_dir = os.path.abspath(sys.argv[1])
    folder = sys.argv[2].strip()
    pdf_rel = sys.argv[3].strip().lstrip("/").replace("\\", "/")

    if folder not in TOOL_BY_FOLDER:
        print("ERROR invalid tool folder")
        return 2
    tool_dir = os.path.join(run_dir, folder)
    if not os.path.isdir(tool_dir):
        print("ERROR tool folder missing")
        return 2
    pdf_path = os.path.join(run_dir, pdf_rel)
    if not os.path.isfile(pdf_path):
        print("ERROR pdf missing")
        return 2

    summary = {
        "artifacts": {"pdf": pdf_rel},
        "folder": folder,
        "generated_utc": datetime.now(timezone.utc).isoformat(),
        "tool": TOOL_BY_FOLDER[folder],
    }
    out_path = os.path.join(tool_dir, "summary.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, sort_keys=True, indent=2)
        f.write("\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
