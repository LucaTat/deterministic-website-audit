# acceptance_indexability.py
from __future__ import annotations

from collections import Counter

from batch import audit_one, read_targets


def main() -> None:
    targets = read_targets("urls.txt")
    if not targets:
        raise SystemExit("No targets found in urls.txt")

    severity_counts = Counter()
    id_counts = Counter()

    for t in targets[:3]:
        url = (t.get("url") or "").strip()
        if not url:
            print("[WARN] Skipping target with empty url")
            continue

        result = audit_one(url, lang="en", business_inputs={})

        # Hard invariants: pack present + version correct
        idx = result.get("signals", {}).get("indexability", {}) or {}
        assert idx.get("pack_version") == "v1", (
            f"Missing/incorrect indexability pack_version for {url}: {idx.get('pack_version')}"
        )

        # Only evaluate findings when mode is ok (consistent with your overall tool semantics)
        if result.get("mode") != "ok":
            print(f"[WARN] {url}: mode={result.get('mode')} (skipping indexability findings checks)")
            continue

        idx_findings = [
            f for f in (result.get("findings", []) or [])
            if f.get("category") == "indexability_technical_access"
        ]

        # Validate category correctness if any exist; do NOT require at least one finding
        if not idx_findings:
            print(f"[WARN] {url}: 0 indexability findings (can be OK if no issues were detected)")
            continue

        print(f"[OK] {url}: {len(idx_findings)} indexability findings")

        for f in idx_findings:
            # Schema invariants
            assert "id" in f and f["id"], f"Missing finding id for {url}"
            assert f.get("category") == "indexability_technical_access", f"Wrong category for {url}: {f.get('category')}"
            assert "severity" in f and f["severity"], f"Missing severity for {url}"
            assert isinstance(f.get("evidence"), dict), f"Evidence must be a single object dict for {url}, id={f.get('id')}"

            severity_counts[f.get("severity")] += 1
            id_counts[f.get("id")] += 1

    print("Indexability findings by severity:")
    for sev, count in severity_counts.items():
        print(f"  {sev}: {count}")

    print("Indexability findings by ID:")
    for fid, count in id_counts.items():
        print(f"  {fid}: {count}")


if __name__ == "__main__":
    main()
