import tempfile
import unittest
from pathlib import Path

from fastapi.testclient import TestClient

from app import create_app


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.database = Path(self.directory.name) / "test.db"
        self.sender = {"Authorization": "Bearer " + "s" * 32}
        self.receiver = {"Authorization": "Bearer " + "r" * 32}
        self.client = TestClient(create_app(self.database, "s" * 32, "r" * 32))
        self.message = {"id": "report-1", "title": "日报", "content": "<h1>你好</h1>"}

    def tearDown(self):
        self.client.close()
        self.directory.cleanup()

    def test_store_receive_acknowledge_and_retry(self):
        self.assertEqual(self.client.post("/v1/messages", headers=self.sender, json=self.message).status_code, 202)
        with self.client.websocket_connect("/v1/stream", headers=self.receiver) as socket:
            self.assertEqual(socket.receive_json()["ids"], ["report-1"])
            response = self.client.get("/v1/messages/report-1", headers=self.receiver)
            self.assertEqual(response.json()["content"], self.message["content"])
            self.client.post("/v1/receipts", headers=self.receiver, json={"ids": ["report-1"]})
            self.assertEqual(socket.receive_json()["ids"], [])
        self.assertEqual(self.client.get("/v1/messages/report-1", headers=self.receiver).status_code, 404)
        retry = self.client.post("/v1/messages", headers=self.sender, json=self.message)
        self.assertEqual(retry.json()["status"], "received")
        self.assertTrue(retry.json()["duplicate"])

    def test_scope_and_conflicting_retry(self):
        self.assertEqual(self.client.post("/v1/messages", headers=self.receiver, json=self.message).status_code, 401)
        self.client.post("/v1/messages", headers=self.sender, json=self.message)
        self.assertEqual(self.client.get("/v1/messages/report-1", headers=self.sender).status_code, 401)
        changed = {**self.message, "content": "different"}
        self.assertEqual(self.client.post("/v1/messages", headers=self.sender, json=changed).status_code, 409)

    def test_pending_survives_restart(self):
        self.client.post("/v1/messages", headers=self.sender, json=self.message)
        with TestClient(create_app(self.database, "s" * 32, "r" * 32)) as restarted:
            self.assertEqual(restarted.get("/v1/messages/report-1", headers=self.receiver).status_code, 200)

    def test_unicode_size_limit(self):
        oversized = {**self.message, "content": "字" * 333_334}
        self.assertEqual(self.client.post("/v1/messages", headers=self.sender, json=oversized).status_code, 422)


if __name__ == "__main__":
    unittest.main()
