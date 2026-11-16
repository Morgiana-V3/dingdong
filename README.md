# 叮咚 · Dingdong

一个可自部署的 Android 推送收件箱。电脑脚本通过 HTTP API 发送 HTML、Markdown 或纯文本，手机接收后离线保存和阅读。

当前版本：**0.1.0**。客户端使用 Flutter 和 Kotlin，服务器使用 FastAPI 和 SQLite，通过 Docker Compose 部署。无需另外安装数据库。

## 功能

- **自定义正文**：保留 HTML 内联 CSS，支持表格、卡片和内嵌图片；也可发送 Markdown 和纯文本。
- **消息管理**：全文搜索、日期与来源筛选、未读、收藏、来源静默、批量操作、删除撤销。
- **图片预览**：全屏查看、双指缩放、左右切换和保存原图。
- **本地备份**：JSON 导出与合并导入，包含正文、内嵌图片、已读、收藏和来源静默设置。
- **后台接收**：Android 常驻通知与 WebSocket，断线重连、离线补收、落盘确认和幂等去重。
- **服务器配置**：App 内填写 IP、域名及端口，更换服务器无需重新编译；提供连接诊断。
- **脚本工具**：自动内嵌图片、失败重试、查询送达状态，以及告警、日报、帖子汇总模板。

帖子在 HTML 和图片首帧准备完成后从右侧滑入，避免先展示空白阅读页。准备较慢时保留收件箱画面并提供取消操作。

## 工作方式

```text
本地脚本 ── HTTP API ──> Docker 服务器（暂存未送达消息）
                               │
                         WebSocket 通知
                               ↓
                       Android 下载并保存到 SQLite
                               │
                          返回接收确认
                               ↓
                       服务器清除正文，保留去重记录
```

`queued` 表示服务器已经收下；`received` 表示手机已经保存。**手机是历史消息的主要存储位置**：卸载、清空数据或换机前，请在 App 设置中导出备份。

## 快速开始

### 1. 部署服务器

服务器需要 Docker Engine、Docker Compose 和一个手机可访问的 TCP 端口。以下命令在 Linux 服务器执行：

```sh
git clone git@github.com:Morgiana-V3/dingdong.git
cd dingdong/server
cp .env.example .env
```

如果服务器没有 GitHub SSH 凭据，也可以使用 `https://github.com/Morgiana-V3/dingdong.git`，或单独复制 `server/` 目录。

分别运行两次下面的命令，生成两个不同的随机密钥：

```sh
python3 -c 'import secrets; print(secrets.token_urlsafe(36))'
```

编辑 `.env`：

```dotenv
DINGDONG_SEND_TOKEN=替换为随机发送密钥
DINGDONG_READ_TOKEN=替换为另一个随机接收密钥
DINGDONG_BIND=0.0.0.0
DINGDONG_PORT=8080
```

发送密钥仅供脚本使用，接收密钥仅供手机使用；两者必须不同，且各不少于 32 个字符。

```sh
chmod 600 .env
docker compose up -d --build
docker compose ps
curl http://127.0.0.1:8080/health
```

健康响应为 `{"service":"dingdong","version":"0.1.0"}`。在服务器防火墙或云安全组放行所选端口，手机使用 `http://服务器IP:8080` 连接。

`.env.example` 默认仅监听 `127.0.0.1`。上面的 `0.0.0.0` 用于直接对外提供服务；使用 HTTPS 反向代理时保留本机监听，由代理提供公网入口，并支持 WebSocket Upgrade。HTTP 可以使用，但不会加密传输密钥和正文，公网长期使用建议配置 HTTPS。

服务默认使用持久化命名卷保存 SQLite 数据，更新容器不会清空消息队列。不要使用 `docker compose down -v` 删除数据卷。镜像导出、迁移服务器及数据卷备份见 [部署与迁移](docs/deployment.md)。

### 2. 构建并安装 App

需要 Flutter SDK、Android SDK 和 JDK 17。已验证环境为 Flutter 3.41.5 / Dart 3.11.3；App 支持 Android 8.0（API 26）及以上版本。回到仓库根目录后执行：

```sh
cd mobile
flutter pub get
flutter build apk --debug
```

APK 输出到 `mobile/build/app/outputs/flutter-apk/app-debug.apk`，可用 ADB 安装：

```sh
adb -s 设备序列号 install -r build/app/outputs/flutter-apk/app-debug.apk
```

此命令构建调试包，使用本机调试签名。正式分发前需要自行配置发布签名；当前 Android release 构建配置也使用调试签名，不应视为已经配置正式签名。

打开 App，进入左侧菜单的“设置”：

1. 填写服务器地址，例如 `http://服务器IP:8080` 或 `https://你的域名`。
2. 填写 `DINGDONG_READ_TOKEN` 对应的接收密钥，保存并连接。
3. 允许通知和后台运行。小米/HyperOS 中将省电策略设为“不限制”，并允许自启动。

已启用接收时，App 会尝试在开机、更新及重新打开后恢复服务。强行停止、系统省电限制和禁用后台运行仍可能中断接收，不能等同于厂商推送通道。

### 3. 从电脑发送

在仓库根目录执行。发送工具只使用 Python 标准库：

```powershell
$env:DINGDONG_URL = 'http://服务器IP:8080'
$env:DINGDONG_SEND_TOKEN = '你的发送密钥'
python tools/send.py examples/report.html --title "HTML 报告" --source "电脑脚本" --wait 30
```

Linux / macOS 可使用 `export DINGDONG_URL=...` 和 `export DINGDONG_SEND_TOKEN=...` 设置环境变量，再运行相同的 Python 命令。

工具会将文档目录内的本地图片转为 data URI。跨进程重试时传入稳定的 `--id`，并保持内容相同；同一 ID 的不同内容会被拒绝。发送命令的 `--wait` 用于等待手机接收确认，不是只检查服务器是否接受请求。

模板生成、静默消息、状态查询及图片路径规则见 [脚本发送与模板](docs/sending.md)。仓库包含演示模板，不包含真实社交平台采集器或自动采集任务。

## API

| 接口 | 凭据 | 用途 |
| --- | --- | --- |
| `GET /health` | 无 | 健康检查 |
| `POST /v1/messages` | 发送密钥 | 提交消息，返回 HTTP 202 |
| `GET /v1/messages/{id}/status` | 发送密钥 | 查询 `queued` / `received` |
| `GET /v1/messages/{id}` | 接收密钥 | 下载待接收正文 |
| `POST /v1/receipts` | 接收密钥 | 手机保存后确认接收 |
| `WS /v1/stream` | 接收密钥 | 接收待下载消息 ID 通知 |

认证使用 `Authorization: Bearer <密钥>`。发送正文示例：

```json
{
  "id": "report-001",
  "source": "电脑脚本",
  "title": "运行结果",
  "summary": "任务已完成",
  "format": "html",
  "content": "<h1>运行结果</h1><p>任务已完成。</p>",
  "priority": "normal"
}
```

`format` 可选 `html`、`markdown`、`text`；`priority` 可选 `normal`、`silent`。HTML 正文按 UTF-8 编码最多 1,000,000 字节，单次 HTTP 请求最多 2,000,000 字节。内嵌图片编码也计入正文大小。

## 使用边界

- 单用户、单接收手机、单服务实例；不要直接启动多个 worker 或容器副本共享当前接收逻辑。
- 保留静态 HTML/CSS，关闭 JavaScript；外部图片、外部样式、iframe 和表单提交不可用。图文内容应先转换为自包含文档。
- 当前没有独立附件上传、多端同步、用户账号系统和厂商推送。
- 接收密钥通过 Android Keystore 加密保存；备份不包含连接密钥。
- 服务器收到确认后清除正文，不能用服务器重新下载已经确认的历史消息。

## 项目结构

```text
mobile/                 Flutter 页面与 Kotlin Android 实现
  lib/                  收件箱、阅读、图库、设置
  android/              后台服务、SQLite、备份与原生首帧同步
  test/                 Flutter 正式回归测试
  integration_test/     独立设备收发集成测试
server/                 FastAPI 服务与 Docker 部署文件
  Dockerfile
  compose.yaml
  .env.example          空白配置模板，不含真实密钥
  tests/                接口与投递回归测试
tools/                  发送工具与模板生成器
  tests/                发送工具回归测试
  testing/              独立设备测试配套工具
examples/               最小 HTML 示例及模板输入
docs/                   部署、发送、架构和开发说明
```

构建缓存、APK、数据库、真实配置、密钥、截图、现场联调记录和个人 IDE 配置不提交仓库。正式回归测试保留，生成的模板 HTML 可随时重建。

## 开发与验证

本次版本已通过 Flutter 静态分析、14 项 Flutter 测试、6 项 Android 测试、5 项发送工具测试、4 项服务端测试以及 Android Lint 和调试构建。真机检查包括 HTML 首帧准备后滑入、返回和再次打开；不代表已验证所有 WebView 版本或整夜后台稳定性。

运行命令与独立设备测试说明见 [开发与验证](docs/development.md)。架构、存储及接收确认机制见 [技术方案](docs/architecture.md)。
