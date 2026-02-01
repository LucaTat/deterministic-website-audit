#!/usr/bin/env python3
import sys
import zipfile

TEXT_EXTS = (".json", ".md", ".txt")


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: verify_client_safe_zip.py <zip_path>")
        return 2
    zip_path = sys.argv[1]
    with zipfile.ZipFile(zip_path, "r") as zf:
        names = zf.namelist()
        name_set = set(names)
        has_ro = "deliverables/Decision_Brief_RO.pdf" in name_set
        has_en = "deliverables/Decision_Brief_EN.pdf" in name_set
        if has_ro and has_en:
            print("ERROR multiple Decision_Brief languages")
            return 2
        if not (has_ro or has_en):
            print("ERROR missing Decision_Brief")
            return 2
        lang = "RO" if has_ro else "EN"

        required = {
            "audit/report.pdf",
            f"deliverables/Decision_Brief_{lang}.pdf",
            f"deliverables/Evidence_Appendix_{lang}.pdf",
            "deliverables/verdict.json",
            "final/master.pdf",
        }
        optional = {
            "action_scope/action_scope.pdf",
            "proof_pack/proof_pack.pdf",
            "regression/regression.pdf",
        }
        allowlist = required | optional
        for req in required:
            if req not in name_set:
                print(f"ERROR missing required: {req}")
                return 2
        for name in names:
            if name not in allowlist:
                print(f"ERROR unexpected entry: {name}")
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
            if lower.endswith(TEXT_EXTS):
                try:
                    data = zf.read(name)
                except Exception:
                    print(f"ERROR could not read: {name}")
                    return 2
                try:
                    text = data.decode("utf-8", errors="ignore")
                except Exception:
                    text = ""
                if "/Users/" in text or "/home/" in text:
                    print(f"ERROR leaked path in: {name}")
                    return 2
                if (
                    "scope_repo=" in text
                    or "scope_invoked=" in text
                    or "scope_available=" in text
                    or "scope_evidence_dir" in text
                    or "\"notes\"" in text
                ):
                    print(f"ERROR leaked notes in: {name}")
                    return 2
        print("bad_entries_count=0")
        print("ZIP contents:")
        for name in names:
            print(name)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
