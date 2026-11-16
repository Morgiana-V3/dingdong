# 脚本发送与模板

发送工具只依赖 Python 标准库。服务器地址放在 `DINGDONG_URL`，发送密钥放在 `DINGDONG_SEND_TOKEN` 环境变量中；不要写进脚本或 Git。

## 发送并等待送达

```powershell
python tools/send.py examples/report.html --title "HTML 报告" --source "电脑脚本" --id "report-example-001" --wait 30
```

工具自动将 HTML 的 `img src` 本地图片，以及常规 Markdown `![说明](相对路径)` 图片转换为 data URI。图片必须位于文档目录或子目录，支持 PNG、JPEG、GIF、WebP；生成后的正文上限 1 MB。Markdown 引用式图片、带复杂标题的图片语法与 CSS 背景图片请先转成自包含 HTML。允许下载外部图片时显式加 `--fetch-images`。

同一轮重试使用相同消息 ID 和内容。网络失败及 HTTP 408、429、5xx 最多尝试三次；认证失败不重试，也不会跟随服务端重定向转发密钥。`--silent` 表示保存但不弹出新消息通知。

成功响应的 `queued` 仅表示服务器收下；`received` 表示手机已经保存正文。`--wait` 以指定秒数为轮询等待预算，单次网络请求另有 20 秒超时；等待结束仍未送达返回退出码 2，普通失败返回非零退出码。

```powershell
python tools/send.py --status "report-example-001"
python tools/send.py --status "report-example-001" --wait 60
```

也可以在自己的 Python 脚本中导入 `tools/send.py` 的 `send_document` 函数，传入文件、标题、来源、摘要和稳定的 `message_id`。返回值是服务器的 JSON 响应，不包含消息正文或凭据。

## 模板

```powershell
python tools/render.py alert examples/templates/alert.json examples/alert.html
python tools/render.py daily examples/templates/daily.json examples/daily.html
python tools/render.py posts examples/templates/posts.json examples/posts.html
```

- `alert`：监控项、值和说明。
- `daily`：分段工作记录。
- `posts`：作者、账号、正文、配图和原文链接。

修改对应 JSON 的 `title` 和 `items` 即可。`image` 相对于生成后的 HTML 文件；`url` 只接受 HTTP/HTTPS。文字按 HTML 转义，采集来的内容不会变成脚本。示例数据明确标注为演示，不会自动发送。

仓库只保留模板输入，生成的 HTML 不提交 Git。图文模板不依赖演示照片；使用自己的图片时，把图片放到输出 HTML 的同目录或子目录，并在对应条目加入 `"image": "photo.jpg"`。然后运行发送命令，工具会将其内嵌：

```powershell
python tools/send.py examples/posts.html --title "帖子汇总" --source "采集脚本" --wait 30
```

## 手机端

- 点击正文中的内嵌图片全屏查看；双指缩放、原始比例下左右换图，双击切换缩放。右上角保存图片。Android 10 及以上保存到相册的 `Pictures/Dingdong`；旧系统使用文件选择器。
- 搜索栏检索标题、来源、摘要和正文，命中正文时显示片段；右侧日期按钮按接收日期筛选。来源筛选从侧边栏的“来源”进入。
- 长按消息进入多选，可批量已读、收藏、取消收藏、删除；右上菜单可将当前列表全部标为已读。删除后有 8 秒撤销入口，正文在 10 秒窗口结束后清理，保留去重标记。
- 设置中导出和导入 JSON 备份。备份含正文、内嵌图片、已读、收藏和来源静默设置，不含连接密钥。支持旧版 v1 备份和新版 v2；导入合并消息，重复 ID 跳过，不覆盖已保存内容或恢复已经删除的消息。无效备份整体回滚。
- 设置中的连接检查区分地址、网络、证书、密钥和服务端响应问题，并显示最近连接成功时间。已开启接收时尝试在开机、应用更新和重新打开后恢复服务；系统强行停止或限制后台时仍需用户允许运行。
