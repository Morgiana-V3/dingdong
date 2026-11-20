# 叮咚（Dingdong）插件开发指南（人类 & AI Coding Agent 通用）

叮咚插件引擎（`services/engine/`）基于 **Cordis**（Koishi 同源插件内核）与 **Node.js 22+ 原生 TypeScript 支持** 构建。你只需要编写一个单文件插件并放入 `plugins/<插件名>/index.ts`（同时兼容 `.mts / .mjs / .js`，**无需编译步骤**），重启引擎即可自动加载，**手机 App 和 Web 管理台会按你声明的 `fields` 与 `auth` 自动生成配置表单和登录入口，无需修改客户端代码。**

> **给 AI 编程助手的提示**：阅读本指南及 [dingdong-plugin.d.ts](../services/engine/sdk/dingdong-plugin.d.ts) 后即可直接编写插件，完成后运行 `npm run plugin:test <插件目录>` 校验。

---

## 1. 一键生成插件模板

```sh
cd services/engine
npm run plugin:create my-watcher "我的监控"
```

生成的标准插件目录包含完整注释、`types.ts`、`schema.ts`、`index.ts` 及浏览器可直接预览的 `src/template/`。所有 SDK 方法与类型统一从 **`dingdong-engine/sdk`** 导入（零相对路径，编辑器输入 `from 'dingdong-engine/sdk'` 自动列出全部可用导出）：

```ts
// plugins/my-watcher/src/index.ts
import { AuthExpiredError, definePlugin, loadImage, renderHtmlTemplate } from 'dingdong-engine/sdk';
```

### 最小插件代码

```ts
// plugins/my-plugin/src/index.ts
import { definePlugin } from 'dingdong-engine/sdk';

export default definePlugin({
  name: 'my-plugin',
  inject: { required: ['source', 'http'] },
  apply(ctx) {
    ctx.source.register({
      id: 'my-plugin',
      name: '我的订阅源',
      description: '一句话说明用途',
      version: '1.0.0',
      fields: [
        { key: 'url', label: '数据源地址', type: 'text', required: true },
        { key: 'limit', label: '最多条数', type: 'number', default: 5, min: 1, max: 20 },
      ],
      async run(job) {
        const { config, state, http, signal, log } = job;
        log('fetch', `拉取 ${config.url}`);
        const data = await http.json<{ items: Array<{ id: string; title: string; summary: string; url: string }> }>(String(config.url), { signal });
        const seen = new Set<string>(Array.isArray(state.seenIds) ? state.seenIds : []);
        const fresh = data.items.filter((i) => !seen.has(i.id)).slice(0, Number(config.limit || 5));
        if (!fresh.length) {
          return { message: null, state: { seenIds: [...seen].slice(-500) }, detail: '暂无更新' };
        }
        return {
          message: {
            title: `${job.taskName}（${fresh.length} 条）`,
            short: fresh.slice(0, 2).map((i) => i.title).join('；'),
            articles: fresh.map((i) => ({ title: i.title, body: i.summary, url: i.url })),
          },
          state: { seenIds: [...seen, ...fresh.map((i) => i.id)].slice(-500) },
          detail: `推送 ${fresh.length} 条更新`,
        };
      },
    });
  },
});
```

---

## 2. 宿主提供的 `job` 上下文能力

| 属性 | 说明 |
| --- | --- |
| `job.config` | 经宿主校验后的用户配置对象（含 `secret` 字段解密后的明文） |
| `job.state` | 上次**投递成功**后持久化的状态对象（去重 ID、游标等）；返回新 `state` 会在消息送达中转后原子提交 |
| `job.http` | `fetch(url, opts)`、`text(url, opts)`、`json(url, opts)`，自动支持代理与超时 |
| `job.ai` | 若任务关联了 AI 配置，提供 `generate(opts, signal)`、`json(opts, signal)` 与原始 `config`（含 `apiUrl / apiKey / model / protocol` 供插件自行发起定制请求）；也可在 `fields` 中声明多个 `aiProvider` 字段按需取用 |
| `job.credential` | 若插件声明了 `auth`，此处自动注入已解密的凭据（`{ cookie, cookies }` 或 `{ token }`） |
| `job.signal` | `AbortSignal`，任务被用户停止或超时时触发，请透传给 `http` 与 `ai` |
| `job.log(step, detail)` | 记录执行轨迹，手机 App 和 Web 管理台可查看 |

---

## 3. 支持的配置字段原语（`fields`）

| `type` | 说明 | 常用属性 |
| --- | --- | --- |
| `text` | 单行文本 | `required`, `default`, `placeholder`, `maxLength`, `help` |
| `textarea` | 多行文本（适合自然语言筛选规则） | `required`, `default`, `placeholder`, `maxLength`, `help` |
| `number` | 数字 | `required`, `default`, `min`, `max`, `integer` |
| `boolean` | 开关 | `default` |
| `select` | 下拉单选 | `required`, `options: [{ value, label, description? }]`, `default` |
| `stringList` | 多行列表（在 `config` 中自动解析为 `string[]`） | `required`, `maxItems`, `placeholder` |
| `secret` | 加密密钥（App 不回显明文，留空保持原值） | `required`, `maxLength` |
| `aiProvider` | 从服务端已配置的 AI 服务中选择模型（可声明多个，如过滤模型 + 摘要模型） | `required`, `help` |
| `remoteMultiSelect` | 带顶部搜索框的远程多选面板（配合 `optionsHandlers[key]` 动态拉取选项） | `required`, `maxItems`, `help` |

> **分组与条件显隐**：任意字段都可附加 `group` / `groupDescription`（同组字段在 App 中自动聚合为同一卡片）以及 `when: { field, notEmpty?: true, equals?: ... }`（根据另一字段值动态展开/收起）。

---

## 4. 声明登录态与凭据（`auth`，可选）

若插件需要目标网站的登录 Cookie 或 API Token，**无需修改 App**，只需在 `register()` 中声明 `auth`：

### 4.1 手机网页登录同步 Cookie（`web-cookie`）
```js
auth: {
  id: 'my-site',
  name: '某网站',
  type: 'web-cookie',
  loginUrl: 'https://example.com/login',
  cookieDomains: ['https://example.com'],
  requiredCookies: ['session_id'],
  async verify({ cookie, cookies }, { http }) {
    const me = await http.json('https://example.com/api/me', { headers: { cookie } });
    if (!me?.id) throw new Error('登录已失效');
    return { name: me.nickname };
  },
}
```
手机 App 会自动在「订阅管理 → 所需账号」中展示该站点，使用独立隔离 WebView 打开 `loginUrl`，检测到 `requiredCookies` 后经一次性配对码通过 HTTPS 上传到服务端，由你的 `verify` 函数验真并 AES-256-GCM 加密保存。

若运行时发现登录态过期，可抛出 `AuthExpiredError`（统一从 `'dingdong-engine/sdk'` 导入），宿主会自动将凭据标记为 `expired` 并向手机推送提醒消息。

### 4.2 Token / API Key（`token`）
```js
auth: {
  id: 'github-pat',
  name: 'GitHub Token',
  type: 'token',
  help: '在 GitHub Settings 生成只读 Personal Access Token',
  async verify({ token }, { http }) {
    const me = await http.json('https://api.github.com/user', {
      headers: { Authorization: `Bearer ${token}` },
    });
    return { name: me.login };
  },
}
```

---

## 5. 输出格式与可视化 HTML 模板（推荐）

插件支持三种输出方式：
- **自定义 HTML 模板目录（最推荐，可边写边在浏览器预览）**：使用 SDK 提供的 `renderHtmlTemplate(new URL('./template', import.meta.url), data)`。在插件内放 `template.html` + `style.css` + `render.js`（带 `testData`），还可在 `template/assets/` 下放置本地 `.svg / .png / .webp` 素材并直接用 `./assets/xxx.svg` 引用；用浏览器打开 `template.html` 即可实时调样式，服务端推送时自动通过 `linkedom` + `vm` 执行 `render(data)`、内联 CSS 与本地素材并剥离 `<script>`，输出纯静态安全 HTML（参考 [bilibili-feed/src/template](../services/engine/plugins/bilibili-feed/src/template/template.html)）。
- **结构化 `articles`**：适合快速开发，由宿主默认模板排版并支持统一推送汇总。
- **原始正文**：直接返回 `{ title, short, format: 'html' | 'markdown' | 'text', content }`。

**硬约束**：
1. 最终渲染后的 HTML 必须 ≤ **1,000,000 字节（1 MB）**。
2. 阅读页禁用 JavaScript，不加载外链图片/样式；正文中的 `https://` 图片会由宿主自动压缩并内嵌为 `data:` URI。
3. 无新内容时返回 `{ message: null, state, detail }`，避免空推送打扰。

---

## 6. 本地校验与试跑

```sh
cd services/engine
npm run plugin:test ./plugins/rss-watch
# 传入配置文件试跑并导出渲染后的本地 HTML 预览：
npm run plugin:test ./plugins/my-plugin -- --config ./test-config.json --out ./preview.html
# 加 --send 可直接发送预览消息到手机（需设置 DINGDONG_URL 与 DINGDONG_SEND_TOKEN）：
npm run plugin:test ./plugins/my-plugin -- --config ./test-config.json --send
```

参考内置完整示例（位于 `services/engine/plugins/`，自带完整 TS 环境）：
- [bilibili-feed](../services/engine/plugins/bilibili-feed/README.md)（完整多文件示范：`web-cookie` 登录 + 远程关注 UP 主搜索多选 + 双 AI 模型过滤与总结 + 分组表单 + HTML/SVG 模板）
- [rss-watch](../services/engine/plugins/rss-watch/index.ts)（单文件极简示范：纯 HTTP + 游标去重）
- [ai-web-digest](../services/engine/plugins/ai-web-digest/index.ts)（单文件极简示范：网页抓取 + AI 筛选摘要）
