import os

# Set test-only dummy credentials BEFORE importing application code. Moto intercepts AWS calls.
os.environ["AWS_ACCESS_KEY_ID"] = "testing"
os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
os.environ["AWS_SESSION_TOKEN"] = "testing"
os.environ["AWS_DEFAULT_REGION"] = "us-west-2"
os.environ["AWS_REGION"] = "us-west-2"
os.environ["AWS_EC2_METADATA_DISABLED"] = "true"
os.environ.pop("AWS_PROFILE", None)
os.environ.pop("AWS_DEFAULT_PROFILE", None)

import boto3  # noqa: E402
import pytest  # noqa: E402
from moto import mock_aws  # noqa: E402

from backend.common import aws, cache  # noqa: E402


@pytest.fixture(autouse=True)
def mocked_aws(monkeypatch):
    for kind in ("BOOKS", "REVIEWS", "STATS"):
        monkeypatch.setenv(f"{kind}_TABLE", kind.lower())
    monkeypatch.setenv("AUTHOR_ISSUER", "https://author-pool")
    monkeypatch.setenv("AUTHOR_CLIENT_ID", "author-client")
    monkeypatch.setenv("READER_ISSUER", "https://reader-pool")
    monkeypatch.setenv("READER_CLIENT_ID", "reader-client")
    monkeypatch.delenv("CACHE_HOST", raising=False)
    aws.client.cache_clear()
    aws.dynamodb.cache_clear()
    cache.connection.cache_clear()
    with mock_aws():
        db = boto3.client("dynamodb", region_name="us-west-2")
        for name, pk in (("books", "PK"), ("reviews", "PK"), ("stats", "BookID")):
            attrs = [{"AttributeName": pk, "AttributeType": "S"}, {"AttributeName": "SK", "AttributeType": "S"}]
            kwargs = {}
            if name in {"books", "stats"}:
                gpk, gsk = ("CatalogPK", "CatalogSK") if name == "books" else ("TopPK", "averageRating")
                attrs.extend([{"AttributeName": gpk, "AttributeType": "S"},
                              {"AttributeName": gsk, "AttributeType": "S" if name == "books" else "N"}])
                kwargs["GlobalSecondaryIndexes"] = [{"IndexName": "catalog" if name == "books" else "top-rated",
                    "KeySchema": [{"AttributeName": gpk, "KeyType": "HASH"}, {"AttributeName": gsk, "KeyType": "RANGE"}],
                    "Projection": {"ProjectionType": "ALL"}}]
            db.create_table(TableName=name, BillingMode="PAY_PER_REQUEST", AttributeDefinitions=attrs,
                            KeySchema=[{"AttributeName": pk, "KeyType": "HASH"},
                                       {"AttributeName": "SK", "KeyType": "RANGE"}], **kwargs)
        yield db
    aws.client.cache_clear()
    aws.dynamodb.cache_clear()


@pytest.fixture
def author_headers():
    return {"X-Identity-Sub": "author-1", "X-Identity-Issuer": "https://author-pool", "X-Identity-Audience": "author-client"}


@pytest.fixture
def reader_headers():
    return {"X-Identity-Sub": "reader-1", "X-Identity-Issuer": "https://reader-pool", "X-Identity-Audience": "reader-client"}
