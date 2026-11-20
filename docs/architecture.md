# 技术方案

## 1. 发送与投递链路（核心：`services/relay` ↔ `mobile/`）

电脑脚本或插件引擎 → `POST /v1/messages` → Relay SQLite 暂存 → WebSocket 通知 ID → 手机 HTTP 下载正文 → 本地 SQLite 提交 → 手机确认回执 → Relay 清除正文并保留去重记录。

- API 接收成功返回 `202`（`queued`）；手机落盘确认后为 `received`。`received` 表示手机已持久化保存，不表示用户已读。
- Relay 保留消息 ID、内容指纹、创建与确认时间，防止重试复活已接收消息；不保存已确认正文。未确认队列上限 10,000 条或 256 MB，超限返回 `507`。
- 单用户、单接收手机、单 worker 部署；发送密钥（`DINGDONG_SEND_TOKEN`）与接收密钥（`DINGDONG_READ_TOKEN`）严格隔离。

| 路径 | 凭据 | 用途 |
| --- | --- | --- |
| `GET /health` | 无 | 健康检查 |
| `POST /v1/messages` | 发送密钥 | 提交消息（重复 ID 同内容幂等，异内容 409） |
| `GET /v1/messages/{id}/status` | 发送密钥 | 查询 `queued` / `received` |
| `WS /v1/stream` | 接收密钥 | 推送待下载 ID 列表，15 秒补发未确认 ID |
| `GET /v1/messages/{id}` | 接收密钥 | 下载待接收正文 |
| `POST /v1/receipts` | 接收密钥 | 落盘确认并清理服务器正文 |

## 2. Android 客户端（`mobile/`）

- **职责分离**：Flutter 负责界面与阅读交互；Kotlin 前台服务（`remoteMessaging`）负责 OkHttp WebSocket、下载、SQLite 持久化、本地 JSON 备份与系统通知。断线指数退避 2–60 秒，网络恢复触发重连。
- **HTML 安全沙箱**：独立 WebView 渲染正文，保留作者内联 CSS，禁用 JavaScript 与页面可访问的原生 JS 桥；清除 `script / iframe / object / embed / base / link / meta[http-equiv]` 并注入严格 CSP，仅允许内嵌 `data:` 图片/字体/媒体。
- **首帧同步转场**：通过 `ReaderFrameBridge` 与 Android `postVisualStateCallback` 等待首帧真实绘制完成后再从右侧滑入，支持取消与系统减少动态效果设置。
- **服务器直连**：可选开启 `RelayNetwork` 物理网络绑定（`INTERNET` + `NOT_VPN`），仅作用于叮咚专用 OkHttp 客户端，不修改进程或其他 App 路由。
- **引擎能力解耦**：收件箱与「订阅管理」独立工作；未部署插件引擎时「订阅管理」提示当前服务器未启用插件引擎，不影响收件箱收发。

## 3. 可选插件引擎（`services/engine/`）

基于 `@cordisjs/core` 插件内核与 Node.js 22 原生 TypeScript 构建，轻量无浏览器依赖：

- **动态插件加载**：启动时扫描 `PLUGINS_DIR`（默认 `./plugins`，Docker 挂载 `/app/plugins`）自动识别 `*/src/index.ts` 与 `*/index.ts`（兼容 `.mts / .mjs / .js`），单个插件出错自动隔离。
- **宿主能力注入（`ctx` / `job`）**：
  - `ctx.source.register(def)`：注册内容源、通用表单原语（`text / textarea / number / boolean / select / stringList / secret / aiProvider / remoteMultiSelect / tasks`）、分组卡片（`group` / `groupDescription`）、条件显隐（`when`）、远程动态选项处理器（`optionsHandlers`）及可选 `auth` 声明。
  - `ctx.http`：统一超时、代理与取消信号。
  - `job.ai` & `aiProvider`：复用 AES-256-GCM 加密保存的 AI 服务商配置，插件可按需声明一个或多个模型字段，既可直接调用 `generate / json`，也可读取 `ai.config` 自行发起定制请求。
  - `job.state` + Outbox 原子投递：投递前原子落盘待发消息，确认 Relay 接收后再提交新 `state`；失败或重启复用原消息 ID 与正文重试；去重逻辑由各插件通过 `job.state` 自主掌控。
  - 渲染与预览：提供 `renderHtmlTemplate()`（`linkedom + node:vm` 编译 `template.html + style.css + render.js + ./assets/*` 为无脚本静态 HTML）以及默认模板自动渲染、图片压缩内嵌与 ≤ 1 MB 体积校验。

## 4. 通用声明式凭据与 Web 登录桥

- 主框架与 App **零平台硬编码**，所有登录态需求均由插件通过 `auth` 声明：
  - `type: 'token'`：App 弹窗输入 Token/API Key，经 HTTPS 加密上传服务端。
  - `type: 'web-cookie'`：插件声明 `loginUrl`、`cookieDomains`、`requiredCookies` 与 `verify(credential, ctx)`。
- **安全闭环**：
  1. App 先以接收密钥调用 `POST /v1/engine/credentials/{id}/pair` 换取 10 分钟一次性配对码；
  2. 独立进程 `PlatformLoginActivity`（隔离 WebView Profile，强制公网 `https://` 校验，拒绝内网/本地地址）加载官方登录页；
  3. 检测到所有 `requiredCookies` 就位后，经用户确认通过一次性配对码上传至 `POST /v1/engine/credentials/{id}/import`；
  4. 服务端调用该插件自己的 `auth.verify()` 验真并 AES-256-GCM 加密保存；运行时若插件抛出 `AuthExpiredError`，服务端自动标记凭据过期并向手机推送提醒消息。
