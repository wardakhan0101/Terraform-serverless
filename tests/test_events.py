import json
import uuid
from decimal import Decimal

import pytest
from botocore.exceptions import ClientError

from backend.common.aws import dynamodb
from backend.functions import aggregator, publisher, query


def message(book_id=None, rating=5):
    return {"schemaVersion": 1, "eventId": str(uuid.uuid4()), "bookId": book_id or str(uuid.uuid4()), "rating": rating}


def test_duplicate_and_replay_persistent_marker():
    event = message()
    assert aggregator.aggregate(event) == "applied"
    assert aggregator.aggregate(event) == "duplicate"
    other = message(event["bookId"], 1)
    assert aggregator.aggregate(other) == "applied"
    assert aggregator.aggregate(event) == "duplicate"
    stats = dynamodb().Table("stats").get_item(Key={"BookID": event["bookId"], "SK": "Stats"})["Item"]
    assert (stats["reviewCount"], stats["ratingTotal"], stats["averageRating"]) == (2, 6, Decimal(3))
    assert len(query.top_books()) == 1  # sparse index excludes event markers


def test_aggregate_transaction_conflict_retries(monkeypatch):
    real = aggregator.client("dynamodb")
    original = real.transact_write_items
    calls = []
    def conflict_once(**kwargs):
        calls.append(kwargs)
        if len(calls) == 1:
            raise ClientError({"Error": {"Code": "TransactionCanceledException"}}, "TransactWriteItems")
        return original(**kwargs)
    monkeypatch.setattr(real, "transact_write_items", conflict_once)
    assert aggregator.aggregate(message()) == "applied"
    assert len(calls) == 2


def test_atomic_failure_does_not_leave_marker(monkeypatch):
    real = aggregator.client("dynamodb")
    event = message()
    def failure(**kwargs):
        raise ClientError({"Error": {"Code": "AccessDeniedException"}}, "TransactWriteItems")
    monkeypatch.setattr(real, "transact_write_items", failure)
    with pytest.raises(ClientError):
        aggregator.aggregate(event)
    assert not real.get_item(TableName="stats", Key=aggregator.wire({"BookID": event["bookId"], "SK": f"EVENT#{event['eventId']}"})).get("Item")


def test_fifo_partial_failure_blocks_only_failed_group(monkeypatch):
    group_a, group_b = str(uuid.uuid4()), str(uuid.uuid4())
    events = [message(group_a), message(group_a), message(group_b)]
    visited = []
    def consume(event):
        visited.append(event["eventId"])
        if event["bookId"] == group_a:
            raise RuntimeError("poison")
    monkeypatch.setattr(aggregator, "aggregate", consume)
    records = [{"messageId": str(i), "body": json.dumps(e), "attributes": {"MessageGroupId": e["bookId"]}} for i, e in enumerate(events)]
    assert aggregator.handler({"Records": records}, None) == {"batchItemFailures": [{"itemIdentifier": "0"}, {"itemIdentifier": "1"}]}
    assert visited == [events[0]["eventId"], events[2]["eventId"]]


def test_publisher_skips_markers_and_checks_send_failure(monkeypatch):
    monkeypatch.setenv("QUEUE_URL", "mock")
    calls = []
    class Queue:
        def send_message(self, **kwargs):
            calls.append(kwargs)
            return {} if kwargs["MessageGroupId"] == "a" else {"MessageId": "ok"}
    monkeypatch.setattr(publisher, "client", lambda service: Queue())
    records = [{"eventName": "INSERT", "dynamodb": {"SequenceNumber": str(i), "NewImage": {
        "kind": {"S": kind}, "bookId": {"S": book}, "reviewId": {"S": str(i)}, "rating": {"N": "5"}}}}
        for i, (kind, book) in enumerate([("uniqueness", "a"), ("review", "a"), ("review", "a"), ("review", "b")])]
    assert publisher.handler({"Records": records}, None) == {"batchItemFailures": [{"itemIdentifier": "1"}, {"itemIdentifier": "2"}]}
    assert len(calls) == 2
    assert calls[1]["MessageDeduplicationId"] == "3"


def test_discover_ties_span_pages():
    ids = [str(uuid.uuid4()) for _ in range(160)]
    for book_id in ids:
        aggregator.aggregate(message(book_id))
    items = query.top_books()
    assert [i["bookId"] for i in items] == sorted(ids)[:10]
    assert all(i["averageRating"] == 5 for i in items)
    assert query.handler({"queryStringParameters": {"filter": "unsupported"}}, None)["statusCode"] == 400


def test_discover_average_order():
    low, high = str(uuid.uuid4()), str(uuid.uuid4())
    aggregator.aggregate(message(low, 2))
    aggregator.aggregate(message(high, 4))
    aggregator.aggregate(message(high, 5))
    assert query.top_books()[0] == {"bookId": high, "averageRating": Decimal("4.5"), "reviewCount": 2}
