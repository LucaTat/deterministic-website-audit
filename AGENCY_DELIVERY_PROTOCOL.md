# SCOPE — Agency Delivery Protocol (v1)

## Purpose
SCOPE is a deterministic, evidence-first audit engine used as a **pre-ads / pre-tracking risk gate**.
All outputs are client-safe and reproducible.

This document defines the **only valid delivery artifacts** agencies receive.

---

## Canonical Artifacts (Only These Are Sent)

For each audit run, agencies receive:

1) `final/master.pdf`  
2) `final/client_safe_bundle.zip`

No other files are sent.

---

## Operator Command (Single Source of Truth)

From the SCOPE repo:

```bash
bash scripts/run_paid_audit.sh "<RUN_DIR>"
