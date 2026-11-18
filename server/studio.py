"""Short-lived control relay. Configuration remains authoritative in Studio."""

import asyncio
import time
import uuid
from typing import Literal

from fastapi import Header, HTTPException, Response
from pydantic import BaseModel, Field


class CommandInput(BaseModel):
    session: str = Field(min_length=1, max_length=128)
    revision: str = Field(min_length=1, max_length=128)
    action: Literal["saveTask", "setEnabled", "deleteTask"]
    payload: dict


class CommandResult(BaseModel):
    id: str = Field(min_length=1, max_length=128)
    ok: bool
    error: str = Field(default="", max_length=2000)


class SyncInput(BaseModel):
    session: str = Field(min_length=1, max_length=128)
    snapshot: dict
    results: list[CommandResult] = Field(default_factory=list, max_length=32)


class StudioRelay:
    def __init__(self, command_timeout=20):
        self.command_timeout = command_timeout
        self.session = ""
        self.snapshot = None
        self.seen = 0.0
        self.pending = {}

    def online(self):
        return self.snapshot is not None and time.monotonic() - self.seen < 15

    def sync(self, message: SyncInput):
        if self.online() and message.session != self.session:
            raise HTTPException(409, "已有另一台 Studio 连接，请先关闭其手机管理")
        if message.session != self.session:
            for entry in self.pending.values():
                if not entry["future"].done():
                    entry["future"].set_result({"ok": False, "error": "Studio 已重新连接，请刷新后重试"})
            self.pending.clear()
        self.session = message.session
        self.snapshot = message.snapshot
        self.seen = time.monotonic()
        for result in message.results:
            entry = self.pending.get(result.id)
            if entry and not entry["future"].done():
                entry["future"].set_result({
                    "ok": result.ok,
                    "error": result.error[:1000],
                })
        commands = []
        for command_id, entry in list(self.pending.items()):
            remaining = entry["deadline"] - time.monotonic()
            if remaining > 0 and not entry["delivered"]:
                entry["delivered"] = True
                commands.append({"id": command_id, **entry["command"], "ttlMs": int(remaining * 1000)})
        return {"commands": commands}

    async def command(self, message: CommandInput):
        if not self.online():
            raise HTTPException(503, "Studio 未连接，请在电脑端开启手机管理并保持运行")
        if message.session != self.session or message.revision != self.snapshot.get("revision"):
            raise HTTPException(409, "订阅设置已变化，请刷新后重试")
        if len(self.pending) >= 32:
            raise HTTPException(429, "操作过多，请稍后重试")
        command_id = str(uuid.uuid4())
        future = asyncio.get_running_loop().create_future()
        self.pending[command_id] = {
            "future": future, "command": message.model_dump(),
            "deadline": time.monotonic() + self.command_timeout, "delivered": False,
        }
        try:
            result = await asyncio.wait_for(future, self.command_timeout)
            return {**result, "session": self.session, "snapshot": self.snapshot}
        except TimeoutError:
            raise HTTPException(504, "未收到 Studio 确认，设置可能已保存；请刷新检查后再操作")
        finally:
            self.pending.pop(command_id, None)


def install_studio_routes(app, authorize, send_token, read_token):
    relay = StudioRelay()

    @app.get("/v1/studio")
    async def studio(response: Response, authorization: str | None = Header(default=None)):
        authorize(authorization, read_token)
        response.headers["Cache-Control"] = "no-store"
        online = relay.online()
        return {"online": online, "session": relay.session if online else "",
                "snapshot": relay.snapshot if online else None}

    @app.post("/v1/studio/sync")
    async def sync(message: SyncInput, authorization: str | None = Header(default=None)):
        authorize(authorization, send_token)
        return relay.sync(message)

    @app.post("/v1/studio/commands")
    async def command(message: CommandInput, authorization: str | None = Header(default=None)):
        authorize(authorization, read_token)
        return await relay.command(message)
