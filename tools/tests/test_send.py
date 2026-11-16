import base64
import io
import json
import sys
import tempfile
import unittest
import urllib.error
from pathlib import Path
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import send
import render


class SenderTests(unittest.TestCase):
    def test_local_images_are_embedded_without_changing_css(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "photo.png").write_bytes(b"\x89PNG\r\n\x1a\nexample")
            document = root / "report.html"
            document.write_text('<style>p{color:red}</style><p>文字 &amp; HTML</p><img src="photo.png">', encoding="utf-8")
            format_name, content = send.load_document(document)
            self.assertEqual(format_name, "html")
            self.assertIn("data:image/png;base64,", content)
            self.assertIn("p{color:red}", content)
            self.assertIn("&amp;", content)

    def test_image_paths_cannot_escape_document_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(ValueError):
                send.image_uri("../private.png", Path(directory))
            with self.assertRaises(ValueError):
                send.image_uri("https://example.com/photo.jpg", Path(directory))

    def test_payload_size_is_checked_after_embedding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "photo.png").write_bytes(b"\x89PNG\r\n\x1a\n" + b"a" * 800000)
            path = root / "report.html"
            path.write_text('<img src="photo.png">', encoding="utf-8")
            with self.assertRaises(ValueError):
                send.load_document(path)

    def test_retry_reuses_exact_payload_and_unauthorized_is_not_retried(self):
        opener = Mock()
        opener.open.side_effect = [urllib.error.HTTPError("http://localhost", 503, "unavailable", {}, None),
                                  io.BytesIO(b'{"id":"same","status":"queued"}')]
        with patch.object(send.urllib.request, "build_opener", return_value=opener), patch.object(send.time, "sleep"):
            result = send.api_request("http://localhost", "test-credential", "/v1/messages", {"id": "same"})
            self.assertEqual(result["status"], "queued")
            self.assertEqual(opener.open.call_args_list[0].args[0].data, opener.open.call_args_list[1].args[0].data)
        opener.reset_mock()
        opener.open.side_effect = urllib.error.HTTPError("http://localhost", 401, "unauthorized", {}, None)
        with patch.object(send.urllib.request, "build_opener", return_value=opener):
            with self.assertRaises(ValueError):
                send.api_request("http://localhost", "test-credential", "/v1/messages/id/status")
        self.assertEqual(opener.open.call_count, 1)

    def test_templates_escape_collected_content(self):
        for template in ("alert", "daily", "posts"):
            document = render.render(template, {"title": "<script>bad</script>", "items": [
                {"name": "<unsafe>", "heading": "<unsafe>", "author": "<unsafe>", "text": "<script>bad</script>", "url": "javascript:alert(1)"}]})
            self.assertNotIn("<script>", document)
            self.assertNotIn("javascript:", document)
            self.assertIn("&lt;script&gt;", document)


if __name__ == "__main__":
    unittest.main()
