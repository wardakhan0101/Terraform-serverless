import json
import logging
import os
import random
import time
import uuid
from decimal import Decimal

from boto3.dynamodb.types import TypeDeserializer, TypeSerializer
from botocore.exceptions import ClientError

from backend.common.aws import client
from backend.common.model import shard

log = logging.getLogger(__name__)
SERIALIZER, DESERIALIZER = TypeSerializer(), TypeDeserializer()


def wire(item):
    return {key: SERIALIZER.serialize(value) for key, value in item.items()}


def aggregate(message):
    if message.get("schemaVersion") != 1:
        raise ValueError("Unsupported event version")
    event_id, book_id = str(uuid.UUID(message["eventId"])), str(uuid.UUID(message["bookId"]))
    rating = message["rating"]
    if type(rating) is not int or not 1 <= rating <= 5:
        raise ValueError("Invalid rating")
    db, table = client("dynamodb"), os.environ["STATS_TABLE"]
    marker_key = {"BookID": book_id, "SK": f"EVENT#{event_id}"}
    stats_key = {"BookID": book_id, "SK": "Stats"}
    for attempt in range(8):
        if db.get_item(TableName=table, Key=wire(marker_key), ConsistentRead=True).get("Item"):
            return "duplicate"
        raw = db.get_item(TableName=table, Key=wire(stats_key), ConsistentRead=True).get("Item", {})
        old = {key: DESERIALIZER.deserialize(value) for key, value in raw.items()}
        count, total = int(old.get("reviewCount", 0)) + 1, int(old.get("ratingTotal", 0)) + rating
        version = int(old.get("version", 0))
        updated = {**stats_key, "reviewCount": count, "ratingTotal": total, "version": version + 1,
                   "averageRating": Decimal(total) / Decimal(count), "TopPK": f"TOP_RATED#{shard(book_id)}"}
        condition = {"ConditionExpression": "#v = :v", "ExpressionAttributeNames": {"#v": "version"},
                     "ExpressionAttributeValues": wire({":v": version})} if raw else {
                         "ConditionExpression": "attribute_not_exists(BookID)"}
        try:
            db.transact_write_items(TransactItems=[
                {"Put": {"TableName": table, "Item": wire({**marker_key, "kind": "event"}),
                         "ConditionExpression": "attribute_not_exists(BookID)"}},
                {"Put": {"TableName": table, "Item": wire(updated), **condition}},
            ])
            return "applied"
        except ClientError as exc:
            if exc.response["Error"]["Code"] not in {"TransactionCanceledException", "TransactionConflictException"}:
                raise
            time.sleep(random.uniform(0, min(0.01 * 2 ** attempt, 0.2)))  # noqa: S311
    raise RuntimeError("Concurrent aggregate updates exhausted retry budget")


def handler(event, context):
    failures, blocked = [], set()
    for record in event.get("Records", []):
        group = record.get("attributes", {}).get("MessageGroupId", "missing")
        try:
            if group in blocked:
                raise ValueError("Earlier message in this group failed")
            message = json.loads(record["body"])
            if message.get("bookId") != group:
                raise ValueError("Message group does not match book")
            aggregate(message)
        except Exception:
            blocked.add(group)
            failures.append({"itemIdentifier": record["messageId"]})
            log.error("aggregate_failed", extra={"messageId": record["messageId"]})
    return {"batchItemFailures": failures}
