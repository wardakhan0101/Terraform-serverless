import os

from boto3.dynamodb.conditions import Key
from boto3.dynamodb.types import TypeSerializer
from botocore.exceptions import ClientError

from backend.common.aws import client, dynamodb
from backend.common.model import decode_cursor, encode_cursor, public_item, shard

SERIALIZER = TypeSerializer()


def wire(item):
    return {key: SERIALIZER.serialize(value) for key, value in item.items()}


def table(name):
    return dynamodb().Table(os.environ[name])


def get_book(book_id):
    return table("BOOKS_TABLE").get_item(Key={"PK": book_id, "SK": "Meta"},
                                        ConsistentRead=True).get("Item")


def create_book(item):
    table("BOOKS_TABLE").put_item(Item=item, ConditionExpression="attribute_not_exists(PK)")


def list_books(limit, cursor):
    position = decode_cursor(cursor, "books")
    condition = Key("CatalogPK").eq("BOOKS")
    if position:
        condition &= Key("CatalogSK").lt(position)
    items = table("BOOKS_TABLE").query(IndexName="catalog", KeyConditionExpression=condition,
                                       ScanIndexForward=False, Limit=limit + 1)["Items"]
    page = items[:limit]
    return {"items": [public_item(i) for i in page],
            "nextCursor": encode_cursor("books", page[-1]["CatalogSK"]) if len(items) > limit else None}


def create_review(item):
    # The marker and review are inseparable, even for concurrent callers/retries.
    marker = {"PK": f"UNIQUE#{item['bookId']}#{item['readerId']}", "SK": "Unique", "kind": "uniqueness"}
    try:
        client("dynamodb").transact_write_items(TransactItems=[
            {"Put": {"TableName": os.environ["REVIEWS_TABLE"], "Item": wire(marker),
                     "ConditionExpression": "attribute_not_exists(PK)"}},
            {"Put": {"TableName": os.environ["REVIEWS_TABLE"], "Item": wire(item),
                     "ConditionExpression": "attribute_not_exists(PK)"}},
        ])
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "TransactionCanceledException":
            reasons = exc.response.get("CancellationReasons", [])
            if reasons and reasons[0].get("Code") == "ConditionalCheckFailed":
                raise ValueError("You have already reviewed this book") from exc
        raise


def list_reviews(book_id, limit, cursor):
    position = decode_cursor(cursor, f"reviews:{book_id}")
    candidates = []
    for index in range(4):
        condition = Key("PK").eq(f"{book_id}#{index}")
        if position:
            condition &= Key("SK").lt(position)
        response = table("REVIEWS_TABLE").query(KeyConditionExpression=condition,
                                                ScanIndexForward=False, Limit=limit + 1,
                                                ConsistentRead=True)
        candidates.extend(response["Items"])
    candidates.sort(key=lambda i: i["SK"], reverse=True)
    page = candidates[:limit]
    return {"items": [public_item(i) for i in page],
            "nextCursor": encode_cursor(f"reviews:{book_id}", page[-1]["SK"])
            if len(candidates) > limit else None}


def review_item(book_id, reader_id, review_id, created_at, rating, text):
    return {"PK": f"{book_id}#{shard(review_id)}", "SK": f"{created_at}#{review_id}",
            "kind": "review", "bookId": book_id, "readerId": reader_id, "reviewId": review_id,
            "createdAt": created_at, "rating": rating, "text": text}
