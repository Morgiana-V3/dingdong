# 叮咚插件引擎（`services/engine`）

基于 `@cordisjs/core`（Koishi 同源插件内核）的轻量可选服务，用于定时执行自定义插件、管理 AI 配置与加密凭据，并将生成的内容推送至 `services/relay`。

## 快速部署（Docker Compose）

```sh
cd services/engine
cp .env.example .env
# 编辑 .env，填入与 services/relay 一致的 DINGDONG_SEND_TOKEN 和 DINGDONG_READ_TOKEN
chmod 600 .env
docker compose up -d --build
curl http://127.0.0.1:18890/health
```

- 自定义插件放在 `services/engine/plugins/<插件名>/index.ts`（同时支持 `.mts / .mjs / .js`，Node 22 原生免编译加载；容器内挂载为 `/app/plugins`），重启容器即可自动加载。
- 通过 Nginx 将 HTTPS 的 `/v1/engine/` 转发到 `127.0.0.1:18890`（参考 [deploy/nginx.conf.template](deploy/nginx.conf.template)），手机 App 会自动探测 `/v1/engine/health` 并展示「订阅管理」。

## 访问本地 Web 管理台

Web 管理台默认仅监听 `127.0.0.1:18890`，不直接对外暴露。通过 SSH 端口转发访问：

```sh
# 1. 查看首次启动自动生成的管理密钥
docker compose exec engine cat /app/data/admin.key

# 2. 在本机建立隧道
ssh -N -L 18890:127.0.0.1:18890 用户名@服务器
```

浏览器打开 <http://127.0.0.1:18890> 输入管理密钥即可查看任务、已加载插件、AI 配置与凭据状态。

## 编写与测试自定义插件

详见 [插件开发指南](../../docs/PLUGIN_GUIDE.md) 与 [TypeScript SDK](sdk/dingdong-plugin.d.ts)：

```sh
npm install
npm run typecheck
npm test
npm run plugin:test ./plugins/bilibili-feed
npm run plugin:test ./plugins/rss-watch
npm run plugin:test ./plugins/ai-web-digest
```
