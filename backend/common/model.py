"""Pure domain operations shared by services and event consumers."""
import base64
import hashlib
import json
from datetime import UTC, datetime
from decimal import Decimal


def shard(identifier: str) -> int:
    return int.from_bytes(hashlib.sha256(identifier.encode()).digest()[:8], "big") % 4


def timestamp() -> str:
    return datetime.now(UTC).isoformat(timespec="microseconds").replace("+00:00", "Z")


def json_default(value):
    if isinstance(value, Decimal):
        return int(value) if value == value.to_integral_value() else float(value)
    raise TypeError(f"Unsupported type: {type(value).__name__}")


def encode_cursor(scope: str, position: str) -> str:
    return base64.urlsafe_b64encode(json.dumps([scope, position]).encode()).decode().rstrip("=")


def decode_cursor(cursor: str | None, scope: str) -> str | None:
    if not cursor:
        return None
    try:
        if len(cursor) > 1024:
            raise ValueError
        value = json.loads(base64.urlsafe_b64decode(cursor + "=" * (-len(cursor) % 4)))
        if not isinstance(value, list) or len(value) != 2 or value[0] != scope:
            raise ValueError
        if not isinstance(value[1], str) or len(value[1]) > 200:
            raise ValueError
        return value[1]
    except (ValueError, TypeError, UnicodeError) as exc:
        raise ValueError("Invalid pagination cursor") from exc


def public_item(item: dict) -> dict:
    hidden = {"PK", "SK", "CatalogPK", "CatalogSK", "readerId", "authorId", "kind"}
    return {key: value for key, value in item.items() if key not in hidden}
