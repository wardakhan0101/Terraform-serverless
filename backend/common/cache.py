"""Best-effort, bounded TLS cache: DynamoDB remains authoritative."""
import json
import logging
import os
from functools import lru_cache

import boto3
import redis
from botocore.auth import SigV4QueryAuth
from botocore.awsrequest import AWSRequest

from backend.common.model import json_default

log = logging.getLogger(__name__)


class CacheCredentials(redis.CredentialProvider):
    """Sign a fresh IAM token whenever Redis opens a connection."""

    def get_credentials(self):
        username = os.environ["CACHE_USER"]
        group = os.environ["CACHE_GROUP"].lower()
        credentials = boto3.Session().get_credentials()
        if credentials is None:
            raise RuntimeError("Task credentials unavailable")
        request = AWSRequest(method="GET", url=f"https://{group}/",
                             params={"Action": "connect", "User": username})
        SigV4QueryAuth(credentials.get_frozen_credentials(), "elasticache",
                       os.getenv("AWS_REGION", "us-west-2"), expires=900).add_auth(request)
        return username, request.url.removeprefix("https://")


@lru_cache
def connection():
    host = os.getenv("CACHE_HOST")
    if not host:
        return None
    return redis.Redis(host=host, port=6379, ssl=True, ssl_cert_reqs="required",
                       socket_connect_timeout=0.3, socket_timeout=0.3, decode_responses=True,
                       credential_provider=CacheCredentials(), health_check_interval=60)


def get(key):
    try:
        cache = connection()
        raw = cache.get(key) if cache else None
        return json.loads(raw) if raw else None
    except Exception:
        log.warning("cache_read_failed")
        return None


def put(key, value, ttl=30):
    try:
        cache = connection()
        if cache:
            cache.setex(key, ttl, json.dumps(value, default=json_default))
    except Exception:
        log.warning("cache_write_failed")
