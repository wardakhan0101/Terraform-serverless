import json
import logging
import os

from boto3.dynamodb.types import TypeDeserializer

from backend.common.aws import client
from backend.common.model import json_default

log = logging.getLogger(__name__)
DESERIALIZER = TypeDeserializer()


def handler(event, context):
    failures, blocked = [], set()
    for record in event.get("Records", []):
        image = record.get("dynamodb", {}).get("NewImage", {})
        if record.get("eventName") != "INSERT" or image.get("kind", {}).get("S") != "review":
            continue
        sequence = record["dynamodb"]["SequenceNumber"]
        book_id = image.get("bookId", {}).get("S", "invalid")
        try:
            if book_id in blocked:
                raise ValueError("Earlier send for this book failed")
            item = {key: DESERIALIZER.deserialize(value) for key, value in image.items()}
            # reviewId is persisted at creation; never generate a new ID during replay.
            message = {"schemaVersion": 1, "eventId": item["reviewId"], "bookId": item["bookId"],
                       "rating": int(item["rating"])}
            response = client("sqs").send_message(
                QueueUrl=os.environ["QUEUE_URL"], MessageBody=json.dumps(message, default=json_default),
                MessageGroupId=book_id, MessageDeduplicationId=message["eventId"])
            if not response.get("MessageId"):
                raise RuntimeError("SQS did not acknowledge the message")
        except Exception:
            blocked.add(book_id)
            failures.append({"itemIdentifier": sequence})
            log.error("review_publish_failed", extra={"sequence": sequence})
    return {"batchItemFailures": failures}
