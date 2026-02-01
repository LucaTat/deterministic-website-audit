import unittest
from unittest.mock import patch, MagicMock
import socket
import sys
import os

# Add parent directory to path to import net_guardrails
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from net_guardrails import validate_url

class TestNetGuardrails(unittest.TestCase):
    def test_valid_urls(self):
        """Test standard public URLs pass validation."""
        # Check that no exception is raised
        # We need to mock getaddrinfo to return a public IP
        with patch('socket.getaddrinfo') as mock_dns:
            mock_dns.return_value = [(0, 0, 0, 0, ('8.8.8.8', 80))]
            validate_url("https://example.com")
            validate_url("http://google.com/foo/bar")

    def test_invalid_scheme(self):
        """Test non-HTTP/HTTPS schemes are blocked."""
        with self.assertRaises(ValueError) as cm:
            validate_url("ftp://example.com")
        self.assertIn("Unsafe scheme", str(cm.exception))

        with self.assertRaises(ValueError) as cm:
            validate_url("file:///etc/passwd")
        self.assertIn("Unsafe scheme", str(cm.exception))

    def test_missing_hostname(self):
        with self.assertRaises(ValueError) as cm:
            validate_url("https://")
        self.assertIn("Missing hostname", str(cm.exception))

    def test_private_ips(self):
        """Test that private IPs are blocked."""
        private_ips = [
            '127.0.0.1',
            '10.0.1.2',
            '192.168.1.1',
            '172.16.0.1',
            '169.254.169.254'
        ]
        with patch('socket.getaddrinfo') as mock_dns:
            for ip in private_ips:
                mock_dns.return_value = [(0, 0, 0, 0, (ip, 80))]
                with self.assertRaises(ValueError) as cm:
                    # Test with IP in URL
                    validate_url(f"http://{ip}")
                self.assertIn("private IP", str(cm.exception))

                with self.assertRaises(ValueError) as cm:
                    # Test with hostname resolving to private IP
                    validate_url("http://localhost-fake")
                self.assertIn("private IP", str(cm.exception))

    def test_dns_resolution_failure(self):
        """Test that DNS failure raises ValueError (Fail Closed)."""
        with patch('socket.getaddrinfo') as mock_dns:
            mock_dns.side_effect = socket.gaierror("Name or service not known")
            with self.assertRaises(ValueError) as cm:
                validate_url("https://nonexistent-domain.example")
            self.assertIn("DNS resolution failed", str(cm.exception))

if __name__ == '__main__':
    unittest.main()
