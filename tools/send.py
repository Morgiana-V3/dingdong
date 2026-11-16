"""Send self-contained documents with idempotent retries and delivery receipts."""
import argparse
import base64
import html
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from html.parser import HTMLParser
from pathlib import Path


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        return None


def image_uri(source, directory, fetch_remote=False):
    if source.startswith("data:image/"):
        return source
    parsed = urllib.parse.urlparse(source)
    if parsed.scheme in ("http", "https"):
        if not fetch_remote:
            raise ValueError("外部图片需要 --fetch-images，或先下载到文档目录")
        with urllib.request.urlopen(source, timeout=20) as response:
            data = response.read(1_000_001)
    elif parsed.scheme:
        raise ValueError("不支持此图片地址协议")
    else:
        path = (directory / urllib.parse.unquote(parsed.path)).resolve()
        if not path.is_relative_to(directory.resolve()):
            raise ValueError("本地图片必须位于文档目录或子目录")
        with path.open("rb") as image:
            data = image.read(1_000_001)
    if len(data) > 1_000_000:
        raise ValueError("图片超过 1 MB，请先缩小或压缩")
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        mime = "image/png"
    elif data.startswith(b"\xff\xd8\xff"):
        mime = "image/jpeg"
    elif data[:6] in (b"GIF87a", b"GIF89a"):
        mime = "image/gif"
    elif data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        mime = "image/webp"
    else:
        raise ValueError("只支持 PNG、JPEG、GIF、WebP 图片")
    return "data:" + mime + ";base64," + base64.b64encode(data).decode("ascii")


class ImageInliner(HTMLParser):
    def __init__(self, directory, fetch_remote):
        super().__init__(convert_charrefs=False)
        self.directory = directory
        self.fetch_remote = fetch_remote
        self.parts = []

    def handle_starttag(self, tag, attrs):
        if tag in ("img", "source"):
            updated = []
            for name, value in attrs:
                if name == "srcset":
                    continue
                if tag == "img" and name == "src" and value:
                    value = image_uri(value, self.directory, self.fetch_remote)
                updated.append(name if value is None else name + '="' + html.escape(value, quote=True) + '"')
            self.parts.append("<" + tag + " " + " ".join(updated) + ">")
        else:
            self.parts.append(self.get_starttag_text())

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        self.parts.append("</" + tag + ">")

    def handle_data(self, data):
        self.parts.append(data)

    def handle_entityref(self, name):
        self.parts.append("&" + name + ";")

    def handle_charref(self, name):
        self.parts.append("&#" + name + ";")

    def handle_decl(self, declaration):
        self.parts.append("<!" + declaration + ">")

    def handle_comment(self, comment):
        self.parts.append("<!--" + comment + "-->")


def load_document(path, fetch_remote=False):
    path = Path(path)
    content = path.read_text(encoding="utf-8")
    document_format = {".html": "html", ".htm": "html", ".md": "markdown"}.get(path.suffix.lower(), "text")
    if document_format == "markdown":
        # Inline standard Markdown image destinations; reference-style images should be converted to HTML first.
        content = re.sub(r"!\[([^\]]*)\]\(([^\s)]+)\)",
            lambda match: "![" + match[1] + "](" + image_uri(match[2], path.parent, fetch_remote) + ")", content)
    if document_format in ("html", "markdown"):
        parser = ImageInliner(path.parent, fetch_remote)
        parser.feed(content)
        parser.close()
        content = "".join(parser.parts)
    if len(content.encode("utf-8")) > 1_000_000:
        raise ValueError("内嵌图片后的正文超过 1 MB，请减少图片或压缩图片")
    return document_format, content


def api_request(endpoint, token, path, payload=None, attempts=3):
    opener = urllib.request.build_opener(NoRedirect())
    encoded = None if payload is None else json.dumps(payload, ensure_ascii=False).encode("utf-8")
    for attempt in range(attempts):
        request = urllib.request.Request(endpoint.rstrip("/") + path, encoded, headers={
            "Authorization": "Bearer " + token, "Content-Type": "application/json"})
        try:
            with opener.open(request, timeout=20) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            if error.code not in (408, 429) and error.code < 500:
                raise ValueError(f"接口返回 HTTP {error.code}") from None
            if attempt == attempts - 1:
                raise ValueError(f"重试后接口仍返回 HTTP {error.code}") from None
        except (urllib.error.URLError, TimeoutError):
            if attempt == attempts - 1:
                raise ValueError("网络连接失败或超时") from None
        time.sleep(2 ** attempt)


def send_document(file, title, source="电脑脚本", summary="", message_id=None,
                  silent=False, fetch_remote=False, endpoint=None, token=None):
    endpoint = endpoint or os.environ.get("DINGDONG_URL", "")
    token = token or os.environ.get("DINGDONG_SEND_TOKEN", "")
    if not endpoint or not token:
        raise ValueError("请设置 DINGDONG_URL 和 DINGDONG_SEND_TOKEN")
    message_id = message_id or str(uuid.uuid4())
    document_format, content = load_document(file, fetch_remote)
    payload = {"id": message_id, "title": title, "summary": summary, "source": source,
               "content": content, "format": document_format, "priority": "silent" if silent else "normal"}
    try:
        return api_request(endpoint, token, "/v1/messages", payload)
    except ValueError as error:
        raise ValueError(f"{error}；重试请复用消息 ID：{message_id}") from None


def main():
    parser = argparse.ArgumentParser(description="发送消息或查询送达状态，图片自动内嵌")
    parser.add_argument("file", type=Path, nargs="?")
    parser.add_argument("--title")
    parser.add_argument("--source", default="电脑脚本")
    parser.add_argument("--summary", default="")
    parser.add_argument("--id", help="同一任务重试时复用此 ID")
    parser.add_argument("--silent", action="store_true")
    parser.add_argument("--fetch-images", action="store_true", help="允许下载 HTML/Markdown 中的外部图片")
    parser.add_argument("--status", metavar="ID", help="仅查询消息送达状态")
    parser.add_argument("--wait", type=float, default=0, metavar="SECONDS", help="等待手机确认落盘；超时退出码为 2")
    args = parser.parse_args()
    endpoint = os.environ.get("DINGDONG_URL", "").rstrip("/")
    token = os.environ.get("DINGDONG_SEND_TOKEN", "")
    if not endpoint or not token:
        parser.error("请设置 DINGDONG_URL 和 DINGDONG_SEND_TOKEN 环境变量")
    if args.wait < 0:
        parser.error("--wait 不能为负数")
    message_id = args.status or args.id or str(uuid.uuid4())
    if not re.fullmatch(r"[a-zA-Z0-9_.:-]{1,128}", message_id):
        parser.error("消息 ID 格式不正确")
    try:
        if args.status:
            result = api_request(endpoint, token, f"/v1/messages/{message_id}/status")
        else:
            if not args.file or not args.title:
                parser.error("发送时需要文件和 --title")
            result = send_document(args.file, args.title, args.source, args.summary,
                                   message_id, args.silent, args.fetch_images, endpoint, token)
        deadline = time.monotonic() + args.wait
        while args.wait > 0 and result.get("status") != "received" and time.monotonic() < deadline:
            time.sleep(min(1, max(0, deadline - time.monotonic())))
            result = api_request(endpoint, token, f"/v1/messages/{message_id}/status", attempts=1)
        print(json.dumps(result, ensure_ascii=False))
        if args.wait > 0 and result.get("status") != "received":
            raise SystemExit(2)
    except (ValueError, OSError) as error:
        raise SystemExit(f"发送/查询未完成：{error}；消息 ID：{message_id}") from None


if __name__ == "__main__":
    main()
