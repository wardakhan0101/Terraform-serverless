from urllib.parse import parse_qs, urlparse

from backend.common.cache import CacheCredentials


def test_signs_cache_iam_credentials(monkeypatch):
    monkeypatch.setenv("CACHE_USER", "portfolio-books")
    monkeypatch.setenv("CACHE_GROUP", "portfolio-cache")
    username, token = CacheCredentials().get_credentials()
    parsed = urlparse("https://" + token)
    params = parse_qs(parsed.query)
    assert username == "portfolio-books"
    assert parsed.hostname == "portfolio-cache"
    assert params["User"] == [username]
    assert params["Action"] == ["connect"]
    assert params["X-Amz-Expires"] == ["900"]
    assert "elasticache/aws4_request" in params["X-Amz-Credential"][0]
