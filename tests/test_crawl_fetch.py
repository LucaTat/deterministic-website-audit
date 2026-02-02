import types

import crawl_v1
from net_guardrails import MAX_REDIRECTS


class _Resp:
    def __init__(self, status_code, url, headers=None, body=b""):
        self.status_code = status_code
        self.url = url
        self.headers = headers or {}
        self._body = body
        self.encoding = "utf-8"

    def iter_content(self, chunk_size=16384):
        yield self._body


class _Session:
    def __init__(self, responses):
        self._responses = list(responses)
        self.max_redirects = MAX_REDIRECTS
        self.trust_env = True
        self.requests = []

    def get(self, url, headers=None, timeout=None, stream=None, allow_redirects=None):
        self.requests.append(url)
        if not self._responses:
            return _Resp(200, url, {}, b"ok")
        return self._responses.pop(0)


def test_fetch_calls_validate_url(monkeypatch):
    called = {"count": 0}

    def _validate(u):
        called["count"] += 1

    monkeypatch.setattr(crawl_v1, "validate_url", _validate)
    session = _Session([_Resp(200, "https://example.com", {}, b"ok")])
    monkeypatch.setattr(crawl_v1.requests, "Session", lambda: session)

    status, body, final_url, headers, error = crawl_v1._fetch("https://example.com")
    assert status == 200
    assert error is None
    assert called["count"] >= 1
    assert final_url == "https://example.com"


def test_fetch_invalid_url_rejected(monkeypatch):
    def _validate(_):
        raise ValueError("bad")

    monkeypatch.setattr(crawl_v1, "validate_url", _validate)
    session = _Session([_Resp(200, "http://127.0.0.1", {}, b"no")])
    monkeypatch.setattr(crawl_v1.requests, "Session", lambda: session)

    status, body, final_url, headers, error = crawl_v1._fetch("http://127.0.0.1")
    assert status is None
    assert error == "invalid_url"


def test_fetch_redirect_limit(monkeypatch):
    monkeypatch.setattr(crawl_v1, "validate_url", lambda _u: None)
    responses = []
    for i in range(MAX_REDIRECTS + 1):
        responses.append(_Resp(302, f"https://example.com/r{i}", {"Location": f"/r{i+1}"}))
    session = _Session(responses)
    monkeypatch.setattr(crawl_v1.requests, "Session", lambda: session)

    status, body, final_url, headers, error = crawl_v1._fetch("https://example.com/r0")
    assert status is None
    assert error == "too_many_redirects"
