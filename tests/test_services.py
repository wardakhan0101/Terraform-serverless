import uuid
from concurrent.futures import ThreadPoolExecutor
from threading import Lock

import pytest
from fastapi.testclient import TestClient

from backend.common import cache
from backend.services import store
from backend.services.app import create_app

BOOK = {"title": "A book", "author": "An author", "description": "A thoughtful description."}


def add_book(headers):
    response = TestClient(create_app("books")).post("/books", json=BOOK, headers=headers)
    assert response.status_code == 201
    return response.json()


def test_pool_authorization_and_immutability(author_headers, reader_headers):
    books, reviews = TestClient(create_app("books")), TestClient(create_app("reviews"))
    assert books.post("/books", json=BOOK).status_code == 403
    assert books.post("/books", json=BOOK, headers=reader_headers).status_code == 403
    bad = {**author_headers, "X-Identity-Audience": "other-client"}
    assert books.post("/books", json=BOOK, headers=bad).status_code == 403
    book = add_book(author_headers)
    path = f"/reviews/{book['bookId']}"
    assert reviews.post(path, json={"rating": 5}, headers=author_headers).status_code == 403
    assert reviews.post(path, json={"rating": 5}, headers=reader_headers).status_code == 201
    assert reviews.post(path, json={"rating": 1}, headers=reader_headers).status_code == 409
    assert reviews.get(path).json()["items"][0]["rating"] == 5
    for method in ("put", "patch", "delete"):
        assert getattr(books, method)(f"/books/{book['bookId']}").status_code == 405
        assert getattr(reviews, method)(path).status_code == 405
    assert "readerId" not in reviews.get(path).json()["items"][0]
    assert books.get(f"/portfolio/books/{book['bookId']}").status_code == 200


@pytest.mark.parametrize("rating", [0, 6, 1.5, "5", True])
def test_rating_validation(author_headers, reader_headers, rating):
    book = add_book(author_headers)
    response = TestClient(create_app("reviews")).post(f"/reviews/{book['bookId']}",
        json={"rating": rating}, headers=reader_headers)
    assert response.status_code == 422


def test_nonexistent_book_and_metadata_validation(reader_headers, author_headers):
    response = TestClient(create_app("reviews")).post(f"/reviews/{uuid.uuid4()}", json={"rating": 5}, headers=reader_headers)
    assert response.status_code == 404
    books = TestClient(create_app("books"))
    assert books.post("/books", json={**BOOK, "coverUrl": "bad"}, headers=author_headers).status_code == 422
    assert books.post("/books", json={**BOOK, "title": " "}, headers=author_headers).status_code == 422


def test_sharded_newest_first_pagination_no_gaps():
    book_id = str(uuid.uuid4())
    inserted = []
    for i in range(23):
        item = store.review_item(book_id, f"reader-{i}", str(uuid.uuid4()), f"2026-10-28T10:00:{i:02d}.000000Z", 5, "")
        store.create_review(item)
        inserted.append(item)
    results, cursor = [], None
    while True:
        page = store.list_reviews(book_id, 5, cursor)
        results.extend(page["items"])
        cursor = page["nextCursor"]
        if not cursor:
            break
    assert [r["reviewId"] for r in results] == [r["reviewId"] for r in reversed(inserted)]
    assert len({r["reviewId"] for r in results}) == 23
    with pytest.raises(ValueError):
        store.list_reviews(str(uuid.uuid4()), 5, store.list_reviews(book_id, 5, None)["nextCursor"])


def test_concurrent_review_uniqueness(monkeypatch):
    # Moto is not thread-safe. Serialize its transaction boundary to model DynamoDB
    # atomicity, while callers submit concurrently. This is NOT live concurrency proof.
    db = store.client("dynamodb")
    transact = db.transact_write_items
    lock = Lock()
    def atomic_transact(**kwargs):
        with lock:
            return transact(**kwargs)
    monkeypatch.setattr(db, "transact_write_items", atomic_transact)
    book_id = str(uuid.uuid4())
    def submit(i):
        item = store.review_item(book_id, "same-reader", str(uuid.uuid4()), f"2026-10-28T10:00:{i:02d}.000000Z", 5, "")
        try:
            store.create_review(item)
            return True
        except ValueError:
            return False
    with ThreadPoolExecutor(max_workers=4) as executor:
        results = list(executor.map(submit, range(8)))
    assert sum(results) == 1
    assert len(store.list_reviews(book_id, 20, None)["items"]) == 1


def test_cache_failure_falls_back(author_headers, monkeypatch):
    book = add_book(author_headers)
    def broken():
        raise OSError("cache down")
    monkeypatch.setattr(cache, "connection", broken)
    response = TestClient(create_app("books")).get(f"/books/{book['bookId']}")
    assert response.status_code == 200
    assert response.json()["title"] == BOOK["title"]
