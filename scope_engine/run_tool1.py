from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

from audit import save_html_evidence
from batch import _build_evidence_pack, _capture_visual_evidence, audit_one, get_tool_version, save_json
from net_guardrails import DEFAULT_HEADERS, DEFAULT_TIMEOUT, MAX_HTML_BYTES, MAX_REDIRECTS, read_limited_text
from pdf_export import export_audit_pdf
from safe_fetch import safe_session


def _normalize_host(value: str) -> str:
    host = value.lower().strip()
    if host.startswith("www."):
        host = host[4:]
    return host.strip(".")


def _host_from_url(url: str) -> str:
    parsed = urlparse(url)
    host = parsed.netloc or parsed.path.split("/")[0]
    return host.split(":")[0].strip()


def _fail(code: int, message: str) -> int:
    print(message)
    return code


def _fetch_home(url: str) -> tuple[str, str, int]:
    session = safe_session()
    session.max_redirects = MAX_REDIRECTS
    resp = session.get(url, headers=DEFAULT_HEADERS, timeout=DEFAULT_TIMEOUT, stream=True)
    text, _ = read_limited_text(resp, MAX_HTML_BYTES)
    final_url = resp.url or url
    status = int(resp.status_code)
    return text or "", final_url, status


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run SCOPE tool1 into a canonical run dir.")
    parser.add_argument("--url", required=True)
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--lang", default="RO")
    parser.add_argument("--max-pages", type=int, default=15)
    args = parser.parse_args(argv)

    url = (args.url or "").strip()
    if not url:
        return _fail(2, "FATAL: missing URL")

    run_dir = Path(args.run_dir).expanduser().resolve()
    if not run_dir.is_absolute():
        return _fail(2, "FATAL: run dir must be absolute")
    run_dir.mkdir(parents=True, exist_ok=True)

    lang = str(args.lang or "RO").strip().upper()
    if lang not in {"RO", "EN"}:
        lang = "RO"
    max_pages = int(args.max_pages or 15)
    if max_pages <= 0:
        max_pages = 15

    # Pre-fetch homepage for identity invariants.
    try:
        html, final_url, status_code = _fetch_home(url)
    except Exception:
        return _fail(2, "FATAL: fetch failed")

    requested_host = _host_from_url(url)
    final_host = _host_from_url(final_url)
    if not requested_host or not final_host:
        return _fail(22, "FATAL: redirect mismatch")
    if _normalize_host(requested_host) != _normalize_host(final_host):
        return _fail(22, "FATAL: redirect mismatch")

    lowered_url = url.lower()
    if "example.invalid" in lowered_url:
        return _fail(23, "FATAL: example domain detected")
    if "example domain" in html.lower():
        return _fail(23, "FATAL: example domain detected")

    if len(html) < 5000:
        return _fail(24, "FATAL: evidence too small")

    # Evidence folder
    scope_dir = run_dir / "scope" / "evidence"
    scope_dir.mkdir(parents=True, exist_ok=True)
    save_html_evidence(html, str(scope_dir), "home.html")
    pages_path = scope_dir / "pages.json"
    pages_path.write_text(json.dumps([{"url": final_url, "file": "home.html"}], indent=2) + "\n", encoding="utf-8")
    meta_path = scope_dir / "meta.json"
    meta_path.write_text(
        json.dumps(
            {
                "requested_url": url,
                "final_url": final_url,
                "status_code": status_code,
                "html_bytes": len(html),
                "timestamp_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    _capture_visual_evidence(final_url, str(scope_dir))

    # Run deterministic audit (Tool 1) into run_dir/audit
    result = audit_one(url, lang.lower())
    result["url_input"] = url
    result["final_url"] = final_url
    result["tool_version"] = get_tool_version()

    audit_dir = run_dir / "audit"
    audit_dir.mkdir(parents=True, exist_ok=True)
    report_json = audit_dir / "report.json"
    report_pdf = audit_dir / "report.pdf"

    save_json(result, str(report_json))
    export_audit_pdf(result, str(report_pdf), tool_version=result["tool_version"])

    evidence_pack = _build_evidence_pack(result.get("crawl_v1") or {}, result.get("evidence_pack"))
    crawl_pages = evidence_pack.get("crawl_pages")
    if isinstance(crawl_pages, list) and len(crawl_pages) > max_pages:
        evidence_pack["crawl_pages"] = crawl_pages[:max_pages]
    evidence_pack_path = scope_dir / "evidence_pack.json"
    evidence_pack_path.write_text(json.dumps(evidence_pack, indent=2) + "\n", encoding="utf-8")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
