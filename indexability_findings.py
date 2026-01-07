# indexability_findings.py
from __future__ import annotations

from typing import Any
from urllib.parse import urlparse


CATEGORY = "indexability_technical_access"


def build_indexability_findings(idx_signals: dict[str, Any], important_urls: list[str]) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []
    important_set = set(important_urls or [])

    groups = idx_signals.get("important_url_groups") or {}
    primary_urls = set()
    for key in ("homepage", "booking", "contact"):
        if isinstance(groups.get(key), list) and groups[key]:
            primary_urls.add(groups[key][0])
    for url in groups.get("services") or []:
        primary_urls.add(url)

    # -------------------------
    # Robots findings (site)
    # -------------------------
    robots = idx_signals.get("robots") or {}
    robots_url = robots.get("url")
    robots_status = robots.get("http_status")
    robots_error = robots.get("error")
    robots_snippet_800 = robots.get("body_snippet") or ""
    robots_snippet_500 = robots_snippet_800[:500] if robots_snippet_800 else ""

    # Unreachable: error OR non-404 4xx/5xx
    if robots_error or (robots_status is not None and int(robots_status) >= 400 and int(robots_status) != 404):
        findings.append({
            "id": "IDX_ROBOTS_UNREACHABLE",
            "category": CATEGORY,
            "severity": "fail",
            "title_en": "robots.txt is unreachable",
            "title_ro": "robots.txt nu este accesibil",
            "description_en": "We could not retrieve robots.txt, so crawl directives for search engines cannot be confirmed.",
            "description_ro": "Nu am putut prelua robots.txt, astfel că directivele de crawl pentru motoarele de căutare nu pot fi confirmate.",
            "recommendation_en": "Ensure /robots.txt is accessible and returns HTTP 200.",
            "recommendation_ro": "Asigurați accesibilitatea fișierului /robots.txt (HTTP 200).",
            "evidence": {
                "type": "robots_txt",
                "url": robots_url,
                "http_status": robots_status,
                "error": robots_error,
                "snippet": robots_snippet_500,
            },
        })

    # Missing: 404
    if robots_status == 404:
        findings.append({
            "id": "IDX_ROBOTS_MISSING",
            "category": CATEGORY,
            "severity": "info",
            "title_en": "robots.txt is missing",
            "title_ro": "robots.txt lipsește",
            "description_en": "The site does not expose a robots.txt file.",
            "description_ro": "Site-ul nu expune un fișier robots.txt.",
            "recommendation_en": "Add a simple robots.txt to document crawl rules and sitemap location.",
            "recommendation_ro": "Adăugați un robots.txt simplu pentru a documenta regulile de crawl și locația sitemap-ului.",
            "evidence": {
                "type": "robots_txt",
                "url": robots_url,
                "http_status": robots_status,
                "snippet": "",
            },
        })

    # Broad disallow: Disallow: / for * or googlebot
    ua_rules = robots.get("ua_rules") or {}
    broad_block_uas = [ua for ua in ("*", "googlebot") if "/" in (ua_rules.get(ua) or [])]
    if broad_block_uas:
        findings.append({
            "id": "IDX_ROBOTS_HAS_BROAD_DISALLOW",
            "category": CATEGORY,
            "severity": "fail",
            "title_en": "robots.txt blocks all paths for a crawler",
            "title_ro": "robots.txt blochează toate rutele pentru un crawler",
            "description_en": "robots.txt includes a Disallow: / rule for a major user agent, which blocks crawling of the entire site.",
            "description_ro": "robots.txt include o regulă Disallow: / pentru un user agent major, ceea ce blochează crawl-ul întregului site.",
            "recommendation_en": "Remove or narrow the Disallow: / rule unless the site should be fully blocked.",
            "recommendation_ro": "Eliminați sau restrângeți regula Disallow: / dacă site-ul nu trebuie blocat complet.",
            "evidence": {
                "type": "robots_txt",
                "url": robots_url,
                "http_status": robots_status,
                "snippet": robots_snippet_800,
                "parsed_summary": {ua: ua_rules.get(ua, []) for ua in broad_block_uas},
                "robots_block_match": {"ua": broad_block_uas[0], "rule": "/"},
            },
        })

    # Blocks important pages
    blocked = _blocked_important_urls(important_urls, ua_rules)
    if blocked:
        severity = "fail" if any(b["url"] in primary_urls for b in blocked) else "warning"
        findings.append({
            "id": "IDX_ROBOTS_BLOCKS_IMPORTANT_PAGES",
            "category": CATEGORY,
            "severity": severity,
            "title_en": "robots.txt blocks important pages",
            "title_ro": "robots.txt blochează pagini importante",
            "description_en": "robots.txt disallows crawling of one or more important pages.",
            "description_ro": "robots.txt interzice crawl-ul pentru una sau mai multe pagini importante.",
            "recommendation_en": "Allow crawling for the listed pages if they should be indexed.",
            "recommendation_ro": "Permiteți crawl-ul pentru paginile listate dacă trebuie indexate.",
            "evidence": {
                "type": "robots_block_match",
                "robots_url": robots_url,
                "robots_http_status": robots_status,
                "blocked": blocked,
                "robots_snippet": robots_snippet_800,
            },
        })

    # -------------------------
    # Page-level findings
    # -------------------------
    pages = idx_signals.get("pages") or {}
    offpage_groups: dict[str, dict[str, Any]] = {}

    for page_url, page in pages.items():
        fetch = page.get("fetch") or {}
        final_url = fetch.get("final_url") or page_url
        final_status = fetch.get("final_status")
        redirect_chain = fetch.get("redirect_chain") or []
        loop = bool(fetch.get("loop"))
        too_many = bool(fetch.get("too_many"))
        important = page_url in important_set

        # Noindex (meta)
        meta = page.get("meta") or {}
        robots_meta = meta.get("robots") or []
        googlebot_meta = meta.get("googlebot") or []
        noindex_meta_tag = _first_noindex_meta(robots_meta, googlebot_meta)
        if noindex_meta_tag:
            findings.append({
                "id": "IDX_NOINDEX_META_PRESENT",
                "category": CATEGORY,
                "severity": "fail" if important else "warning",
                "title_en": "Noindex meta tag present",
                "title_ro": "Tag meta noindex prezent",
                "description_en": "A meta robots directive includes noindex on this page.",
                "description_ro": "Un tag meta robots include noindex pe această pagină.",
                "recommendation_en": "Remove noindex if this page should appear in search results.",
                "recommendation_ro": "Eliminați noindex dacă această pagină trebuie să apară în rezultatele de căutare.",
                "evidence": {
                    "type": "html_tag",
                    "url": page_url,
                    "final_url": final_url,
                    "http_status": final_status,
                    "snippet": noindex_meta_tag.get("snippet"),
                    "attrs": noindex_meta_tag.get("attrs"),
                },
            })

        # Noindex (header)
        headers = page.get("headers") or {}
        x_robots = (headers.get("x-robots-tag") or "").lower()
        if _has_token(x_robots, "noindex"):
            findings.append({
                "id": "IDX_NOINDEX_HEADER_PRESENT",
                "category": CATEGORY,
                "severity": "fail" if important else "warning",
                "title_en": "X-Robots-Tag header sets noindex",
                "title_ro": "Headerul X-Robots-Tag setează noindex",
                "description_en": "The response header includes a noindex directive.",
                "description_ro": "Headerul de răspuns include o directivă noindex.",
                "recommendation_en": "Remove noindex from X-Robots-Tag if this page should be indexed.",
                "recommendation_ro": "Eliminați noindex din X-Robots-Tag dacă pagina trebuie indexată.",
                "evidence": {
                    "type": "response_headers",
                    "url": page_url,
                    "final_url": final_url,
                    "http_status": final_status,
                    "headers_subset": {"x-robots-tag": headers.get("x-robots-tag", "")},
                },
            })

        # Conflicting directives (explicit index + noindex)
        conflict = _has_conflicting_directives(robots_meta, googlebot_meta, x_robots)
        if conflict:
            findings.append({
                "id": "IDX_NOINDEX_CONFLICTING_DIRECTIVES",
                "category": CATEGORY,
                "severity": "warning",
                "title_en": "Conflicting index directives detected",
                "title_ro": "Directive de indexare în conflict",
                "description_en": "The page includes both index and noindex directives across meta tags or headers.",
                "description_ro": "Pagina include directive index și noindex în meta tag-uri sau headere.",
                "recommendation_en": "Keep a single, consistent directive (index or noindex).",
                "recommendation_ro": "Păstrați o singură directivă consecventă (index sau noindex).",
                "evidence": {
                    "type": "html_tag",
                    "url": page_url,
                    "final_url": final_url,
                    "http_status": final_status,
                    "meta_robots": robots_meta,
                    "meta_googlebot": googlebot_meta,
                    "x_robots_tag": headers.get("x-robots-tag", ""),
                },
            })

        # Canonical checks
        canonical = page.get("canonical") or {}
        canon_count = int(canonical.get("found_count", 0) or 0)

        if canon_count == 0:
            findings.append({
                "id": "IDX_CANONICAL_MISSING",
                "category": CATEGORY,
                "severity": "warning" if important else "info",
                "title_en": "Canonical tag is missing",
                "title_ro": "Tag-ul canonical lipsește",
                "description_en": "No canonical tag was found on this page.",
                "description_ro": "Nu a fost găsit un tag canonical pe această pagină.",
                "recommendation_en": "Add a canonical tag pointing to the preferred URL for this page.",
                "recommendation_ro": "Adăugați un tag canonical către URL-ul preferat al paginii.",
                "evidence": {
                    "type": "html_tag",
                    "url": page_url,
                    "final_url": final_url,
                    "http_status": final_status,
                    "found_count": 0,
                },
            })

        if canon_count > 1:
            findings.append({
                "id": "IDX_CANONICAL_MULTIPLE",
                "category": CATEGORY,
                "severity": "warning",
                "title_en": "Multiple canonical tags detected",
                "title_ro": "Mai multe tag-uri canonical detectate",
                "description_en": "More than one canonical tag was found on this page.",
                "description_ro": "A fost găsit mai mult de un tag canonical pe această pagină.",
                "recommendation_en": "Keep a single canonical tag to avoid ambiguity.",
                "recommendation_ro": "Păstrați un singur tag canonical pentru a evita ambiguitatea.",
                "evidence": {
                    "type": "html_tag",
                    "url": page_url,
                    "final_url": final_url,
                    "http_status": final_status,
                    "canonicals": canonical.get("tags") or [],
                },
            })

        canon_href = canonical.get("href") or ""
        canon_resolved = canonical.get("resolved") or ""

        if canon_href and canon_resolved:
            offpage = _canonical_points_offpage(final_url, canon_resolved)
            entry = None
            if offpage:
                key = canon_resolved  # consolidate by resolved canonical
                tag_snippet = (canonical.get("tags") or [{}])[0].get("snippet", "")
                entry = offpage_groups.setdefault(key, {
                    "canonical_href": canon_href,
                    "canonical_resolved": canon_resolved,
                    "affected_pages": [],
                    "target_fetches": [],
                })
                entry["affected_pages"].append({
                    "url": page_url,
                    "final_url": final_url,
                    "http_status": final_status,
                    "snippet": tag_snippet,
                })

            # Canonical target non-200 (only if actually fetched)
            target_fetch = canonical.get("target_fetch") or None
            if isinstance(target_fetch, dict) and target_fetch:
                if offpage and entry is not None:
                    entry["target_fetches"].append(target_fetch)
                target_status = target_fetch.get("final_status")
                if target_status is not None and int(target_status) != 200:
                    findings.append({
                        "id": "IDX_CANONICAL_NON_200_TARGET",
                        "category": CATEGORY,
                        "severity": "fail",
                        "title_en": "Canonical target is not reachable (non-200)",
                        "title_ro": "Ținta canonical nu este accesibilă (non-200)",
                        "description_en": "The canonical URL does not return HTTP 200.",
                        "description_ro": "URL-ul canonical nu returnează HTTP 200.",
                        "recommendation_en": "Fix the canonical target to return HTTP 200.",
                        "recommendation_ro": "Corectați ținta canonical astfel încât să returneze HTTP 200.",
                        "evidence": _chain_evidence(target_fetch, canon_resolved or canon_href),
                    })
                elif target_fetch.get("error"):
                    findings.append({
                        "id": "IDX_CANONICAL_NON_200_TARGET",
                        "category": CATEGORY,
                        "severity": "fail",
                        "title_en": "Canonical target is unreachable",
                        "title_ro": "Ținta canonical nu este accesibilă",
                        "description_en": "The canonical URL could not be reached.",
                        "description_ro": "URL-ul canonical nu a putut fi accesat.",
                        "recommendation_en": "Ensure the canonical target is reachable and returns HTTP 200.",
                        "recommendation_ro": "Asigurați-vă că ținta canonical este accesibilă și returnează HTTP 200.",
                        "evidence": _chain_evidence(target_fetch, canon_resolved or canon_href),
                    })

        # Status codes
        if final_status is not None and 400 <= int(final_status) < 500:
            findings.append({
                "id": "IDX_PAGE_STATUS_4XX",
                "category": CATEGORY,
                "severity": "fail" if important else "warning",
                "title_en": "Page returns a 4xx status code",
                "title_ro": "Pagina returnează un cod 4xx",
                "description_en": "This page returns a client error response.",
                "description_ro": "Această pagină returnează o eroare de tip client.",
                "recommendation_en": "Fix the URL or restore the page so it returns HTTP 200.",
                "recommendation_ro": "Corectați URL-ul sau restaurați pagina pentru a returna HTTP 200.",
                "evidence": _chain_evidence(fetch, page_url),
            })

        if final_status is not None and 500 <= int(final_status) < 600:
            findings.append({
                "id": "IDX_PAGE_STATUS_5XX",
                "category": CATEGORY,
                "severity": "fail",
                "title_en": "Page returns a 5xx status code",
                "title_ro": "Pagina returnează un cod 5xx",
                "description_en": "This page returns a server error response.",
                "description_ro": "Această pagină returnează o eroare de tip server.",
                "recommendation_en": "Fix the server error and ensure the page returns HTTP 200.",
                "recommendation_ro": "Remediați eroarea de server și asigurați returnarea HTTP 200.",
                "evidence": _chain_evidence(fetch, page_url),
            })

        # Redirect chain
        if len(redirect_chain) >= 2:
            severity = "fail" if len(redirect_chain) > 3 or important else "warning"
            findings.append({
                "id": "IDX_REDIRECT_CHAIN",
                "category": CATEGORY,
                "severity": severity,
                "title_en": "Redirect chain detected",
                "title_ro": "Lanț de redirect detectat",
                "description_en": "This URL redirects multiple times before reaching the final page.",
                "description_ro": "Acest URL redirecționează de mai multe ori până la pagina finală.",
                "recommendation_en": "Reduce redirect hops to improve crawl efficiency and consistency.",
                "recommendation_ro": "Reduceți numărul de redirect-uri pentru eficiență și consistență.",
                "evidence": _chain_evidence(fetch, page_url),
            })

        if loop or too_many:
            reason = "loop" if loop else "too_many_redirects"
            findings.append({
                "id": "IDX_REDIRECT_LOOP_OR_TOO_MANY",
                "category": CATEGORY,
                "severity": "fail",
                "title_en": "Redirect loop or too many redirects",
                "title_ro": "Buclă de redirect sau prea multe redirect-uri",
                "description_en": "The URL could not be resolved due to a redirect loop or too many hops.",
                "description_ro": "URL-ul nu a putut fi rezolvat din cauza unei bucle de redirect sau a prea multor pași.",
                "recommendation_en": "Fix the redirect rules so the URL resolves to a single final page.",
                "recommendation_ro": "Corectați regulile de redirect pentru a ajunge la o singură pagină finală.",
                "evidence": {
                    **_chain_evidence(fetch, page_url),
                    "reason": reason,
                },
            })

    # Consolidated canonical offpage findings (one per canonical target)
        for _, entry in offpage_groups.items():
            finding = {
            "id": "IDX_CANONICAL_POINTS_OFFPAGE",
            "category": CATEGORY,
            "severity": "fail",
            "title_en": "Canonical points to a different page",
            "title_ro": "Canonical indică o altă pagină",
            "description_en": "These pages declare a canonical URL that points to a different URL (often the site root/homepage) instead of the page’s own URL.",
            "description_ro": "Aceste pagini declară un URL canonical care indică un URL diferit (adesea rădăcina site-ului/homepage) în locul propriului URL al paginii.",
            "recommendation_en": "Confirm whether these pages should canonicalize to the homepage. If not, set each page’s canonical to its preferred URL.",
            "recommendation_ro": "Confirmați dacă aceste pagini trebuie să aibă canonical către homepage. Dacă nu, setați canonical pentru fiecare pagină către URL-ul preferat.",
            "evidence": {
                "type": "html_tag",
                "canonical_href": entry.get("canonical_href"),
                "canonical_resolved": entry.get("canonical_resolved"),
                "affected_pages": entry.get("affected_pages") or [],
            },
        }

        # Canonical target validation (earn complete proof)
        entry_dict = entry if isinstance(entry, dict) else {}
        target_fetches = entry_dict.get("target_fetches") or []

        valid_targets = [
            tf for tf in target_fetches
            if isinstance(tf, dict) and tf.get("final_status") == 200
        ]


        if valid_targets:
            finding["proof_completeness"] = "complete"
            finding["confidence_level"] = "high"
        else:
            finding["proof_completeness"] = "partial"
            finding["confidence_level"] = "medium"

        findings.append(finding)


        # --------------------------------------------------
        # Canonical target validation (earn complete proof)
        # --------------------------------------------------
        entry_dict = entry if isinstance(entry, dict) else {}
        canonicals = entry_dict.get("canonicals") or []


        target_fetches = [
            c.get("target_fetch")
            for c in canonicals
            if isinstance(c.get("target_fetch"), dict)
        ]

        valid_targets = [
            tf for tf in target_fetches
            if tf.get("final_status") == 200
        ]

        if valid_targets:
            finding["proof_completeness"] = "complete"
            finding["confidence_level"] = "high"
        else:
            finding["proof_completeness"] = "partial"
            finding["confidence_level"] = "medium"

        findings.append(finding)


    # -------------------------
    # Sitemap findings (site)
    # -------------------------
    sitemaps = idx_signals.get("sitemaps") or {}
    declared = sitemaps.get("declared") or []
    probed = sitemaps.get("probed") or []
    fetched = sitemaps.get("fetched") or {}
    robots_snippet = sitemaps.get("robots_snippet") or ""

    # Missing sitemap: no declared AND no probe 200
    if not declared and not _any_probe_ok(probed):
        findings.append({
            "id": "IDX_SITEMAP_MISSING",
            "category": CATEGORY,
            "severity": "info",
            "title_en": "Sitemap not found",
            "title_ro": "Sitemap inexistent",
            "description_en": "No sitemap was found via robots.txt or common sitemap locations.",
            "description_ro": "Nu a fost găsit un sitemap în robots.txt sau la locațiile uzuale.",
            "recommendation_en": "Publish a sitemap and reference it in robots.txt.",
            "recommendation_ro": "Publicați un sitemap și menționați-l în robots.txt.",
            "evidence": {
                "type": "sitemap_fetch",
                "probed": probed,
                "robots_sitemaps": declared,
            },
        })

    # Declared but unreachable
    unreachable_declared: list[dict[str, Any]] = []
    for sm_url in declared:
        entry = fetched.get(sm_url) or {}
        status = entry.get("status")
        error = entry.get("error")
        if error or (status is not None and int(status) >= 400):
            unreachable_declared.append({"url": sm_url, "status": status, "error": error})

    if unreachable_declared:
        findings.append({
            "id": "IDX_SITEMAP_DECLARED_BUT_UNREACHABLE",
            "category": CATEGORY,
            "severity": "warning",
            "title_en": "Declared sitemap is unreachable",
            "title_ro": "Sitemap declarat este inaccesibil",
            "description_en": "robots.txt declares a sitemap that cannot be fetched.",
            "description_ro": "robots.txt declară un sitemap care nu poate fi accesat.",
            "recommendation_en": "Fix the sitemap URL or ensure it returns HTTP 200.",
            "recommendation_ro": "Corectați URL-ul sitemap-ului sau asigurați returnarea HTTP 200.",
            "evidence": {
                "type": "sitemap_fetch",
                "declared": unreachable_declared,
                "robots_snippet": robots_snippet,
            },
        })

    # Invalid XML
    invalid_xml: list[dict[str, Any]] = []
    for sm_url, entry in fetched.items():
        if entry.get("status") == 200 and entry.get("parse_error"):
            invalid_xml.append({
                "url": sm_url,
                "status": entry.get("status"),
                "parse_error": entry.get("parse_error"),
                "body_snippet": entry.get("body_snippet"),
            })

    if invalid_xml:
        findings.append({
            "id": "IDX_SITEMAP_INVALID_XML",
            "category": CATEGORY,
            "severity": "warning",
            "title_en": "Sitemap XML is invalid",
            "title_ro": "XML-ul sitemap-ului este invalid",
            "description_en": "A sitemap URL returned HTTP 200 but could not be parsed as XML.",
            "description_ro": "Un sitemap a returnat HTTP 200, dar nu a putut fi interpretat ca XML.",
            "recommendation_en": "Fix the sitemap XML format and revalidate.",
            "recommendation_ro": "Corectați formatul XML al sitemap-ului și revalidați.",
            "evidence": {
                "type": "sitemap_parse",
                "invalid": invalid_xml,
            },
        })

    # Sample unreachable
    sample = sitemaps.get("sample") or {}
    sample_results = sample.get("results") or []
    failing = [
        s for s in sample_results
        if s.get("error") or (s.get("status") is not None and int(s.get("status")) >= 400)
    ]

    if failing:
        failing_important = any((s.get("url") or "") in important_set for s in failing)
        findings.append({
            "id": "IDX_SITEMAP_URLS_UNREACHABLE_SAMPLE",
            "category": CATEGORY,
            "severity": "fail" if failing_important else "warning",
            "title_en": "Sampled sitemap URLs are unreachable",
            "title_ro": "URL-urile din sitemap eșantionate sunt inaccesibile",
            "description_en": "Some sampled URLs from the sitemap did not return a successful response.",
            "description_ro": "Unele URL-uri eșantionate din sitemap nu au returnat un răspuns de succes.",
            "recommendation_en": "Remove or fix unreachable URLs in the sitemap.",
            "recommendation_ro": "Eliminați sau corectați URL-urile inaccesibile din sitemap.",
            "evidence": {
                "type": "sitemap_sample_result",
                "strategy": sample.get("strategy"),
                "n": sample.get("n"),
                "failing_count": len(failing),
                "sample": sample_results,
            },
        })
   
        # IMPORTANT PAGE NOT DISCOVERABLE
        homepage_links = set()
        pages = idx_signals.get("pages") or {}
        homepage_url = (idx_signals.get("homepage_final_url") or "").rstrip("/")

        # Collect internal links found on homepage
        homepage_page = pages.get(homepage_url)
        if homepage_page:
            fetch = homepage_page.get("fetch") or {}
            html = fetch.get("text") or ""
            try:
                from bs4 import BeautifulSoup
                soup = BeautifulSoup(html, "html.parser")
                for a in soup.find_all("a"):
                    href = str(a.get("href") or "").strip()

                    if href.startswith(("http://", "https://")):
                        homepage_links.add(href.rstrip("/"))
            except Exception:
                pass

        sitemap_urls = set()
        sitemaps = idx_signals.get("sitemaps") or {}
        fetched = sitemaps.get("fetched") or {}
        for sm in fetched.values():
            for u in sm.get("urls") or []:
                sitemap_urls.add(u.rstrip("/"))

        for page_url in important_urls:
            norm = page_url.rstrip("/")
            if norm == homepage_url:
                continue

            found_in_homepage = norm in homepage_links
            found_in_sitemap = norm in sitemap_urls

            if not found_in_homepage and not found_in_sitemap:
                severity = "fail" if page_url in primary_urls else "warning"

                findings.append({
                    "id": "IDX_IMPORTANT_PAGE_NOT_DISCOVERABLE",
                    "category": CATEGORY,
                    "severity": severity,
                    "title_en": "Important page is not discoverable by search engines",
                    "title_ro": "Pagina importantă nu este ușor descoperibilă de motoarele de căutare",
                    "description_en": (
                        "This page is indexable, but we could not find a clear discovery path "
                        "via internal links or sitemap references."
                    ),
                    "description_ro": (
                        "Pagina este indexabilă, dar nu am identificat o cale clară de descoperire "
                        "prin linkuri interne sau sitemap."
                    ),
                    "recommendation_en": (
                        "Link this page from the homepage or include it in the sitemap."
                    ),
                    "recommendation_ro": (
                        "Adăugați un link către această pagină din homepage sau includeți-o în sitemap."
                    ),
                    "evidence": {
                        "page_url": page_url,
                        "found_in_homepage_links": found_in_homepage,
                        "found_in_sitemap": found_in_sitemap,
                        "checked_sources": ["homepage_links", "sitemap_urls"],
                    },
                })


    return findings

def _blocked_important_urls(important_urls: list[str], ua_rules: dict[str, list[str]]) -> list[dict[str, Any]]:
    blocked: list[dict[str, Any]] = []
    for ua in ("*", "googlebot"):
        rules = ua_rules.get(ua) or []
        for url in important_urls:
            rule = _matching_disallow_rule(url, rules)
            if rule:
                blocked.append({"ua": ua, "url": url, "rule": rule})
    return blocked


def _matching_disallow_rule(url: str, rules: list[str]) -> str | None:
    path = urlparse(url).path or "/"
    for rule in rules:
        rule = (rule or "").strip()
        if not rule:
            continue
        if rule == "/":
            return rule
        if rule.startswith("/") and path.startswith(rule):
            return rule
    return None


def _first_noindex_meta(robots_meta: list[dict[str, Any]], googlebot_meta: list[dict[str, Any]]) -> dict[str, Any] | None:
    for item in robots_meta + googlebot_meta:
        content = (item.get("content") or "").lower()
        if _has_token(content, "noindex"):
            return item
    return None


def _has_conflicting_directives(
    robots_meta: list[dict[str, Any]],
    googlebot_meta: list[dict[str, Any]],
    x_robots: str,
) -> bool:
    has_noindex = False
    has_index = False
    for item in robots_meta + googlebot_meta:
        content = (item.get("content") or "").lower()
        if _has_token(content, "noindex"):
            has_noindex = True
        if _has_token(content, "index"):
            has_index = True
    if _has_token(x_robots, "noindex"):
        has_noindex = True
    if _has_token(x_robots, "index"):
        has_index = True
    return has_noindex and has_index


def _has_token(text: str, token: str) -> bool:
    tokens = [t for t in text.replace(";", ",").replace(" ", ",").split(",") if t]
    return token in [t.strip() for t in tokens]


def _canonical_points_offpage(final_url: str, canonical_url: str) -> bool | None:
    if not final_url or not canonical_url:
        return None
    pf = urlparse(final_url)
    pc = urlparse(canonical_url)
    final_host = (pf.netloc or "").lower()
    canon_host = (pc.netloc or "").lower()
    final_path = (pf.path or "/").rstrip("/")
    canon_path = (pc.path or "/").rstrip("/")
    if final_host != canon_host or final_path != canon_path:
        return True
    return False


def _chain_evidence(fetch: dict[str, Any], requested_url: str) -> dict[str, Any]:
    return {
        "type": "http_redirect_chain",
        "url": requested_url,
        "final_url": fetch.get("final_url"),
        "final_status": fetch.get("final_status"),
        "redirect_chain": fetch.get("redirect_chain") or [],
    }


def _any_probe_ok(probed: list[dict[str, Any]]) -> bool:
    for entry in probed:
        if entry.get("status") == 200:
            return True
    return False
