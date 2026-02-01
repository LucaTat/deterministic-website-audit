#!/usr/bin/env python3
import sys
import zipfile

REQUIRED = {
    "audit/report.pdf",
    "final/master.pdf",
}


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: verify_client_safe_zip.py <zip_path>")
        return 2
    zip_path = sys.argv[1]
    with zipfile.ZipFile(zip_path, "r") as zf:
        names = zf.namelist()
        name_set = set(names)
        for req in REQUIRED:
            if req not in name_set:
                print(f"ERROR missing required: {req}")
                return 2
        for name in names:
            lower = name.lower()
            if name.startswith("__MACOSX/"):
                print(f"ERROR banned entry: {name}")
                return 2
            if "/._" in name or name.startswith("._"):
                print(f"ERROR banned entry: {name}")
                return 2
            if name.endswith(".DS_Store"):
                print(f"ERROR banned entry: {name}")
                return 2
            if lower.endswith(".log"):
                print(f"ERROR banned entry: {name}")
                return 2
            if "/__pycache__/" in name:
                print(f"ERROR banned entry: {name}")
                return 2
            if lower.endswith(".pyc"):
                print(f"ERROR banned entry: {name}")
                return 2
            if "/.venv/" in name or "/venv/" in name or "/node_modules/" in name:
                print(f"ERROR banned entry: {name}")
                return 2
        print("bad_entries_count=0")
        print("ZIP contents:")
        for name in names:
            print(name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
