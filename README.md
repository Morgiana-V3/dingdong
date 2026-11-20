# 叮咚 · Dingdong

一个可自部署的 Android 推送收件箱与插件化内容引擎。电脑脚本或自定义服务端插件通过 HTTP API 发送 HTML、Markdown 或纯文本，手机接收后离线保存与阅读。

当前版本 **0.2.0**（MIT 开源）。客户端使用 Flutter 和 Kotlin；服务端由极简消息中转（FastAPI + SQLite）与可选插件引擎（Node.js + Cordis）组成，两套服务均支持 Docker Compose 部署。

## 两种使用模式

1. **纯净模式（App + Relay，推荐大多数用户）**
   只部署轻量的 `services/relay/`。任何语言、脚本、Cron、n8n 或 GitHub Actions 只要调用 `POST /v1/messages` 即可推送完全自定义的 HTML（含内联 CSS 与内嵌图片）、Markdown 或纯文本。手机 App 开箱即用，收件箱功能完全独立于插件引擎。
2. **插件引擎模式（App + Relay + Engine，可选）**
   额外部署 `services/engine/`（基于 Koishi 同源的 Cordis 插件内核，无 Playwright 依赖，镜像轻量）。将自定义插件放入 `plugins/` 目录即可自动加载调度，手机 App 与 Web 管理台按插件声明的 Schema 自动生成配置表单与登录入口，并支持统一 AI 配置与汇总推送。

## 核心功能

- **自定义正文**：保留 HTML 内联 CSS，支持表格、卡片和内嵌图片；同时支持 Markdown 与纯文本；阅读页禁用脚本与外链资源。
- **离线收件箱**：全文搜索、日期与来源筛选、未读、收藏、来源静默、批量操作、删除撤销、JSON 本地备份导出与合并导入。
- **图片预览**：全屏查看、双指缩放、左右切换与保存原图。
- **后台接收**：Android 常驻前台服务与 WebSocket 长连接，断线重连、离线补收、落盘确认后清除服务器正文、幂等去重。
- **通用 App 配置**：App 内填写服务器地址与接收密钥，更换服务器无需重新编译；支持服务器直连与连接诊断。
- **AI 友好的插件生态**：参考 Koishi 的 Cordis 插件机制，提供 [插件开发指南](docs/PLUGIN_GUIDE.md)、`dingdong-engine/sdk` 统一 TypeScript SDK、`npm run plugin:create` 一键脚手架与 `npm run plugin:test` 校验工具，可直接让 AI 编程助手帮你编写自定义推送插件。
- **通用声明式凭据（`web-cookie` / `token`）**：需要网站登录态的自定义插件只需声明 `auth` 元数据，手机 App 即可在独立隔离 WebView 中完成登录并通过一次性配对码安全回传给服务端，零平台硬编码。

## 工作方式

```text
任意脚本 / Engine 插件 ── HTTP POST /v1/messages ──> services/relay（暂存未送达消息）
                                                         │
                                                   WebSocket 通知
                                                         ↓
                                                 Android 下载并保存 SQLite
                                                         │
                                                    返回接收确认
                                                         ↓
                                                 服务器清除正文，保留去重记录
```

`queued` 表示服务器已收下；`received` 表示手机已落盘。**手机是历史消息的主要存储位置**，换机或清空数据前请在 App 设置中导出备份。

## 快速开始

### 1. 部署核心消息中转（`services/relay`）

```sh
cd services/relay
cp .env.example .env
```

运行两次下面的命令生成两个不同的随机密钥（至少 32 字符）：

```sh
python3 -c 'import secrets; print(secrets.token_urlsafe(36))'
```

写入 `.env`：

```dotenv
DINGDONG_SEND_TOKEN=替换为随机发送密钥
DINGDONG_READ_TOKEN=替换为另一个随机接收密钥
DINGDONG_BIND=0.0.0.0
DINGDONG_PORT=8080
```

启动服务：

```sh
chmod 600 .env
docker compose up -d --build
curl http://127.0.0.1:8080/health
```

公网长期使用建议通过 Nginx 配置 HTTPS 反向代理（需支持 `/v1/stream` 的 WebSocket Upgrade）。

### 2. 安装并配置 App

需要 Flutter SDK、Android SDK 和 JDK 17（支持 Android 8.0 / API 26 及以上）：

```sh
cd mobile
flutter pub get
flutter build apk --debug
```

正式发布签名可通过 `mobile/android/key.properties` 或环境变量 `DINGDONG_KEYSTORE_PATH` / `DINGDONG_KEYSTORE_PASSWORD` / `DINGDONG_KEY_ALIAS` / `DINGDONG_KEY_PASSWORD` 配置。

打开 App，进入「设置 → 服务器连接」，填入服务器地址和 `DINGDONG_READ_TOKEN` 即可开始接收。

### 3. 从电脑或任意脚本发送自定义内容

仓库自带零第三方依赖的 Python 发送工具：

```powershell
$env:DINGDONG_URL = 'http://服务器IP:8080'
$env:DINGDONG_SEND_TOKEN = '你的发送密钥'
python tools/send.py examples/report.html --title "HTML 报告" --source "电脑脚本" --wait 30
```

也可以直接向 `POST /v1/messages` 发送 JSON（Header：`Authorization: Bearer <DINGDONG_SEND_TOKEN>`）：

```json
{
  "id": "report-001",
  "source": "监控脚本",
  "title": "每日巡检",
  "summary": "所有服务运行正常",
  "format": "markdown",
  "content": "## 巡检结果\n\n- API: 正常\n- 数据库: 正常",
  "priority": "normal"
}
```

### 4. 可选：部署插件引擎（`services/engine`）

如果你希望服务器按计划自动运行自定义插件（如 RSS 监控、AI 网页摘要等）：

```sh
cd services/engine
cp .env.example .env
# 填入与 relay 相同的 DINGDONG_SEND_TOKEN / DINGDONG_READ_TOKEN
docker compose up -d --build
```

参考 [nginx.conf.template](services/engine/deploy/nginx.conf.template) 将 HTTPS 的 `/v1/engine/` 转发到 `127.0.0.1:18890`，App 即可自动识别并开启「订阅管理」。

编写自定义插件请阅读 [插件开发指南](docs/PLUGIN_GUIDE.md)，或直接参考内置于 `services/engine/plugins/` 的官方参考插件：
- [services/engine/plugins/bilibili-feed](services/engine/plugins/bilibili-feed/README.md)（完整多文件示范：手机网页登录回传 Cookie + 远程关注 UP 主搜索多选 + 双 AI 模型过滤与总结 + 分组表单 + HTML/SVG 模板）
- [services/engine/plugins/rss-watch](services/engine/plugins/rss-watch/index.ts)（单文件极简示范：纯 HTTP + 游标去重）
- [services/engine/plugins/ai-web-digest](services/engine/plugins/ai-web-digest/index.ts)（单文件极简示范：网页抓取 + AI 筛选摘要）

## 核心 API

| 接口 | 服务 | 凭据 | 用途 |
| --- | --- | --- | --- |
| `GET /health` | Relay | 无 | 健康检查 |
| `POST /v1/messages` | Relay | 发送密钥 | 提交消息，返回 HTTP 202 |
| `GET /v1/messages/{id}/status` | Relay | 发送密钥 | 查询 `queued` / `received` |
| `GET /v1/messages/{id}` | Relay | 接收密钥 | 下载待接收正文 |
| `POST /v1/receipts` | Relay | 接收密钥 | 手机落盘后确认接收 |
| `WS /v1/stream` | Relay | 接收密钥 | 接收待下载消息 ID 通知 |
| `GET /v1/engine/health` | Engine | 无 | 探测插件引擎是否启用 |
| `GET /v1/engine/snapshot` | Engine | 接收密钥 | 读取插件、任务、AI 与所需凭据快照 |
| `POST /v1/engine/commands` | Engine | 接收密钥 | 增删改启停任务与 AI 配置（带版本冲突校验） |
| `POST /v1/engine/credentials/{id}/*` | Engine | 接收密钥 / 配对码 | 通用凭据配对、加密导入、验证与清除 |

## 项目结构

```text
mobile/                 Flutter 页面与 Kotlin Android 原生实现
services/
  relay/                FastAPI 极简消息中转（可单独部署）
  engine/               Node + Cordis 可选插件引擎、SDK、内置插件、Web 管理台与 CLI
examples/               HTML 示例文档与模板输入 JSON
tools/                  零依赖 Python 发送工具与模板渲染器
docs/                   插件开发指南、部署、发送、架构与开发文档
```

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。
