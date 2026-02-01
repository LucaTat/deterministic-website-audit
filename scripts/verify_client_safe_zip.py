#!/usr/bin/env python3
import sys
import zipfile

BAD_SUBSTRINGS = [
    "pipeline.log",
    "version.json",
    ".DS_Store",
    "__MACOSX",
]


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: verify_client_safe_zip.py <zip_path>")
        return 2
    zip_path = sys.argv[1]
    with zipfile.ZipFile(zip_path, "r") as zf:
        names = zf.namelist()
        for name in names:
            lower = name.lower()
            if lower.endswith(".log"):
                print(f"FAIL: found log file in zip: {name}")
                return 2
            if "pipeline.log" in lower:
                print(f"FAIL: found pipeline.log in zip: {name}")
                return 2
            if "version.json" in lower:
                print(f"FAIL: found version.json in zip: {name}")
                return 2
            if name.endswith(".run_state.json"):
                print(f"FAIL: found .run_state.json in zip: {name}")
                return 2
            for bad in BAD_SUBSTRINGS:
                if bad.lower() in lower:
                    print(f"FAIL: found banned entry in zip: {name}")
                    return 2
        print("ZIP contents:")
        for name in names:
            print(name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
