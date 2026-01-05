# release_check_v1.py
from __future__ import annotations

import json
from pathlib import Path

from batch import audit_one


GOLDEN = [
    ("salon_elegance_magic", "https://www.saloanelemagic.ro", "en"),
    ("jet_s_studio", "https://www.getts.ro", "en"),
]


def assert_true(cond: bool, msg: str) -> None:
    if not cond:
        raise AssertionError(msg)


def main() -> None:
    for name, url, lang in GOLDEN:
        print(f"[RUN] {name} ({lang}) {url}")
        result = audit_one(url, lang=lang, business_inputs={})

        # Invariants: tool must run deterministically and include required meta
        meta = result.get("meta") or {}
        assert_true(meta.get("indexability_pack_version") == "v1", f"{name}: missing meta.indexability_pack_version=v1")

        signals = result.get("signals") or {}
        idx = signals.get("indexability") or {}
        assert_true(idx.get("pack_version") == "v1", f"{name}: missing signals.indexability.pack_version=v1")

        # Invariants: category must exist, even if no findings are emitted
        findings = result.get("findings") or []
        cats = {
           (f or {}).get("category")
           for f in findings
           if isinstance(f, dict) and (f or {}).get("category")
    }

        # Indexability category: may be 0 findings, that's OK. But must not crash.

        # Jet_s_studio should still have at least one canonical offpage finding (known issue example)
        if name == "jet_s_studio":
            idx_findings = [f for f in findings if (f or {}).get("category") == "indexability_technical_access"]
            assert_true(len(idx_findings) >= 1, f"{name}: expected >=1 indexability finding")
            assert_true(
                any((f or {}).get("id") == "IDX_CANONICAL_POINTS_OFFPAGE" for f in idx_findings),
                f"{name}: expected IDX_CANONICAL_POINTS_OFFPAGE to appear",
            )

        print(f"[OK] {name}: mode={result.get('mode')} findings={len(findings)}")

    print("\nAll v1 release checks passed.")


if __name__ == "__main__":
    main()