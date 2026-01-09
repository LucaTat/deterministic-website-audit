# batch.py
import os
import json
import re
import csv
import argparse
import datetime as dt 
import time
import subprocess
import requests
from urllib.parse import urlparse
from datetime import datetime, timezone
from finding_policy import enforce_policy_on_findings
from findings_enricher import enrich_findings
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
from proof_completeness_shadow import write_proof_completeness_shadow

CAMPAIGN = "2025-Q1-outreach"

CRITICAL_FINDING_PREFIXES = ("IDX_",)
CRITICAL_FINDING_IDS = {
    "CONVLOSS_SITE_UNREACHABLE",
}
CRITICAL_SEVERITIES = {"critical", "warning"}

def classify_audit(mode: str, findings: list[dict]) -> tuple[str, str]:
    """
    Returns (audit_type, audit_state)
    """
    if mode in ("broken", "no_website"):
        return ("critical_risk", "critical_failure_detected")

    # mode == ok:
    for f in (findings or []):
        fid = (f.get("id") or "").strip()
        sev = (f.get("severity") or "").strip().lower()
        if fid in CRITICAL_FINDING_IDS:
            return ("critical_risk", "critical_failure_detected")
        if fid.startswith(CRITICAL_FINDING_PREFIXES) and sev in CRITICAL_SEVERITIES:
            return ("critical_risk", "critical_failure_detected")

    return ("opportunity", "no_critical_failures")


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--lang", choices=["en", "ro"], default="en", help="PDF/client narrative language")
    p.add_argument("--campaign", default=CAMPAIGN, help="Campaign folder name under reports/")
    p.add_argument("--targets", default="urls.txt", help="Targets file (default: urls.txt)")
    p.add_argument("--proof-spec", choices=["legacy", "shadow"], default="legacy",
                   help="Proof completeness spec mode (default: legacy)")
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
        secondary_issues = humanize_fetch_error_bullets(reason, lang=lang) if reason else []
        if lang == "ro":
            return {
                "overview": [
                    "Clienții nu pot ajunge constant la site, ceea ce taie din încredere.",
                    "Cereri și programări se pierd în momentul în care pagina nu se deschide."
                ],
                "primary_issue": {"title": "Website inaccesibil", "impact": "Se pierd lead-uri și scade încrederea din Google/Maps."},
                "secondary_issues": secondary_issues[:2],
                "plan": [
                    "Verificați dacă domeniul trimite corect către site și că pagina principală se deschide mereu.",
                    "Corectați orice probleme de acces sau redirecționare care blochează vizitatorii.",
                    "După ce site-ul se deschide constant, actualizați linkurile din profilele publice."
                ],
                "confidence": "Ridicată"
            }
        return {
            "overview": [
                "Customers can’t consistently reach the site, which erodes trust fast.",
                "Inquiries are lost whenever the page fails to open."
            ],
            "primary_issue": {"title": "Website unreachable", "impact": "Lost leads and reduced trust from Google/Maps visitors."},
            "secondary_issues": secondary_issues[:2],
            "plan": [
                "Confirm the domain points correctly and the homepage opens consistently.",
                "Fix any access or redirect issues that block visitors.",
                "Once the site is stable, update public profile links to the working URL."
            ],
            "confidence": "High"
        }

    # ok mode
    return build_client_narrative(signals or {}, lang=lang)


def humanize_fetch_error(reason: str, lang: str = "ro") -> str:
    text = (reason or "").lower()
    is_ro = (lang or "").lower().strip() == "ro"
    if "ssl" in text or "certificate" in text or "cert" in text:
        return "Eroare SSL / certificat invalid." if is_ro else "SSL error / invalid certificate."
    if "dns" in text or "name or service not known" in text or "nodename nor servname" in text:
        return "Eroare DNS (domeniu inexistent sau neconfigurat)." if is_ro else "DNS error (domain missing or misconfigured)."
    if "timeout" in text or "timed out" in text:
        return "Timeout la încărcarea website-ului." if is_ro else "Website load timed out."
    if "connection" in text or "refused" in text:
        return "Conexiunea la website a eșuat." if is_ro else "Connection to the website failed."
    if "404" in text or "not found" in text:
        return "Pagina nu a fost găsită (404)." if is_ro else "Page not found (404)."
    if "5" in text and "http" in text or "server error" in text:
        return "Eroare de server (5xx)." if is_ro else "Server error (5xx)."
    return "Website-ul nu a putut fi accesat." if is_ro else "The website could not be reached."


def humanize_fetch_error_bullets(reason: str, lang: str = "ro") -> list[str]:
    r = (reason or "").lower()

    is_ro = (lang or "").lower().strip() == "ro"

    def ro(cause, action):
        return [f"Cauză probabilă: {cause}", f"Ce să faceți: {action}"]

    def en(cause, action):
        return [f"Likely cause: {cause}", f"What to do: {action}"]

    def out(cause_ro, action_ro, cause_en, action_en):
        return (ro(cause_ro, action_ro) if is_ro else en(cause_en, action_en))[:2]

    if "ssl" in r or "certificate" in r or "cert" in r:
        return out(
            "certificatul SSL nu este configurat corect pentru domeniu (www vs non-www)",
            "reinstalați certificatul și verificați redirecționările către domeniul principal",
            "the SSL certificate is misconfigured for the domain (www vs non-www)",
            "reinstall the certificate and verify redirects to the primary domain",
        )

    if "dns" in r or "name or service not known" in r or "nodename nor servname" in r:
        return out(
            "domeniul nu indică corect către server (DNS greșit sau lipsă)",
            "verificați înregistrările DNS și IP-ul serverului",
            "the domain does not point correctly to the server (DNS issue)",
            "check DNS records and server IP configuration",
        )

    if "timeout" in r or "timed out" in r:
        return out(
            "serverul răspunde foarte lent sau nu răspunde",
            "verificați hostingul și performanța serverului",
            "the server is too slow or not responding",
            "check hosting stability and server performance",
        )

    if "refused" in r or "connection" in r:
        return out(
            "serverul respinge conexiunile externe",
            "verificați firewall-ul și configurația serverului",
            "the server is refusing external connections",
            "check firewall and server configuration",
        )

    if "redirect" in r:
        return out(
            "există o buclă de redirecționare (http/https sau www/non-www)",
            "corectați regulile de redirecționare către un singur URL canonical",
            "there is a redirect loop (http/https or www/non-www)",
            "fix redirects to point to a single canonical URL",
        )

    return out(
        "configurația domeniului sau a serverului împiedică accesarea site-ului",
        "verificați domeniul, hostingul și certificatul SSL",
        "domain or server configuration prevents access",
        "check domain, hosting, and SSL configuration",
    )

def get_tool_version() -> str:
    start_dir = os.path.abspath(os.path.dirname(__file__))
    repo_root = None
    current = start_dir
    for _ in range(6):
        if os.path.isdir(os.path.join(current, ".git")):
            repo_root = current
            break
        parent = os.path.abspath(os.path.join(current, ".."))
        if parent == current:
            break
        current = parent
    if not repo_root:
        return "unknown"
    try:
        result = subprocess.run(
            ["git", "rev-parse", "--short", "HEAD"],
            cwd=repo_root,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=0.3,
            check=False,
        )
        return (result.stdout or "").strip() or "unknown"
    except Exception:
        return "unknown"

def audit_one(url: str, lang: str, business_inputs: dict | None = None) -> dict:
    lang = (lang or "en").lower().strip()
    if lang not in ("en", "ro"):
        lang = "en"
    u = (url or "").strip()
    summary_text = ""

    # No website case
    if u.lower() in ["none", "no", "no website", "n/a", "na", ""]:
        summary_text = human_summary("(no website)", {}, mode="no_website")
        if os.environ.get("AUDIT_DEBUG") == "1":
            print("HUMAN_SUMMARY_PREVIEW:", summary_text[:120])
        conversion_loss = build_conversion_loss(
            mode="no_website", signals={}, business_inputs=business_inputs
        )
        conversion_loss_findings = build_conversion_loss_findings(
            mode="no_website",
            signals={},
            business_inputs=business_inputs,
            lang=lang,
        )

        findings = enforce_policy_on_findings(conversion_loss_findings)

        return {
            "url": "(no website)",
            "mode": "no_website",
            "lang": lang,
            "html": "",
            "signals": {},
            "findings": findings,
            "meta": {"indexability_pack_version": INDEXABILITY_PACK_VERSION},
            "business_inputs": business_inputs or {},
            "conversion_loss": conversion_loss,
            "summary": summary_text,
            "summary_en": summary_text if lang == "en" else "",
            "summary_ro": summary_text if lang == "ro" else summary_text,
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

            "audit_type": "critical_risk",
            "audit_state": "critical_failure_detected",
            "blocks": [
                "organic_search",
                "google_business_profile",
                "direct_and_referral",
                "user_trust_security",
                "all_conversions",
            ],
            "blocked_checks": [
                "indexability_and_crawlability",
                "internal_linking",
                "conversion_paths",
                "contact_and_booking_clarity",
            ],
        }




    try:
        html = fetch_html(u)
        signals = build_all_signals(html, page_url=u)
        idx_signals = extract_indexability_signals(url=u, html=html, signals=signals)
        signals["indexability"] = idx_signals

        # Findings
        findings = (
            build_social_findings(signals, lang=lang)
            + build_share_meta_findings(signals, lang=lang)
            + build_indexability_findings(
                idx_signals,
                important_urls=idx_signals.get("important_urls", []),
                lang=lang,
            )
            + build_conversion_loss_findings(
                mode="ok",
                signals=signals,
                business_inputs=business_inputs,
                lang=lang,
            )
        )

        findings = enforce_policy_on_findings(findings)
        audit_type, audit_state = classify_audit("ok", findings)
        conversion_loss = build_conversion_loss(
            mode="ok", signals=signals, business_inputs=business_inputs
        )

        client_narrative = build_client_narrative(signals, lang=lang)
        insights = user_insights(signals)
        summary_text = human_summary(u, signals, mode="ok")
        if os.environ.get("AUDIT_DEBUG") == "1":
            print("HUMAN_SUMMARY_PREVIEW:", summary_text[:120])

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
            "summary": summary_text,
            "summary_en": summary_text if lang == "en" else "",
            "summary_ro": summary_text if lang == "ro" else summary_text,
            "client_narrative": client_narrative,
            "user_insights_en": insights,
            "audit_type": audit_type,
            "audit_state": audit_state,
            "blocks": [],
            "blocked_checks": [],
        }

    # 🔴 WEBSITE UNREACHABLE (SSL / DNS / timeout / 4xx / 5xx)
    except (
        requests.exceptions.ConnectionError,
        requests.exceptions.SSLError,
        requests.exceptions.Timeout,
        requests.exceptions.HTTPError,
    ) as e:
        reason = str(e)
        summary_text = human_summary(u, {"reason": reason}, mode="broken")
        if os.environ.get("AUDIT_DEBUG") == "1":
            print("HUMAN_SUMMARY_PREVIEW:", summary_text[:120])

        conversion_loss = build_conversion_loss(
            mode="broken", signals={"reason": reason}, business_inputs=business_inputs
        )
        conversion_loss_findings = build_conversion_loss_findings(
            mode="broken",
            signals={"reason": reason},
            business_inputs=business_inputs,
            lang=lang,
        )
        findings = enforce_policy_on_findings(conversion_loss_findings)

        return {
            "url": u,
            "mode": "broken",  # ← unreachable website
            "lang": lang,
            "html": "",
            "signals": {"reason": reason},
            "findings": findings,
            "meta": {"indexability_pack_version": INDEXABILITY_PACK_VERSION},
            "business_inputs": business_inputs or {},
            "conversion_loss": conversion_loss,
            "summary": summary_text,
            "summary_en": summary_text if lang == "en" else "",
            "summary_ro": summary_text if lang == "ro" else summary_text,
            "client_narrative": client_narrative_for_mode("broken", lang, {"reason": reason}),
            "user_insights_en": {
                "primary_issue": "Website unreachable.",
                "secondary_issues": [],
                "confidence": "High",
                "recommended_focus": "Fix hosting/domain/SSL and rerun.",
                "steps": [
                    "Fix DNS/hosting/SSL so the homepage loads consistently.",
                    "Rerun the audit after the fix.",
                ],
            },
            "audit_type": "critical_risk",
            "audit_state": "critical_failure_detected",
            "blocks": [
                "organic_search",
                "google_business_profile",
                "direct_and_referral",
                "user_trust_security",
                "all_conversions",
            ],
            "blocked_checks": [
                "indexability_and_crawlability",
                "internal_linking",
                "conversion_paths",
                "contact_and_booking_clarity",
            ],
        }

    # 🔴 INTERNAL TOOL CRASH (real bug)
    except Exception as e:
        import traceback

        reason = str(e)
        tb = traceback.format_exc()
        summary_text = human_summary(u, {"reason": reason}, mode="broken")
        if os.environ.get("AUDIT_DEBUG") == "1":
            print("HUMAN_SUMMARY_PREVIEW:", summary_text[:120])

        conversion_loss = build_conversion_loss(
            mode="broken", signals={"reason": reason}, business_inputs=business_inputs
        )
        conversion_loss_findings = build_conversion_loss_findings(
            mode="broken",
            signals={"reason": reason},
            business_inputs=business_inputs,
            lang=lang,
        )
        findings = enforce_policy_on_findings(conversion_loss_findings)

        return {
            "url": u,
            "mode": "broken",
            "lang": lang,
            "html": "",
            "signals": {"reason": reason, "traceback": tb},
            "findings": findings,
            "meta": {"indexability_pack_version": INDEXABILITY_PACK_VERSION},
            "business_inputs": business_inputs or {},
            "conversion_loss": conversion_loss,
            "summary": summary_text,
            "summary_en": summary_text if lang == "en" else "",
            "summary_ro": summary_text if lang == "ro" else summary_text,
            "client_narrative": client_narrative_for_mode("broken", lang, {"reason": reason}),
            "user_insights_en": {
                "primary_issue": "Audit crashed internally.",
                "secondary_issues": [],
                "confidence": "High",
                "recommended_focus": "Fix internal error and rerun.",
                "steps": [
                    "Open the saved traceback and fix the crashing line.",
                    "Rerun the audit.",
                ],
            },

            # NEW: audit classification + impact (TOP-LEVEL)
            "audit_type": "critical_risk",
            "audit_state": "critical_failure_detected",
            "blocks": [
                "audit_delivery",
                "audit_coverage",
                "client_reporting",
            ],
            "blocked_checks": [
                "indexability_and_crawlability",
                "internal_linking",
                "conversion_paths",
                "contact_and_booking_clarity",
            ],
        }
    




def save_json(audit_result: dict, out_path: str) -> None:
    if "tool_version" not in audit_result:
        audit_result["tool_version"] = get_tool_version()
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
    proof_spec = args.proof_spec

    business_inputs = {
        "sessions_per_month": args.sessions,
        "conversion_rate": args.conversion_rate,
        "value_per_conversion": args.value,
    }

    reports_root = os.path.join("reports", campaign)
    os.makedirs(reports_root, exist_ok=True)
    csv_path = os.path.join(reports_root, "summary.csv")

    targets = read_targets(targets_path)
    total = len(targets)
    print(f"Deterministic Website Audit (batch) — {total} target(s)")
    if not targets:
        print("Done — 0 OK, 0 BROKEN")
        return

    ok_count = 0
    broken_count = 0
    unknown_count = 0

    tool_version = get_tool_version()
    for i, t in enumerate(targets, start=1):
        client_name = t["client_name"]
        url = t["url"]
        start_time = time.perf_counter()

        result = audit_one(url, lang=lang, business_inputs=business_inputs)
        result["client_name"] = client_name
        result["tool_version"] = tool_version

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

        export_audit_pdf(result, pdf_path, tool_version=tool_version)
        save_json(result, json_path)

        if proof_spec == "shadow":
            shadow_path = os.path.join(out_folder, "proof_completeness_shadow.json")
            write_proof_completeness_shadow(result.get("findings", []), shadow_path)

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

        display = result.get("url", "<unknown>")
        mode = result.get("mode", "unknown")
        missing_target = not (url or "").strip() or display == "(no website)"
        status = "BROKEN" if missing_target else ("OK" if mode == "ok" else ("BROKEN" if mode == "broken" else "UNKNOWN"))
        duration = time.perf_counter() - start_time
        if status == "OK":
            ok_count += 1
        elif status == "BROKEN":
            broken_count += 1
        else:
            unknown_count += 1

        print(f"[{i}/{total}] {display}")
        print(f"  status: {status}")
        print(f"  pdf:   {pdf_path}")
        print(f"  json:  {json_path}")
        evidence_path = os.path.join(out_folder, "evidence")
        if os.path.isdir(evidence_path):
            print(f"  ev:    {evidence_path}")
        print(f"  time:  {duration:.1f}s")

        # If broken mode includes a traceback, write it next to the outputs for debugging.
        tb = ((result.get("signals") or {}).get("traceback"))
        if tb:
            with open(os.path.join(out_folder, "error_traceback.txt"), "w", encoding="utf-8") as f:
               f.write(tb)

    if unknown_count > 0:
        print(f"Done — {ok_count} OK, {broken_count} BROKEN, {unknown_count} UNKNOWN")
    else:
        print(f"Done — {ok_count} OK, {broken_count} BROKEN")



if __name__ == "__main__":
    main()
