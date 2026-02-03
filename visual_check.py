"""Visual verification module using Playwright."""

from __future__ import annotations

import logging
import json
import os
from pathlib import Path
from typing import Optional, Literal

try:
    from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout, Browser, Playwright
    PLAYWRIGHT_AVAILABLE = True
    # Import vitals snippet if available
    try:
        from web_vitals import VITALS_SNIPPET
    except ImportError:
        VITALS_SNIPPET = "() => { return {lcp: 0, cls: 0}; }" # Fallback
except ImportError:
    PLAYWRIGHT_AVAILABLE = False
    PlaywrightTimeout = Exception  # type: ignore
    VITALS_SNIPPET = ""

logger = logging.getLogger(__name__)

class VisualVerifier:
    def __init__(self):
        self._playwright: Optional[Playwright] = None
        self._browser: Optional[Browser] = None

    def __enter__(self) -> "VisualVerifier":
        if PLAYWRIGHT_AVAILABLE:
            self._playwright = sync_playwright().start()
            self._browser = self._playwright.chromium.launch(
                headless=True,
                args=[
                    "--no-sandbox",
                    "--disable-setuid-sandbox",
                    "--disable-dev-shm-usage",
                    "--disable-gpu",
                    "--font-render-hinting=none",
                ]
            )
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if self._browser:
            self._browser.close()
        if self._playwright:
            self._playwright.stop()

    def capture(
        self,
        url: str,
        output_path: Path,
        device_type: Literal["desktop", "mobile"] = "desktop",
        timeout_ms: int = 20000,
    ) -> dict:
        if not PLAYWRIGHT_AVAILABLE or not self._browser:
            return {
                "ok": False,
                "error": "playwright_not_installed_or_initialized",
                "path": None,
                "metrics": {},
            }
        
        output_path.parent.mkdir(parents=True, exist_ok=True)
        metrics = {"load_time_ms": None, "fcp_ms": None}

        try:
             # Device Configuration
            if device_type == "mobile":
                viewport = {"width": 390, "height": 844}
                device_scale_factor = 3
                is_mobile = True
                has_touch = True
                user_agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
            else:
                viewport = {"width": 1280, "height": 720}
                device_scale_factor = 1
                is_mobile = False
                has_touch = False
                user_agent = "ASTRA/1.0 (VisualGuard; +contact@astra.example)"

            context = self._browser.new_context(
                viewport=viewport,
                device_scale_factor=device_scale_factor,
                is_mobile=is_mobile,
                has_touch=has_touch,
                user_agent=user_agent,
                locale="en-US",
                timezone_id="UTC",
            )
            
            page = context.new_page()
            
            try:
                page.goto(url, wait_until="networkidle", timeout=timeout_ms)
            except PlaywrightTimeout:
                logger.warning(f"Timeout loading {url}, capturing partial state.")
            
            # Metrics
            try:
                perf_entry = page.evaluate("() => JSON.stringify(performance.getEntriesByType('navigation')[0])")
                paint_entry = page.evaluate("() => JSON.stringify(performance.getEntriesByType('paint'))")
                
                if perf_entry:
                    pdata = json.loads(perf_entry)
                    if pdata.get("loadEventEnd") and pdata.get("startTime") is not None:
                        metrics["load_time_ms"] = int(pdata["loadEventEnd"])
                
                if paint_entry:
                    paints = json.loads(paint_entry)
                    for pt in paints:
                        if pt.get("name") == "first-contentful-paint":
                             metrics["fcp_ms"] = int(pt.get("startTime", 0))
                             break
            except Exception:
                pass

            # Core Web Vitals (LCP, CLS)
            try:
                vitals = page.evaluate(VITALS_SNIPPET)
                if isinstance(vitals, dict):
                     # ensure keys are lcp, cls
                     metrics.update(vitals)
            except Exception:
                pass

            page.emulate_media(color_scheme="light")
            page.screenshot(path=str(output_path), full_page=False)
            context.close()  # Close context but keep browser
            
            return {
                "ok": True,
                "error": None,
                "path": str(output_path),
                "width": viewport["width"],
                "height": viewport["height"],
                "metrics": metrics,
            }

        except Exception as e:
            logger.error(f"Visual check failed: {e}")
            return {
                "ok": False,
                "error": str(e),
                "path": None,
                "metrics": {},
            }

def capture_screenshot(url: str, output_path: Path, device_type: str = "desktop", timeout_ms: int = 20000) -> dict:
    """Legacy wrapper for backward compatibility."""
    with VisualVerifier() as vv:
        return vv.capture(url, output_path, device_type, timeout_ms)
