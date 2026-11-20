# 叮咚 · Dingdong

一个可自部署的 Android 私人推送收件箱与插件化内容引擎。  
你可以用一行 HTTP 请求把任意自定义排版的内容推送到手机离线阅读；也可以在服务器部署插件引擎，按计划抓取你关注的网站、用 AI 过滤与总结，再按自定义 HTML 样式推到手机。

## 它能做到什么

- **不只是通知栏一行字，而是完整富文本卡片**  
  支持自定义 HTML + 内联 CSS、Markdown、表格、多图与本地 SVG 素材；手机端离线保存、全文搜索、日期与来源筛选、收藏、批量管理、全屏缩放看图与本地 JSON 备份。
- **数据完全归你自己**  
  服务端只做临时中转，手机下载落盘后服务器立即清除正文；支持后台长连接、断线重连与离线补收。
- **App 开箱即用，无需为新功能重新编译**  
  直接安装现成 APK，填入自己的服务器地址和密钥即可使用。服务端新增插件后，**手机 App 会自动渲染对应的配置表单、远程搜索多选与登录入口**。
- **高度可定制的服务端插件（人类与 AI 助手都能快速编写）**  
  - **免改客户端登录**：需要网站 Cookie 或 Token 时，插件声明登录规则，手机在独立隔离 WebView 中完成登录并加密回传服务端。
  - **按需组合多模型 AI**：服务器统一管理多个 AI 服务商，插件可自由指定不同模型（例如轻量模型过滤噪音、强模型生成导读），也可拿原始配置自行发起定制请求。
  - **所见即所得模板**：支持浏览器直接打开 `template.html` 调样式，推送时自动内联 CSS/素材并转为安全静态 HTML。

---

## 快速上手

### 懒人方案：复制提示词交给 AI Agent 一键部署

如果你正在使用 AI 编程助手（Antigravity / Cursor / Claude Code / Codex 等），直接把下面这段提示词发给它，即可自动完成服务端部署、HTTPS 代理配置、App 安装与首条测试推送：

```text
请帮我部署并配置当前仓库的「叮咚（Dingdong）」私人推送服务与 Android App。请按以下步骤执行：
1. 先向我确认 3 件事：
   - 部署模式：仅核心推送中转（services/relay），还是完整版（services/relay + services/engine 插件引擎）；
   - 我的服务器 SSH 信息与访问方式（域名 HTTPS 还是公网 IP 直连）；
   - 我的 Android 手机是否已通过 USB 连接电脑（用于自动安装 APK）。
2. 在服务器上分别生成两个 32 位以上独立随机密钥（DINGDONG_SEND_TOKEN 和 DINGDONG_READ_TOKEN），写入权限为 600 的 .env（绝不写入 Git 仓库），通过 Docker Compose 启动对应服务。
3. 如使用域名与插件引擎，参考 services/engine/deploy/nginx.conf.template 配置 Nginx 反向代理（确保开启 /v1/stream 的 WebSocket 转发，并将 /v1/engine/ 转发到插件引擎），校验 /health 与 /v1/engine/health 均返回正常。
4. 帮我获取或安装 Android App：优先指引我从 Releases 下载 APK；如果我已连接 USB 手机且本机有 Flutter 环境，也可直接编译并通过 adb 安装到手机。
5. 等我在 App 的「设置 → 服务器连接」填入服务器地址和 DINGDONG_READ_TOKEN 后，使用 tools/send.py 发送一条测试 HTML 消息验证端到端送达。
```

### 手动步骤：第一步 安装 Android App

前往 [GitHub Releases](../../releases) 下载最新的 `app-release.apk` 安装（支持 Android 8.0 及以上）。  
安装后打开「设置 → 服务器连接」，填入下一步部署好的服务器地址与接收密钥即可。

> 如需自行修改或编译客户端源码，见 [开发与验证文档](docs/development.md)。

### 手动步骤：第二步 部署服务端

按需二选一，均提供 Docker Compose 一键部署：

- **仅需推送收件箱（`services/relay`）**：适合配合自己的脚本、Cron、n8n、GitHub Actions 主动推消息。
- **完整插件订阅（`services/relay` + `services/engine`）**：在推送基础上，增加定时插件调度、手机端管理任务、AI 过滤总结与网页登录同步 Cookie。

```sh
# 1. 启动核心消息中转
cd services/relay
cp .env.example .env
# 在 .env 中填入两个不同的 32 位以上随机密钥：DINGDONG_SEND_TOKEN / DINGDONG_READ_TOKEN
chmod 600 .env
docker compose up -d --build
```

```sh
# 2. （可选）启动插件引擎
cd services/engine
cp .env.example .env
# 填入与 relay 一致的两个密钥
chmod 600 .env
docker compose up -d --build
```

公网 HTTPS 反向代理（Nginx）与数据迁移详见 [部署文档](docs/deployment.md) 和 [插件引擎部署说明](services/engine/README.md)。

---

## 开始使用

### 方式一：任意脚本直接推一条富文本消息

只需调用 `POST /v1/messages`（Header：`Authorization: Bearer <DINGDONG_SEND_TOKEN>`），或直接使用仓库内置的零依赖 Python 工具：

```sh
export DINGDONG_URL="https://你的服务器地址"
export DINGDONG_SEND_TOKEN="你的发送密钥"
python tools/send.py examples/report.html --title "每日巡检" --source "监控脚本" --wait 30
```

更多发送参数、Markdown/图片内嵌与模板用法见 [脚本发送与模板](docs/sending.md)。

### 方式二：定制自己的服务端插件（推荐）

只需要关注你想要的数据源和展示样式，不用碰手机 App 代码：

```sh
cd services/engine
npm install

# 1. 一键生成带完整注释和本地预览模板的插件骨架
npm run plugin:create my-watcher "我的监控"

# 2. 本地校验并导出静态 HTML 预览（无需连接服务器）
npm run plugin:test ./plugins/my-watcher -- --out ./preview.html
```

把插件目录放入 `services/engine/plugins/`（容器内挂载 `/app/plugins`）并重启引擎，手机 App 的「订阅管理」就会自动识别它。

> **小技巧**：你可以直接把 [插件开发指南](docs/PLUGIN_GUIDE.md) 和 [SDK 类型定义](services/engine/sdk/dingdong-plugin.d.ts) 交给 AI 编程助手，描述你想追踪的网站、过滤条件和卡片样式，让它帮你生成插件并用 `npm run plugin:test` 自检。

仓库内置了 3 个可直接参考或启用的官方插件：

| 插件 | 风格 | 演示能力 |
| --- | --- | --- |
| [bilibili-feed](services/engine/plugins/bilibili-feed/README.md) | 多文件标准结构 | 手机网页登录回传 Cookie、远程搜索多选关注 UP 主、双 AI 模型过滤与导读、分组表单、HTML + SVG 素材模板 |
| [rss-watch](services/engine/plugins/rss-watch/index.ts) | 单文件极简 | 纯 HTTP 拉取 + 游标增量去重 |
| [ai-web-digest](services/engine/plugins/ai-web-digest/index.ts) | 单文件极简 | 网页正文抓取 + AI 兴趣筛选摘要 |

---

## 仓库结构与延伸文档

```text
mobile/                 Android 客户端源码（Flutter + Kotlin）
services/relay/         核心消息中转服务
services/engine/        可选插件引擎、SDK、内置插件与 CLI 工具
tools/ & examples/      零依赖发送脚本、模板渲染器与示例
docs/                   详细文档
```

- [插件开发指南](docs/PLUGIN_GUIDE.md) — 表单原语、动态登录、多模型 AI 与 HTML 模板写法
- [部署与迁移](docs/deployment.md) — Docker Compose、HTTPS 反向代理与数据卷迁移
- [脚本发送与模板](docs/sending.md) — HTTP 接口、本地图片内嵌与模板渲染
- [技术架构](docs/architecture.md) — 投递状态机、安全沙箱与加密凭据设计
- [开发与验证](docs/development.md) — 从源码编译 APK、单元测试与真机集成测试

## 开源协议

本项目基于 [MIT License](LICENSE) 开源。
