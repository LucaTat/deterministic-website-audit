"""
visual_engine.py - Reusable Playwright Visual Verifier.

Usage:
    with VisualVerifier() as vv:
        res = vv.capture("https://example.com", Path("out.png"))
"""

from __future__ import annotations

import logging
import json
from pathlib import Path
from typing import Optional, Literal

try:
    from playwright.sync_api import sync_playwright, TimeoutError as PlaywrightTimeout, Browser, Playwright, BrowserContext
    PLAYWRIGHT_AVAILABLE = True
except ImportError:
    PLAYWRIGHT_AVAILABLE = False
    PlaywrightTimeout = Exception
    # Type mocks for static analysis if library missing
    Browser = object
    Playwright = object
    BrowserContext = object

logger = logging.getLogger("visual_engine")

class VisualVerifier:
    def __init__(self, headless: bool = True):
        self._playwright: Optional[Playwright] = None
        self._browser: Optional[Browser] = None
        self._headless = headless

    def __enter__(self) -> "VisualVerifier":
        if PLAYWRIGHT_AVAILABLE:
            self._playwright = sync_playwright().start()
            self._browser = self._playwright.chromium.launch(
                headless=self._headless,
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
        """
        Captures a screenshot and extracts performance metrics.
        Returns a dictionary with 'ok', 'error', 'path', 'metrics'.
        """
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
            # Device Profiles
            if device_type == "mobile":
                # iPhone 13/14 Pro-ish
                viewport = {"width": 390, "height": 844}
                device_scale_factor = 3
                is_mobile = True
                has_touch = True
                user_agent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
            else:
                # Standard Desktop
                viewport = {"width": 1280, "height": 720}
                device_scale_factor = 1
                is_mobile = False
                has_touch = False
                user_agent = "VisualVerifier/1.0 (Desktop; +bot)"

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
            
            # Navigate
            try:
                page.goto(url, wait_until="networkidle", timeout=timeout_ms)
            except PlaywrightTimeout:
                logger.warning(f"Timeout loading {url}, state detailed capture may be partial.")
            
            # Extract Metrics using Navigation Timing API
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

            # Standardize rendering before snap
            page.emulate_media(color_scheme="light")
            page.screenshot(path=str(output_path), full_page=False)
            context.close()
            
            return {
                "ok": True,
                "error": None,
                "path": str(output_path),
                "width": viewport["width"],
                "height": viewport["height"],
                "metrics": metrics,
            }

        except Exception as e:
            logger.error(f"Visual capture error: {e}")
            return {
                "ok": False,
                "error": str(e),
                "path": None,
                "metrics": {},
            }
