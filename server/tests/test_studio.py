import asyncio
import tempfile
import unittest
from pathlib import Path

import httpx
from fastapi import HTTPException

from app import create_app
from studio import CommandInput, StudioRelay, SyncInput


class StudioTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.directory = tempfile.TemporaryDirectory()
        app = create_app(Path(self.directory.name) / "inbox.db", "s" * 32, "r" * 32)
        self.client = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test")
        self.sender = {"Authorization": "Bearer " + "s" * 32}
        self.receiver = {"Authorization": "Bearer " + "r" * 32}
        self.sync = {"session": "studio-one", "snapshot": {"revision": "version-one", "tasks": []}}
        self.command = {"session": "studio-one", "revision": "version-one",
                        "action": "setEnabled", "payload": {"id": "task-one", "enabled": False}}

    async def asyncTearDown(self):
        await self.client.aclose()
        self.directory.cleanup()

    async def test_permissions_offline_and_allowlist(self):
        response = await self.client.get("/v1/studio", headers=self.receiver)
        self.assertFalse(response.json()["online"])
        self.assertEqual((await self.client.get("/v1/studio", headers=self.sender)).status_code, 401)
        self.assertEqual((await self.client.post("/v1/studio/sync", headers=self.receiver, json=self.sync)).status_code, 401)
        self.assertEqual((await self.client.post("/v1/studio/commands", headers=self.receiver, json=self.command)).status_code, 503)
        self.assertEqual((await self.client.post("/v1/studio/commands", headers=self.receiver,
            json={**self.command, "action": "saveProvider"})).status_code, 422)

    async def test_edit_waits_for_studio_confirmation_and_returns_new_snapshot(self):
        await self.client.post("/v1/studio/sync", headers=self.sender, json=self.sync)
        edit = asyncio.create_task(self.client.post("/v1/studio/commands", headers=self.receiver, json=self.command))
        for _ in range(100):
            await asyncio.sleep(0.01)
            response = await self.client.post("/v1/studio/sync", headers=self.sender, json=self.sync)
            commands = response.json()["commands"]
            if commands:
                break
        self.assertEqual(len(commands), 1)
        self.assertFalse(edit.done())
        self.assertEqual(commands[0]["payload"], self.command["payload"])
        # A lost polling response never causes duplicate execution.
        repeat = await self.client.post("/v1/studio/sync", headers=self.sender, json=self.sync)
        self.assertEqual(repeat.json()["commands"], [])
        updated = {**self.sync, "snapshot": {"revision": "version-two", "tasks": [{"id": "task-one", "enabled": False}]},
                   "results": [{"id": commands[0]["id"], "ok": True}]}
        await self.client.post("/v1/studio/sync", headers=self.sender, json=updated)
        confirmed = await asyncio.wait_for(edit, 2)
        self.assertTrue(confirmed.json()["ok"])
        self.assertEqual(confirmed.json()["snapshot"], updated["snapshot"])
        conflict = await self.client.post("/v1/studio/commands", headers=self.receiver, json=self.command)
        self.assertEqual(conflict.status_code, 409)

    async def test_second_studio_cannot_take_over_live_connection(self):
        await self.client.post("/v1/studio/sync", headers=self.sender, json=self.sync)
        response = await self.client.post("/v1/studio/sync", headers=self.sender, json={**self.sync, "session": "other"})
        self.assertEqual(response.status_code, 409)
        stale = await self.client.post("/v1/studio/commands", headers=self.receiver, json={**self.command, "session": "other"})
        self.assertEqual(stale.status_code, 409)

    async def test_timeout_is_removed_and_never_replayed_on_reconnect(self):
        relay = StudioRelay(command_timeout=0.02)
        relay.sync(SyncInput(**self.sync))
        with self.assertRaises(HTTPException) as failure:
            await relay.command(CommandInput(**self.command))
        self.assertEqual(failure.exception.status_code, 504)
        self.assertEqual(relay.pending, {})
        self.assertEqual(relay.sync(SyncInput(**self.sync))["commands"], [])
        relay.seen -= 16
        self.assertFalse(relay.online())
        relay.sync(SyncInput(**{**self.sync, "session": "replacement"}))
        self.assertEqual(relay.session, "replacement")

    async def test_request_size_is_bounded(self):
        response = await self.client.post("/v1/studio/sync", headers=self.sender,
            json={**self.sync, "snapshot": {"text": "x" * 2_000_000}})
        self.assertEqual(response.status_code, 413)
