"""Render alert, daily report and collected-post HTML templates from JSON."""
import argparse
import html
import json
from pathlib import Path


def escape(value):
    return html.escape(str(value), quote=True)


def render(template, data):
    title = escape(data.get("title", {"alert": "监控告警", "daily": "工作日报", "posts": "帖子汇总"}[template]))
    sections = []
    for item in data.get("items", []):
        image = item.get("image")
        photo = '<img alt="配图" src="' + escape(image) + '">' if image else ""
        if template == "alert":
            body = f'<h2>{escape(item.get("name", "监控项"))}</h2><strong>{escape(item.get("value", ""))}</strong>'
            body += f'<p>{escape(item.get("detail", ""))}</p>'
        elif template == "daily":
            body = f'<h2>{escape(item.get("heading", "记录"))}</h2><p>{escape(item.get("text", ""))}</p>'
        else:
            body = f'<h2>{escape(item.get("author", "作者"))}</h2><small>{escape(item.get("handle", ""))}</small>'
            body += f'<p>{escape(item.get("text", ""))}</p>'
        url = item.get("url", "")
        link = f'<a href="{escape(url)}">查看原文</a>' if url.startswith(("https://", "http://")) else ""
        sections.append(f'<section>{body}{photo}{link}</section>')
    return f'''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title}</title><style>
body {{ margin:0; padding:24px 18px 40px; color:#242830; background:#f3f4f6; font:16px/1.75 sans-serif; }}
main {{ max-width:720px; margin:auto; }} h1 {{ font-size:27px; line-height:1.35; margin:8px 0 24px; }}
section {{ background:#fff; padding:20px; border-radius:18px; margin:14px 0; overflow:hidden; }}
h2 {{ font-size:18px; margin:0 0 6px; }} p {{ white-space:pre-wrap; overflow-wrap:anywhere; }}
strong {{ color:#c65239; font-size:24px; }} small {{ color:#697380; }}
img {{ display:block; width:100%; height:auto; border-radius:10px; margin:14px 0; }} a {{ color:#c65239; }}
</style></head><body><main><h1>{title}</h1>{''.join(sections)}</main></body></html>'''


def main():
    parser = argparse.ArgumentParser(description="从 JSON 生成 HTML 推送模板")
    parser.add_argument("template", choices=["alert", "daily", "posts"])
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    data = json.loads(args.input.read_text(encoding="utf-8"))
    args.output.write_text(render(args.template, data), encoding="utf-8")


if __name__ == "__main__":
    main()
