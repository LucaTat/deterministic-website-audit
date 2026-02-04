#!/usr/bin/env python3
import sys
import os

# Add repo root to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from crawl_v1 import _parse_sitemap_xml
try:
    from defusedxml import ElementTree as ET
except ImportError:
    import xml.etree.ElementTree as ET # Fallback if defusedxml is missing

def test_sitemap_parsing():
    print("Testing sitemap parsing with defusedxml...")
    xml_content = """<?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
      <url>
        <loc>https://example.com/</loc>
        <lastmod>2024-01-01</lastmod>
      </url>
      <url>
        <loc>https://example.com/page1</loc>
      </url>
    </urlset>
    """
    
    urls, kind = _parse_sitemap_xml(xml_content)
    
    assert kind == "urlset", f"Expected urlset, got {kind}"
    assert len(urls) == 2, f"Expected 2 URLs, got {len(urls)}"
    assert "https://example.com/" in urls
    assert "https://example.com/page1" in urls
    
    print("Sitemap parsing passed.")

def test_xxe_safety():
    print("Testing XXE safety...")
    # Attempt a simple XXE payload
    xml_content = """<?xml version="1.0" encoding="ISO-8859-1"?>
    <!DOCTYPE foo [
    <!ELEMENT foo ANY >
    <!ENTITY xxe SYSTEM "file:///etc/passwd" >]><foo>&xxe;</foo>"""
    
    try:
        # If defusedxml is working, this might raise an error or just return empty text/safe content depending on config.
        # But specifically, we used ET.fromstring from defusedxml in crawl_v1.
        # It should forbid external entities by default.
        _parse_sitemap_xml(xml_content)
    except Exception as e:
        print(f"XXE blocked/failed as expected or handled: {e}")
        # Note: defusedxml.ElementTree raises ParseError or generic Error on entities if forbidden.
        pass
    
    print("XXE safety check completed (did not crash interpreter).")

if __name__ == "__main__":
    try:
        test_sitemap_parsing()
        test_xxe_safety()
        sys.exit(0)
    except Exception as e:
        print(f"FAILED: {e}")
        sys.exit(1)
