"""
web_vitals.py - Web Vitals Extraction (LCP, CLS, FID).

Usage:
    # Inside a Playwright page session
    metrics = measure_vitals(page)
"""

# JavaScript to inject for Web Vitals
# Based on Google's 'web-vitals' library logic simplified
VITALS_SNIPPET = r"""
() => {
    return new Promise((resolve) => {
        const metrics = {
            lcp: 0,
            cls: 0,
            fid: 0
        };
        
        // LCP
        const lcpObserver = new PerformanceObserver((entryList) => {
            const entries = entryList.getEntries();
            const lastEntry = entries[entries.length - 1];
            metrics.lcp = lastEntry.startTime;
        });
        try { lcpObserver.observe({type: 'largest-contentful-paint', buffered: true}); } catch(e){}

        // CLS
        let clsValue = 0;
        const clsObserver = new PerformanceObserver((entryList) => {
            for (const entry of entryList.getEntries()) {
                if (!entry.hadRecentInput) {
                    clsValue += entry.value;
                }
            }
            metrics.cls = clsValue;
        });
        try { clsObserver.observe({type: 'layout-shift', buffered: true}); } catch(e){}

        // Resolve after 2 seconds (short observation window for audit)
        setTimeout(() => {
            resolve(metrics);
        }, 2000);
    });
}
"""

def measure_vitals(page) -> dict:
    """
    Injects observer and returns LCP/CLS metrics.
    Requires an active Playwright page object.
    Blocks for 2 seconds.
    """
    try:
        # We need to reload or just wait if page is already loaded?
        # Ideally this is called *before* navigation or immediately after.
        # But if page is loaded, 'buffered: true' handles past events.
        
        metrics = page.evaluate(VITALS_SNIPPET)
        return metrics
    except Exception as e:
        return {"error": str(e), "lcp": None, "cls": None}
