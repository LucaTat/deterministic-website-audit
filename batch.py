# batch.py
import os
import json
import re
import csv
import argparse
import datetime as dt
from urllib.parse import urlparse
from datetime import datetime, timezone

from audit import (
    fetch_html,
    page_signals,
    build_all_signals,
    human_summary,
    save_html_evidence,
    user_insights,
)

from social_findings import build_social_findings
from share_meta_findings import build_share_meta_findings
from conversion_loss_findings import build_conversion_loss, build_conversion_loss_findings
from indexability_signals import extract_indexability_signals, INDEXABILITY_PACK_VERSION
from indexability_findings import build_indexability_findings

from client_narrative import build_client_narrative
from pdf_export import export_audit_pdf
from ai.advisory import build_ai_advisory

CAMPAIGN = "2025-Q1-outreach"


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--lang", choices=["en", "ro"], default="en", help="PDF/client narrative language")
    p.add_argument("--campaign", default=CAMPAIGN, help="Campaign folder name under reports/")
    p.add_argument("--targets", default="urls.txt", help="Targets file (default: urls.txt)")
    # Optional business inputs to translate % impact into absolute estimates.
    # If omitted, the tool will output conservative % ranges only.
    p.add_argument("--sessions", type=float, default=None, help="Optional: monthly sessions (e.g. 3000)")
    p.add_argument("--conversion-rate", type=float, default=None, help="Optional: conversion rate as fraction (e.g. 0.02 for 2%%)")
    p.add_argument("--value", type=float, default=None, help="Optional: value per conversion (lead/order value)")
    return p.parse_args()


def slugify(s: str) -> str:
    s = (s or "").strip().lower()
    s = re.sub(r"\s+", "_", s)
    s = re.sub(r"[^a-z0-9_]+", "_", s)
    s = re.sub(r"_+", "_", s).strip("_")
    return s or "client"


def slug_from_url(url: str) -> str:
    url = url.strip()
    parsed = urlparse(url if "://" in url else "https://" + url)

    host = (parsed.netloc or "").lower()
    path = (parsed.path or "").strip("/").lower()

    host = re.sub(r"^www\.", "", host)
    host = host.replace(".", "_")
    path = re.sub(r"[^a-z0-9/_-]+", "", path).replace("/", "_")

    base = host if host else "site"
    if path:
        base = f"{base}_{path}"

    base = re.sub(r"_+", "_", base).strip("_")
    return base or "audit"


def read_targets(path: str = "urls.txt") -> list[dict]:
    if not os.path.exists(path):
        raise FileNotFoundError(f"Nu găsesc fișierul: {path}")

    targets = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            raw = line.strip()
            if not raw or raw.startswith("#"):
                continue

            if "," in raw:
                name, url = raw.split(",", 1)
                targets.append({"client_name": name.strip(), "url": url.strip()})
            else:
                targets.append({"client_name": "", "url": raw})
    return targets


def client_narrative_for_mode(mode: str, lang: str, signals: dict) -> dict:
    lang = (lang or "en").lower().strip()
    if lang not in ("en", "ro"):
        lang = "en"

    if mode == "no_website":
        if lang == "ro":
            return {
                "overview": [
                    "Nu a fost furnizat un website funcțional pentru acest business.",
                    "Fără website, încrederea scade și se pierd cereri din Google/Maps."
                ],
                "primary_issue": {"title": "Nu există website", "impact": "Clienții nu pot vedea servicii, locație sau cum să vă contacteze."},
                "secondary_issues": [],
                "plan": [
                    "Creați un website simplu (1 pagină) cu servicii, locație, contact și program.",
                    "Adăugați un CTA clar: Sună / Programează-te / Cere ofertă.",
                    "Retestați după ce website-ul este live."
                ],
                "confidence": "Ridicată"
            }
        return {
            "overview": [
                "No working website was provided for this business.",
                "Without a website, trust drops and inquiries are lost from Google/Maps."
            ],
            "primary_issue": {"title": "No website available", "impact": "Customers cannot confirm services, location, or how to contact/book."},
            "secondary_issues": [],
            "plan": [
                "Create a simple one-page website with services, location, contact details, and opening hours.",
                "Add a clear call-to-action (Call / Book / Request a quote).",
                "Retest once the site is live."
            ],
            "confidence": "High"
        }

    if mode == "broken":
        reason = (signals or {}).get("reason", "")
        if lang == "ro":
            return {
                "overview": [
                    "Există un link de website, dar pagina nu a putut fi accesată în mod fiabil.",
                    "Orice vizitator care vede o eroare pleacă imediat."
                ],
                "primary_issue": {"title": "Website inaccesibil", "impact": "Se pierd lead-uri și scade încrederea din Google/Maps."},
                "secondary_issues": [f"Detalii eroare: {reason}"] if reason else [],
                "plan": [
                    "Reparați accesul (domeniu/hosting/SSL) astfel încât homepage-ul să se încarce constant.",
                    "Retestați după fix și apoi îmbunătățiți programarea/contactul.",
                    "Verificați ca Google Business Profile să trimită către URL-ul corect."
                ],
                "confidence": "Ridicată"
            }
        return {
            "overview": [
                "A website link exists but the page could not be accessed reliably.",
                "Any visitor who hits an error is likely to leave immediately."
            ],
            "primary_issue": {"title": "Website unreachable", "impact": "Lost leads and reduced trust from Google/Maps visitors."},
            "secondary_issues": [f"Error details: {reason}"] if reason else [],
            "plan": [
                "Fix hosting/domain/SSL so the homepage loads consistently.",
                "Retest after the fix and then improve booking/contact clarity.",
                "Ensure Google Business Profile points to the working URL."
            ],
            "confidence": "High"
        }

    # ok mode
    return build_client_narrative(signals or {}, lang=lang)


def audit_one(url: str, lang: str, business_inputs: dict | None = None) -> dict:
    u = (url or "").strip()

    # No website case
    if u.lower() in ["none", "no", "no website", "n/a", "na", ""]:
        summary = human_summary("(no website)", {}, mode="no_website")
        conversion_loss = build_conversion_loss(mode="no_website", signals={}, business_inputs=business_inputs)
        conversion_loss_findings = build_conversion_loss_findings(mode="no_website", signals={}, business_inputs=business_inputs)
        return {
            "url": "(no website)",
            "mode": "no_website",
            "lang": lang,
            "html": "",
            "signals": {},
            "findings": conversion_loss_findings,
            "meta": {"indexability_pack_version": INDEXABILITY_PACK_VERSION},
            "business_inputs": business_inputs or {},
            "conversion_loss": conversion_loss,
            "summary_ro": summary,
            "client_narrative": client_narrative_for_mode("no_website", lang, {}),
            "user_insights_en": {
                "primary_issue": "No website is available to audit.",
                "secondary_issues": [],
                "confidence": "High",
                "recommended_focus": "Create a simple one-page site with clear services, contact, and a call-to-action.",
                "steps": [
                    "Create a basic one-page website with services + location + contact.",
                    "Add a clear call-to-action (Call / Book / Request info).",
                    "Retest once the site is live.",
                ],
            },
        }

    try:
        html = fetch_html(u)
        signals = build_all_signals(html, page_url=u)
        idx_signals = extract_indexability_signals(url=u, html=html, signals=signals)
        signals["indexability"] = idx_signals

        # Findings
        findings = (
            build_social_findings(signals)
            + build_share_meta_findings(signals)
            + build_indexability_findings(idx_signals, important_urls=idx_signals.get("important_urls", []))
            + build_conversion_loss_findings(mode="ok", signals=signals, business_inputs=business_inputs)
        )

        conversion_loss = build_conversion_loss(mode="ok", signals=signals, business_inputs=business_inputs)

        client_narrative = build_client_narrative(signals, lang=lang)
        insights = user_insights(signals)
        summary = human_summary(u, signals, mode="ok")

        return {
            "url": u,
            "mode": "ok",
            "lang": lang,
            "html": html,
            "signals": signals,
            "findings": findings,
            "meta": {"indexability_pack_version": INDEXABILITY_PACK_VERSION},
            "business_inputs": business_inputs or {},
            "conversion_loss": conversion_loss,
            "summary_ro": summary,
            "client_narrative": client_narrative,
            "user_insights_en": insights,
        }

    except Exception as e:
        reason = str(e)
        summary = human_summary(u, {"reason": reason}, mode="broken")

        conversion_loss = build_conversion_loss(mode="broken", signals={"reason": reason}, business_inputs=business_inputs)
        conversion_loss_findings = build_conversion_loss_findings(mode="broken", signals={"reason": reason}, business_inputs=business_inputs)

        return {
            "url": u,
            "mode": "broken",
            "lang": lang,
            "html": "",
            "signals": {"reason": reason},
            "findings": conversion_loss_findings,
            "meta": {"indexability_pack_version": INDEXABILITY_PACK_VERSION},
            "business_inputs": business_inputs or {},
            "conversion_loss": conversion_loss,
            "summary_ro": summary,
            "client_narrative": client_narrative_for_mode("broken", lang, {"reason": reason}),
            "user_insights_en": {
                "primary_issue": "The website is unreachable or broken.",
                "secondary_issues": [],
                "confidence": "High",
                "recommended_focus": "Fix access first (domain/hosting/SSL), then retest.",
                "steps": [
                    "Check domain + hosting availability (site must load reliably).",
                    "Fix SSL/HTTPS issues if present.",
                    "Retest the homepage once the site loads normally.",
                ],
            },
        }


def save_json(audit_result: dict, out_path: str) -> None:
    payload = {
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        **audit_result,
    }
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def append_csv_row(path: str, row: dict) -> None:
    file_exists = os.path.exists(path)
    with open(path, "a", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "client_name",
                "url",
                "mode",
                "score",
                "booking",
                "contact",
                "services",
                "pricing",
                "lang",
            ],
        )
        if not file_exists:
            writer.writeheader()
        writer.writerow(row)


def main():
    args = parse_args()
    lang = args.lang
    campaign = args.campaign
    targets_path = args.targets

    business_inputs = {
        "sessions_per_month": args.sessions,
        "conversion_rate": args.conversion_rate,
        "value_per_conversion": args.value,
    }

    reports_root = os.path.join("reports", campaign)
    os.makedirs(reports_root, exist_ok=True)
    csv_path = os.path.join(reports_root, "summary.csv")

    targets = read_targets(targets_path)
    print(f"[INFO] Targets found: {len(targets)} | lang={lang} | campaign={campaign}")
    if not targets:
        return

    for i, t in enumerate(targets, start=1):
        client_name = t["client_name"]
        url = t["url"]

        result = audit_one(url, lang=lang, business_inputs=business_inputs)
        result["client_name"] = client_name

        ai_advisory = build_ai_advisory(result)
        if ai_advisory:
            result["ai_advisory"] = ai_advisory

        base = slugify(client_name) if client_name else slug_from_url(result["url"])
        client_folder = os.path.join(reports_root, base)
        run_folder = dt.datetime.now().strftime("%Y-%m-%d")
        out_folder = os.path.join(client_folder, run_folder)
        os.makedirs(out_folder, exist_ok=True)

        # SAVE EVIDENCE
        if result.get("mode") == "ok":
            evidence_dir = os.path.join(out_folder, "evidence")
            save_html_evidence(result.get("html", ""), evidence_dir, "home.html")

        pdf_path = os.path.join(out_folder, "audit.pdf")
        json_path = os.path.join(out_folder, "audit.json")

        export_audit_pdf(result, pdf_path)
        save_json(result, json_path)

        signals = result.get("signals", {}) or {}
        append_csv_row(csv_path, {
            "client_name": client_name,
            "url": result["url"],
            "mode": result["mode"],
            "score": signals.get("score", 0) if result["mode"] == "ok" else 0,
            "booking": "yes" if signals.get("booking_detected") else "no",
            "contact": "yes" if signals.get("contact_detected") else "no",
            "services": "yes" if signals.get("services_keywords_detected") else "no",
            "pricing": "yes" if signals.get("pricing_keywords_detected") else "no",
            "lang": lang,
        })

        print(f"[OK] {base} → {out_folder}")


if __name__ == "__main__":
    main()
