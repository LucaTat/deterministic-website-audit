"""
safe_fetch.py - SSRF-protected HTTP client with DNS Pinning.

Usage:
    session = safe_session()
    resp = session.get("https://example.com")
    
    # Or simple wrapper:
    resp = safe_get("https://example.com")
"""

import socket
import ipaddress
import requests
from requests.adapters import HTTPAdapter
from urllib.parse import urlparse
from urllib3.connection import HTTPConnection, HTTPSConnection
from urllib3.connectionpool import HTTPConnectionPool, HTTPSConnectionPool

DEFAULT_TIMEOUT = 10
MAX_REDIRECTS = 5
USER_AGENT = "AuditBot/1.0 (+http://example.com)"

PRIVATE_IP_RANGES = [
    ipaddress.ip_network("10.0.0.0/8"),
    ipaddress.ip_network("172.16.0.0/12"),
    ipaddress.ip_network("192.168.0.0/16"),
    ipaddress.ip_network("127.0.0.0/8"),
    ipaddress.ip_network("169.254.0.0/16"),
    ipaddress.ip_network("::1/128"),
    ipaddress.ip_network("fc00::/7"),
    ipaddress.ip_network("fe80::/10"),
]

class SafeConnectionMixin:
    """Mixin to pin the connection to a specific IP address."""
    def __init__(self, *args, **kwargs):
        self._pinned_ip = kwargs.pop('_pinned_ip', None)
        super().__init__(*args, **kwargs)

    def connect(self):
        """Connect to the pinned IP if available, otherwise standard resolution."""
        if self._pinned_ip:
            # We must set both host and port for connect to work, 
            # but we want to actually connect to _pinned_ip.
            # The exact mechanism depends on urllib3 version, but generally 
            # we can replace the host temporarily for the socket connection 
            # OR we can just override _new_conn in a customized way.
            # A simpler way in modern urllib3 is allowing the host to be the IP
            # but setting the Sni/Host header correctly.
            pass
        return super().connect()
        
    def _new_conn(self):
        """Establish a socket connection to the pinned IP."""
        if self._pinned_ip:
            # Create a connection to the IP, not the hostname
            extra_kw = {}
            if self.source_address:
                extra_kw['source_address'] = self.source_address
            
            # This is the lowest level connection creation
            # We connect to (IP, port) instead of (Hostname, port)
            conn = socket.create_connection(
                (self._pinned_ip, self.port),
                self.timeout,
                **extra_kw
            )
            return conn
        return super()._new_conn()

class SafeHTTPConnection(SafeConnectionMixin, HTTPConnection):
    pass

class SafeHTTPSConnection(SafeConnectionMixin, HTTPSConnection):
    pass

class SafeHTTPConnectionPool(HTTPConnectionPool):
    def __init__(self, host, port=None, _pinned_ip=None, **kwargs):
        self._pinned_ip = _pinned_ip
        super().__init__(host, port, **kwargs)

    def _new_conn(self):
        self.ConnectionCls = SafeHTTPConnection
        conn = super()._new_conn()
        conn._pinned_ip = self._pinned_ip
        return conn

class SafeHTTPSConnectionPool(HTTPSConnectionPool):
    def __init__(self, host, port=None, _pinned_ip=None, **kwargs):
        self._pinned_ip = _pinned_ip
        super().__init__(host, port, **kwargs)

    def _new_conn(self):
        self.ConnectionCls = SafeHTTPSConnection
        conn = super()._new_conn()
        conn._pinned_ip = self._pinned_ip
        return conn

class SafeTransportAdapter(HTTPAdapter):
    """
    Adapter that resolves DNS first, checks safety, then pins the IP.
    """
    def resolve_and_check(self, host):
        try:
            # Resolve
            addr_info = socket.getaddrinfo(host, None, proto=socket.IPPROTO_TCP)
            # Just take the first one
            ip_str = addr_info[0][4][0]
            
            # Check safety
            ip_obj = ipaddress.ip_address(ip_str)
            for private_range in PRIVATE_IP_RANGES:
                if ip_obj in private_range:
                    raise ValueError(f"Target resolves to private IP: {ip_str}")
            
            return ip_str
        except socket.gaierror:
            raise ValueError(f"DNS resolution failed for {host}")

    def get_connection(self, url, proxies=None):
        # Allow requests to handle proxies if needed, but we focus on direct fetch
        if proxies:
            return super().get_connection(url, proxies)

        parsed = urlparse(url)
        if not parsed.hostname:
            raise ValueError("Missing hostname")
            
        # 1. Resolve & Check
        pinned_ip = self.resolve_and_check(parsed.hostname)
        
        # 2. Return a custom PoolManager/ConnectionPool that uses this IP
        # Since get_connection returns a ConnectionPool, we need to create one 
        # that will produce our SafeConnection.
        
        # To avoid reimplementing the entire PoolManager logic (connection reuse etc),
        # we can hack it slightly: we are creating a new connection for *every* request 
        # effectively if we want to be strictly safe per-request, OR we assume
        # the hostname->IP mapping is stable for the session.
        # Given we want per-request safety, we might just bypass the pool cache 
        # or cache by (hostname, IP).
        
        # Simplified approach: We delegate to poolmanager but override `connection_from_url` logic?
        # Actually `get_connection` is called by `send`. 
        # Let's override `send` instead, it's easier to inject logic there.
        return super().get_connection(url, proxies)

    def send(self, request, **kwargs):
        # 1. Resolve & Check
        parsed = urlparse(request.url)
        if not parsed.hostname:
             raise ValueError("Missing hostname")
             
        pinned_ip = self.resolve_and_check(parsed.hostname)
        
        # 2. Inject the pinned IP into the pool
        # We need to access the connection pool for this request
        conn = self.get_connection(request.url, kwargs.get("proxies"))
        
        # If we modify the pool, we affect all requests to this host.
        # For a "Safe Fetch" generic usage, this is acceptable (we want all to be safe).
        # We need to ensure the pool uses our SafeConnection classes.
        
        # Actually, standard HTTPAdapter uses `poolmanager.connection_from_url`.
        # We can implement a custom PoolManager.
        return super().send(request, **kwargs)

    def init_poolmanager(self, connections, maxsize, block=False, **pool_kwargs):
        # Use our custom pool manager? 
        # Or just let standard one work and only override the Pool classes?
        # It's hard to inject custom Pool classes into standard PoolManager without subclassing it.
        
        self._pool_connections = connections
        self._pool_maxsize = maxsize
        self._pool_block = block
        
        self.poolmanager = SafePoolManager(num_pools=connections, maxsize=maxsize,
                                           block=block, strict=True, **pool_kwargs)

class SafePoolManager(requests.adapters.PoolManager):
    def connection_from_host(self, host, port=1, scheme='http', pool_kwargs=None):
        # We need to intercept here to perform DNS check + IP Pinning
        # But wait, `connection_from_host` is cached. 
        # If we resolve IP here, we pin it for the lifetime of the pool (session).
        # That is arguably DESIRABLE for a consistent session.
        
        if pool_kwargs is None:
            pool_kwargs = {}
            
        # Resolve & Check
        try:
             # Re-use the existing resolve logic? We can just do it inline here.
            addr_info = socket.getaddrinfo(host, None, proto=socket.IPPROTO_TCP)
            ip_str = addr_info[0][4][0]
            ip_obj = ipaddress.ip_address(ip_str)
            for private_range in PRIVATE_IP_RANGES:
                if ip_obj in private_range:
                    raise ValueError(f"Target resolves to private IP: {ip_str}")
                    
            pool_kwargs['_pinned_ip'] = ip_str
            
        except socket.gaierror:
            raise ValueError(f"DNS resolution failed for {host}")
            
        # Determine strict class
        if scheme == 'https':
            return SafeHTTPSConnectionPool(host, port, **pool_kwargs)
        else:
            # Filter out SSL kwargs for HTTP
            http_kwargs = pool_kwargs.copy()
            for key in ("key_file", "cert_file", "cert_reqs", "ca_certs", "ssl_version", "assert_hostname", "assert_fingerprint", "ca_cert_dir", "ssl_context"):
                http_kwargs.pop(key, None)
            return SafeHTTPConnectionPool(host, port, **http_kwargs)

def safe_session() -> requests.Session:
    """Create a requests Session that enforces SSRF protection via DNS pinning."""
    session = requests.Session()
    adapter = SafeTransportAdapter()
    session.mount("http://", adapter)
    session.mount("https://", adapter)
    session.headers.update({"User-Agent": USER_AGENT})
    return session

def safe_get(url: str, **kwargs) -> requests.Response:
    """Legacy wrapper using safe_session."""
    session = safe_session()
    kwargs.setdefault("timeout", DEFAULT_TIMEOUT)
    return session.get(url, **kwargs)
