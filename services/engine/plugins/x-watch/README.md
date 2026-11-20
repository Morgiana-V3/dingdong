# X（推特）订阅插件（`x-watch`）

免登录监控公开 X（Twitter）账号推文或关键词最新动态（基于 FxEmbed 公开只读接口），支持多账号汇总、引用推文与图文展示、双 AI 模型过滤与中文导读总结。

> 如部署在无法直连外网的服务器，请在 `services/engine/.env` 中配置 `HTTPS_PROXY`。

## 本地预览模板
直接用浏览器打开 `src/template/template.html` 即可实时调整卡片样式。

## 本地校验
```sh
cd services/engine
npm run plugin:test ./plugins/x-watch
```
