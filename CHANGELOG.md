
# 3️⃣ CHANGELOG v1 (pentru livrare software)

👉 **Scop:** arată maturitate de produs și claritate la livrare.

**Changelog – v1.0 (Agency Pilot)**

**Added**

* Deterministic website audit engine
* Client-facing PDF output (RO / EN)
* Technical audit JSON with full evidence
* Embedded font support for Romanian diacritics
* Human-readable summaries for all audit modes

**Improved**

* Separation between client-facing content and technical evidence
* Error handling for inaccessible websites (SSL, DNS, hosting)
* Audit structure focused on conversion impact

**Fixed**

* Romanian diacritics rendering in PDF
* Removal of raw stack traces from client-facing reports
* Stable output across repeated runs

**Design Decisions**

* No AI used in analysis
* Conversion impact expressed as ranges, not fake precision
* Client PDF optimized for decision-making, not debugging

**Current Status**

* Ready for agency pilot
* Suitable for white-label usage
* Stable for repeated use

---

## Cum le folosești concret

* **Agenție** → trimiți documentul #1
* **Repo / proiect nou** → pui README-ul (#2)
* **Livrare software / zip / GitHub** → incluzi changelog (#3)

Dacă vrei, următorul pas poate fi:

* transformarea lor în **PDF-uri oficiale**
* sau adaptarea limbajului pentru **investitori / SaaS pitch**
* sau pregătirea unui **email exact** de trimitere a tool-ului

Spune-mi ce urmează.
