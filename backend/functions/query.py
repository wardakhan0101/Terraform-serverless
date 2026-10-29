import json
import logging
import os

from boto3.dynamodb.conditions import Key

from backend.common.aws import dynamodb
from backend.common.model import json_default

log = logging.getLogger(__name__)


def top_books():
    table = dynamodb().Table(os.environ["STATS_TABLE"])
    candidates = []
    for index in range(4):
        items, cursor = [], None
        for _ in range(100):
            args = {"IndexName": "top-rated", "KeyConditionExpression": Key("TopPK").eq(f"TOP_RATED#{index}"),
                    "ScanIndexForward": False, "Limit": 25}
            if cursor:
                args["ExclusiveStartKey"] = cursor
            result = table.query(**args)
            items.extend(result["Items"])
            cursor = result.get("LastEvaluatedKey")
            # Continue through all ties at the tenth score before sorting by book ID.
            if not cursor or (len(items) > 10 and items[-1]["averageRating"] < items[9]["averageRating"]):
                break
        else:
            raise RuntimeError("Ranking tie set exceeds bounded query budget")
        items.sort(key=lambda i: (-i["averageRating"], i["BookID"]))
        candidates.extend(items[:10])
    candidates.sort(key=lambda i: (-i["averageRating"], i["BookID"]))
    return [{"bookId": i["BookID"], "averageRating": i["averageRating"], "reviewCount": i["reviewCount"]}
            for i in candidates[:10]]


def handler(event, context):
    try:
        if event.get("queryStringParameters"):
            return {"statusCode": 400, "headers": {"Cache-Control": "no-store"},
                    "body": json.dumps({"detail": "Discover does not accept filters"})}
        return {"statusCode": 200,
                "headers": {"Content-Type": "application/json", "Cache-Control": "public, max-age=600"},
                "body": json.dumps({"items": top_books()}, default=json_default)}
    except Exception:
        log.exception("discover_query_failed")
        return {"statusCode": 503, "headers": {"Cache-Control": "no-store"},
                "body": json.dumps({"detail": "Discover temporarily unavailable"})}
