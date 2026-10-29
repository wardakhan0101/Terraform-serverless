import json
import logging
import os
import time
import uuid

from botocore.exceptions import ClientError
from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field

from backend.common import cache
from backend.common.auth import identity
from backend.common.model import public_item, timestamp
from backend.services import store

logging.basicConfig(level=logging.INFO, format="%(message)s")
log = logging.getLogger("api")


class BookInput(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    title: str = Field(min_length=1, max_length=200)
    author: str = Field(min_length=1, max_length=120)
    description: str = Field(min_length=1, max_length=5000)


class ReviewInput(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    rating: int = Field(ge=1, le=5, strict=True)
    text: str = Field(default="", max_length=2000)


def create_app(service=None):
    service = service or os.getenv("SERVICE", "books")
    if service not in {"books", "reviews"}:
        raise ValueError("SERVICE must be books or reviews")
    app = FastAPI(title=f"{service.title()} API", version="1.0.0", docs_url=None, redoc_url=None)

    @app.middleware("http")
    async def telemetry(request, call_next):
        start = time.monotonic()
        request_id = str(uuid.uuid4())
        # REST VPC Link V2 can preserve the stage prefix. Accept only our fixed stage.
        if request.scope["path"].startswith("/portfolio/"):
            request.scope["path"] = request.scope["path"][len("/portfolio"):]
            request.scope["raw_path"] = request.scope["path"].encode()
        try:
            content_length = int(request.headers.get("content-length", "0"))
        except ValueError:
            return JSONResponse({"detail": "Invalid Content-Length"}, status_code=400)
        if content_length > 16384:
            return JSONResponse({"detail": "Request too large"}, status_code=413)
        # Bound chunked bodies too; API endpoints are small metadata JSON requests.
        body = await request.body()
        if len(body) > 16384:
            return JSONResponse({"detail": "Request too large"}, status_code=413)
        response = await call_next(request)
        response.headers["X-Request-Id"] = request_id
        response.headers["Cache-Control"] = "no-store"
        log.info(json.dumps({"event": "request", "requestId": request_id, "service": service,
                             "method": request.method, "status": response.status_code,
                             "durationMs": round((time.monotonic() - start) * 1000)}))
        return response

    @app.exception_handler(ClientError)
    async def aws_error(request, exc):
        log.error(json.dumps({"event": "aws_error", "code": exc.response["Error"]["Code"]}))
        return JSONResponse({"detail": "Service temporarily unavailable"}, status_code=503)

    @app.get("/health")
    def health():
        return {"status": "ok", "service": service}

    if service == "books":
        @app.get("/books")
        def books(limit: int = Query(20, ge=1, le=50), cursor: str | None = None):
            try:
                return store.list_books(limit, cursor)
            except ValueError as exc:
                raise HTTPException(400, str(exc)) from exc

        @app.get("/books/{book_id}")
        def book(book_id: uuid.UUID):
            key = f"book:{book_id}"
            cached = cache.get(key)
            if cached:
                return cached
            item = store.get_book(str(book_id))
            if not item:
                raise HTTPException(404, "Book not found")
            value = public_item(item)
            cache.put(key, value, 300)  # Books are immutable.
            return value

        @app.post("/books", status_code=201)
        def add_book(body: BookInput, request: Request):
            author_id = identity(request, "author")
            book_id, created_at = str(uuid.uuid4()), timestamp()
            item = {"PK": book_id, "SK": "Meta", "kind": "book", "bookId": book_id,
                    "authorId": author_id, "createdAt": created_at, "CatalogPK": "BOOKS",
                    "CatalogSK": f"{created_at}#{book_id}", **body.model_dump()}
            store.create_book(item)
            return public_item(item)
    else:
        @app.get("/reviews/{book_id}")
        def reviews(book_id: uuid.UUID, limit: int = Query(20, ge=1, le=50), cursor: str | None = None):
            try:
                # Validate before using user input in cache keys.
                store.decode_cursor(cursor, f"reviews:{book_id}")
                key = f"reviews:{book_id}:{limit}:{cursor or ''}"
                value = cache.get(key)
                if value is None:
                    value = store.list_reviews(str(book_id), limit, cursor)
                    cache.put(key, value, 30)
                return value
            except ValueError as exc:
                raise HTTPException(400, str(exc)) from exc

        @app.post("/reviews/{book_id}", status_code=201)
        def add_review(book_id: uuid.UUID, body: ReviewInput, request: Request):
            reader_id = identity(request, "reader")
            if not store.get_book(str(book_id)):
                raise HTTPException(404, "Book not found")
            item = store.review_item(str(book_id), reader_id, str(uuid.uuid4()), timestamp(),
                                     body.rating, body.text)
            try:
                store.create_review(item)
            except ValueError as exc:
                raise HTTPException(409, str(exc)) from exc
            return public_item(item)
    return app


app = create_app()
