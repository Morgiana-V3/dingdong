# dingdong-plugin-bilibili-feed

叮咚（Dingdong）官方标准插件结构参考示例，用于订阅 B 站关注 UP 主的动态与视频投稿。

## 目录结构

```text
bilibili-feed/
├── package.json        # 插件元信息与 main 入口声明
├── README.md           # 插件说明
└── src/
    ├── index.ts        # Cordis 插件入口（definePlugin 注册与编排）
    ├── types.ts        # Config / State / 平台接口类型定义
    ├── schema.ts       # 配置表单（fields）与声明式网页登录（auth）
    ├── client.ts       # 平台 HTTP API 请求封装
    ├── parser.ts       # 动态解析、关键词过滤与可选 AI 导读生成
    └── template/       # 可直接用浏览器打开预览的静态 HTML 模板套件
        ├── template.html   # 纯 HTML 骨架（浏览器/Live Server 打开即看效果）
        ├── style.css       # 纯 CSS 样式（服务端自动内联为 <style>）
        └── render.js       # render(data) + testData（服务端执行后自动移除 <script>）
```

## 演示的能力

1. **声明式网页登录（`web-cookie`）**：在 `src/schema.ts` 声明登录页与必要 Cookie，手机 App 自动弹出隔离 WebView 登录并安全回传。
2. **多类型配置表单（`fields`）**：涵盖 `select`、`text`、`number`、`boolean`，App 与 Web 自动渲染。
3. **增量去重与容错**：`state.seenIds` 在消息送达中转后原子提交；会话过期时抛出 `AuthExpiredError` 自动推送提醒。
4. **可选 AI 导读**：声明 `capabilities: ['ai.optional']`，开启开关并选择 AI 配置时自动生成导读，未配置或调用失败不影响推送。
