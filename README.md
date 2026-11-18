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
- **Studio 订阅管理**：手机通过同一服务器查看、新增、编辑、启停和删除 Studio 内置订阅，调整执行时间、兴趣规则、贴吧列表及汇总内容源。
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

## 外部 App 跳转与代理网络

阅读页中的 X、贴吧、小红书和 B 站内容链接会在确认后优先交给对应 App，未安装或无法处理时回退到网页。保留原帖 ID 与小红书分享参数，支持新窗口链接。页面脚本、任意 intent、文件和内容提供者地址仍不开放。

开启手机代理后若叮咚无法接收，可在「设置」开启「服务器直连」，再点「保存并连接」。这个选项只绑定叮咚服务器的 WebSocket、正文下载/确认和 Studio 控制连接；优先使用可用 Wi-Fi，其次移动网络，不修改系统代理或外部 App 的路由。默认关闭，旧配置继续跟随系统网络。切换网络或重新连接会重建 HTTP 客户端，避免残留连接池和代理路由。

若 VPN 禁止应用绕过，需在代理软件中将叮咚设为直连/排除应用，或关闭服务器直连选项。Android 的网络绑定受 VPN 策略约束，见 [Android VPN 文档](https://developer.android.com/develop/connectivity/vpn)。HTTP 健康检查和电脑发送成功不代表 WebSocket 握手成功；接收状态若显示 HTTP 404，应检查 `/v1/stream` 的 WebSocket Upgrade 转发，而不能只判断公网 IP 不可达。

服务器已配置可信 HTTPS 时，可在手机设置点击“改用 HTTPS 加密连接”再保存；消息接收将使用 WSS，正文和回执使用 HTTPS。同一主机从标准 HTTP 升级时无需重新填写密钥，历史消息与去重范围保持不变。此设置不会修改手机 VPN，也不会自动开启服务器直连。

## 从手机管理 Studio 订阅

### 服务器订阅：先任务，后账号

从「订阅管理」连接当前服务器，先查看任务列表。点击「添加任务」后选择服务器安装的插件，配置并开启任务，再到右侧「所需账号」完成任务需要的登录；没有已开启任务时，不展示独立登录入口。多个任务共用同一平台账号，暂停或删除任务后，相应账号需求自动移除，已保存登录态保留。

Node/Cordis 服务器已适配 Studio 的 B 站指定 UP 主、贴吧兴趣精选、X 兴趣发现、小红书兴趣发现和统一推送。任务支持手动、固定间隔和每天定点，AI 配置在右上角「更多」中管理。B 站可从关注列表选择 UP 主，首次执行建立基线，之后只推送新视频；旧版任务保持原配置。各平台真实可用性取决于服务器网络和账号验证。

App 沿用设置中保存的服务器地址和接收密钥。标准 HTTP 地址的订阅与账号请求自动使用同主机 HTTPS，不修改原消息命名空间；自定义端口须配置 HTTPS。平台密码在独立官方页面输入，用户授权后才上传会话。账号服务及任务运行在服务器，手机和电脑无需保持打开。

原电脑 Studio 的任务不自动迁移，从订阅管理右上角「更多 → 电脑 Studio 管理」进入。手机新建的服务器任务与原桌面任务分别保存。

设置中的接收密钥默认不回填；输入框为空时点击眼睛图标，可在禁止截屏的原生窗口查看已保存密钥。侧边栏的连接状态放在设置同一行右侧，绿色表示已连接，红色表示未连接，可查看具体连接原因。

### 现有桌面 Studio 遥控

1. 更新此仓库的服务器：在 `server/` 执行 `docker compose up -d --build`，保留原有数据卷和密钥。
2. 更新并启动 DingDong Studio，在「应用设置 → 允许手机管理订阅」选择叮咚渠道。该渠道的服务器须与手机设置一致；Studio 使用发送密钥，手机继续使用原有接收密钥。
3. 安装新版 App，从「订阅管理 → 更多 → 电脑 Studio 管理」进入。可新增、编辑、启停和删除 B 站、贴吧、X、小红书订阅及订阅汇总，选择已有 AI/推送渠道并调整时间与过滤规则。

平台登录、插件安装及密钥配置在电脑端完成；B 站订阅账号及 UP 主通过 UID 填写。自定义代码插件仍在电脑端管理。所有执行时间采用北京时间，手动任务在电脑执行或作为汇总内容源。

Studio 必须保持运行且电脑联网、未睡眠。手机与电脑无需处于同一局域网，也无需开放电脑端口。保存通常需要几秒，只有收到 Studio 确认才显示成功；离线不会排队等待开机执行。设置在其他位置变化时会拒绝覆盖，请返回列表刷新再编辑。超时可能代表确认丢失，先刷新检查结果再操作。

开启后，持有该服务器接收密钥的手机获得订阅管理权限；关闭电脑端开关即可停止处理控制请求。一个服务器同时支持一台 Studio；关闭或退出后，在线状态最多约 15 秒变为离线。订阅配置仅保存在中转服务内存中，不写入消息队列或数据库；平台 Cookie、发送密钥、AI 密钥和历史正文不上传。原有消息投递协议保持兼容。

## API

| 接口 | 凭据 | 用途 |
| --- | --- | --- |
| `GET /health` | 无 | 健康检查 |
| `POST /v1/messages` | 发送密钥 | 提交消息，返回 HTTP 202 |
| `GET /v1/messages/{id}/status` | 发送密钥 | 查询 `queued` / `received` |
| `GET /v1/messages/{id}` | 接收密钥 | 下载待接收正文 |
| `POST /v1/receipts` | 接收密钥 | 手机保存后确认接收 |
| `WS /v1/stream` | 接收密钥 | 接收待下载消息 ID 通知 |
| `GET /v1/studio` | 接收密钥 | 查看 Studio 在线状态与可编辑订阅 |
| `POST /v1/studio/commands` | 接收密钥 | 提交订阅修改并等待 Studio 确认 |
| `POST /v1/studio/sync` | 发送密钥 | Studio 同步订阅、取回命令和返回结果 |

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

## Studio 插件订阅（Node）

手机订阅管理以任务列表为入口，添加任务后选择服务器安装的插件，字段与 Studio 定义一致。服务端已适配 B 站指定 UP 主、贴吧兴趣精选、X 兴趣发现、小红书兴趣发现和统一推送；支持仅手动、固定间隔、北京时间定点、立即运行与停止。右侧账号需求来自已开启任务及汇总来源。任务缺少 UP 主、AI 或登录时分别提示等待配置，不以手机 Cookie 存在代替服务端验证。

选择菜单、时间日期与确认操作统一从底部打开。统一推送可选择已有任务，也可直接添加内容源、选择插件并配置；新来源默认暂停，保存后自动选入当前汇总。取消汇总编辑不会删除已保存的来源。旧版 B 站任务可作为汇总来源；已经被其他启用汇总占用的来源不可重复选择。

账号平台按 bilibili/x/xiaohongshu 隔离，复用当前服务器 HTTPS 与接收凭据；独立官方登录页只上传当前平台必要会话。B 站可读取关注列表选择 UP 主；X、小红书同时提供通过 SSH 访问服务器浏览器的备用登录入口。AI 配置在订阅管理「更多」中，加密保存在服务器。Node 运行时、投递进度与实际验证范围见 ../dingdong-node/README.md。
