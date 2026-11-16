"""Single-user store-and-forward inbox. Run one uvicorn worker per database."""

import asyncio
import hashlib
import hmac
import json
import os
import sqlite3
import time
from contextlib import asynccontextmanager, contextmanager
from pathlib import Path
from typing import Literal

from fastapi import FastAPI, Header, HTTPException, Request, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field, field_validator


class MessageInput(BaseModel):
    id: str = Field(min_length=1, max_length=128, pattern=r"^[a-zA-Z0-9_.:-]+$")
    source: str = Field(default="默认", min_length=1, max_length=64)
    title: str = Field(min_length=1, max_length=160)
    summary: str = Field(default="", max_length=500)
    format: Literal["html", "markdown", "text"] = "html"
    content: str = Field(max_length=1_000_000)
    priority: Literal["normal", "silent"] = "normal"

    @field_validator("content")
    @classmethod
    def limit_content_bytes(cls, content: str) -> str:
        if len(content.encode("utf-8")) > 1_000_000:
            raise ValueError("Content exceeds 1 MB")
        return content


class ReceiptInput(BaseModel):
    ids: list[str] = Field(max_length=100)


class InboxStore:
    def __init__(self, path: Path):
        self.path = path
        path.parent.mkdir(parents=True, exist_ok=True)
        with self.connect() as database:
            database.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS messages (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    id TEXT UNIQUE NOT NULL,
                    fingerprint TEXT NOT NULL,
                    payload TEXT,
                    created_at INTEGER NOT NULL,
                    received_at INTEGER
                );
            """)

    @contextmanager
    def connect(self):
        database = sqlite3.connect(self.path, timeout=10)
        try:
            with database:
                yield database
        finally:
            database.close()

    def publish(self, message: MessageInput):
        payload = message.model_dump()
        encoded = json.dumps(payload, ensure_ascii=False, sort_keys=True)
        fingerprint = hashlib.sha256(encoded.encode()).hexdigest()
        now = int(time.time() * 1000)
        with self.connect() as database:
            database.execute("BEGIN IMMEDIATE")
            existing = database.execute(
                "SELECT fingerprint, received_at FROM messages WHERE id = ?", (message.id,)
            ).fetchone()
            if existing:
                if existing[0] != fingerprint:
                    raise HTTPException(409, "Message ID already has different content")
                return {"id": message.id, "status": "received" if existing[1] else "queued", "duplicate": True}
            pending = database.execute(
                "SELECT count(*), coalesce(sum(length(CAST(payload AS BLOB))), 0) FROM messages WHERE payload IS NOT NULL"
            ).fetchone()
            if pending[0] >= 10_000 or pending[1] + len(encoded.encode()) > 256_000_000:
                raise HTTPException(507, "Pending inbox is full")
            payload["createdAt"] = now
            database.execute(
                "INSERT INTO messages(id, fingerprint, payload, created_at) VALUES (?, ?, ?, ?)",
                (message.id, fingerprint, json.dumps(payload, ensure_ascii=False), now),
            )
        return {"id": message.id, "status": "queued", "duplicate": False}

    def pending(self):
        with self.connect() as database:
            rows = database.execute(
                "SELECT id FROM messages WHERE received_at IS NULL ORDER BY sequence LIMIT 50"
            ).fetchall()
        return [row[0] for row in rows]

    def message(self, message_id):
        with self.connect() as database:
            row = database.execute("SELECT payload FROM messages WHERE id = ?", (message_id,)).fetchone()
        if not row or row[0] is None:
            raise HTTPException(404, "Message content is unavailable")
        return json.loads(row[0])

    def acknowledge(self, ids):
        now = int(time.time() * 1000)
        with self.connect() as database:
            database.executemany(
                "UPDATE messages SET received_at = coalesce(received_at, ?), payload = NULL WHERE id = ?",
                [(now, message_id) for message_id in ids],
            )
        # Keep only IDs and hashes after receipt. A script retry can never resurrect a message.
        return {"acknowledged": len(ids)}

    def status(self, message_id):
        with self.connect() as database:
            row = database.execute(
                "SELECT created_at, received_at FROM messages WHERE id = ?", (message_id,)
            ).fetchone()
        if row is None:
            raise HTTPException(404, "Unknown message")
        return {"id": message_id, "status": "received" if row[1] else "queued", "createdAt": row[0], "receivedAt": row[1]}


def create_app(database_path=None, send_token=None, read_token=None):
    send_token = send_token or os.environ.get("DINGDONG_SEND_TOKEN", "")
    read_token = read_token or os.environ.get("DINGDONG_READ_TOKEN", "")
    if len(send_token) < 32 or len(read_token) < 32 or send_token == read_token:
        raise RuntimeError("Set two different DINGDONG_SEND_TOKEN and DINGDONG_READ_TOKEN values (32+ characters)")
    store = InboxStore(Path(database_path or os.environ.get("DINGDONG_DATABASE", "data/inbox.db")))
    changed = asyncio.Event()
    subscribers: set[WebSocket] = set()

    @asynccontextmanager
    async def lifespan(app):
        yield
        for socket in list(subscribers):
            await socket.close(code=1001)

    app = FastAPI(title="叮咚", version="0.1.0", lifespan=lifespan, docs_url=None, redoc_url=None)

    def authorize(header, expected):
        if not hmac.compare_digest(header or "", f"Bearer {expected}"):
            raise HTTPException(401, "Invalid credential")

    @app.middleware("http")
    async def limit_body(request: Request, call_next):
        if request.method == "POST":
            # Stream before parsing: Content-Length cannot be trusted for chunked requests.
            body = bytearray()
            async for chunk in request.stream():
                body.extend(chunk)
                if len(body) > 2_000_000:
                    from fastapi.responses import JSONResponse
                    return JSONResponse({"detail": "Request exceeds 2 MB"}, status_code=413)
            request._body = bytes(body)
        return await call_next(request)

    @app.get("/health")
    async def health():
        return {"service": "dingdong", "version": "0.1.0"}

    @app.post("/v1/messages", status_code=202)
    async def publish(message: MessageInput, authorization: str | None = Header(default=None)):
        authorize(authorization, send_token)
        result = await asyncio.to_thread(store.publish, message)
        changed.set()
        return result

    @app.get("/v1/messages/{message_id}/status")
    async def status(message_id: str, authorization: str | None = Header(default=None)):
        authorize(authorization, send_token)
        return await asyncio.to_thread(store.status, message_id)

    @app.get("/v1/messages/{message_id}")
    async def read(message_id: str, authorization: str | None = Header(default=None)):
        authorize(authorization, read_token)
        return await asyncio.to_thread(store.message, message_id)

    @app.post("/v1/receipts")
    async def receipt(receipt: ReceiptInput, authorization: str | None = Header(default=None)):
        authorize(authorization, read_token)
        result = await asyncio.to_thread(store.acknowledge, receipt.ids)
        changed.set()
        return result

    @app.websocket("/v1/stream")
    async def stream(socket: WebSocket):
        if not hmac.compare_digest(socket.headers.get("authorization", ""), f"Bearer {read_token}"):
            await socket.close(code=1008)
            return
        await socket.accept()
        # One receiving phone: only the latest connection receives the inbox.
        for previous in list(subscribers):
            await previous.close(code=4001, reason="Receiver replaced")
        subscribers.add(socket)
        try:
            while True:
                changed.clear()
                ids = await asyncio.to_thread(store.pending)
                await socket.send_json({"type": "pending", "ids": ids})
                try:
                    await asyncio.wait_for(changed.wait(), timeout=15)
                except TimeoutError:
                    pass
        except (WebSocketDisconnect, RuntimeError, OSError):
            pass
        finally:
            subscribers.discard(socket)

    return app
