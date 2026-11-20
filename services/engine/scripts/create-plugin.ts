#!/usr/bin/env node
/**
 * Scaffold a new modular Dingdong plugin in services/engine/plugins/<name>/.
 * Usage:
 *   npm run plugin:create <plugin-id> [display-name]
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const pluginId = (args[0] || '').trim().toLowerCase();
const displayName = (args[1] || '').trim() || pluginId;

if (!pluginId || !/^[a-z][a-z0-9-]{0,63}$/.test(pluginId)) {
  console.error('用法: npm run plugin:create <插件ID> [显示名称]');
  console.error('插件 ID 需以小写字母开头，仅包含小写字母、数字和连字符，例如: npm run plugin:create my-watcher "我的监控"');
  process.exit(1);
}

const targetDir = path.join(root, 'plugins', pluginId);
if (fs.existsSync(targetDir)) {
  console.error(`插件目录已存在: ${targetDir}`);
  process.exit(1);
}

const srcDir = path.join(targetDir, 'src');
const tplDir = path.join(srcDir, 'template');
fs.mkdirSync(tplDir, { recursive: true });

fs.writeFileSync(
  path.join(targetDir, 'package.json'),
  JSON.stringify(
    {
      name: `dingdong-plugin-${pluginId}`,
      version: '0.1.0',
      private: true,
      type: 'module',
      main: './src/index.ts',
      description: `${displayName} - 叮咚自定义插件`,
    },
    null,
    2,
  ) + '\n',
);

fs.writeFileSync(
  path.join(targetDir, 'README.md'),
  `# ${displayName} (${pluginId})

## 目录结构

\`\`\`text
${pluginId}/
├── package.json        # 插件元信息与入口声明
├── README.md           # 插件说明
└── src/
    ├── index.ts        # Cordis 插件入口与主运行逻辑
    ├── types.ts        # Config / State 类型定义
    ├── schema.ts       # 配置表单（fields）与可选登录态（auth）
    └── template/       # 可视化 HTML 模板（直接用浏览器打开 template.html 预览）
        ├── template.html
        ├── style.css
        └── render.js
\`\`\`

## 本地验证

\`\`\`sh
cd services/engine
npm run typecheck
npm run plugin:test ./plugins/${pluginId}
\`\`\`
`,
);

fs.writeFileSync(
  path.join(srcDir, 'types.ts'),
  `/**
 * 用户在手机 App / Web 管理台填写的配置项类型。
 * 与 src/schema.ts 中的 fields 一一对应。
 */
export interface PluginConfig {
  targetUrl: string;
  limit: number;
  // 若需要宿主提供的 AI 能力，在 schema.ts 中声明 type: 'aiProvider' 字段即可
  aiProvider?: string;
}

/**
 * 持久化状态类型（用于增量去重、记录游标等）。
 * 宿主保证：只有消息成功送达中转服务器后，才会原子提交新的 state。
 */
export interface PluginState {
  seenIds?: string[];
}

export interface RenderedItem {
  id: string;
  title: string;
  summary: string;
  url: string;
  publishedAt?: number;
}
`,
);

fs.writeFileSync(
  path.join(srcDir, 'schema.ts'),
  `import type { PluginField, WebCookieAuth } from 'dingdong-engine/sdk';

/**
 * 配置表单定义（参考 Koishi Schema）：
 * 支持的 type：
 * - 'text'       单行文本
 * - 'textarea'   多行文本（适合筛选规则、提示词）
 * - 'number'     数字（支持 min / max）
 * - 'boolean'    开关
 * - 'select'     下拉单选（需提供 options）
 * - 'stringList' 多行列表（运行时自动解析为 string[]）
 * - 'secret'     加密密钥（不回显明文）
 * - 'aiProvider' 选择服务器已配置的 AI 模型（插件不声明则 App 不显示 AI 选项）
 */
export const fields: PluginField[] = [
  {
    key: 'targetUrl',
    label: '数据源地址',
    type: 'text',
    required: true,
    placeholder: 'https://example.com/feed.json',
    help: '填写需要定时抓取的网页或 JSON 接口地址。',
  },
  {
    key: 'limit',
    label: '单次最多推送条数',
    type: 'number',
    default: 5,
    min: 1,
    max: 20,
  },
  {
    key: 'aiProvider',
    label: 'AI 摘要模型（可选）',
    type: 'aiProvider',
    required: false,
    help: '留空则不使用 AI；选择后可在 run(job) 中通过 job.getAI(config.aiProvider) 调用。',
  },
];

/**
 * 可选：若你的插件需要目标网站登录态（Cookie）或 API Token，
 * 取消下方注释并在 src/index.ts 中传给 auth，手机 App 会自动出现对应登录入口。
 */
export const exampleAuth: WebCookieAuth | undefined = undefined;
/*
export const auth: WebCookieAuth = {
  id: '${pluginId}-auth',
  name: '${displayName}',
  type: 'web-cookie', // 若只需手动填密钥，改为 type: 'token'
  loginUrl: 'https://example.com/login',
  cookieDomains: ['https://example.com'],
  requiredCookies: ['session_id'],
  async verify({ cookie }, { http }) {
    const me = await http.json<{ name?: string }>('https://example.com/api/me', {
      headers: { cookie },
    });
    return { name: me.name || '已登录用户' };
  },
};
*/
`,
);

fs.writeFileSync(
  path.join(srcDir, 'index.ts'),
  `import { AuthExpiredError, definePlugin, renderHtmlTemplate } from 'dingdong-engine/sdk';
import { fields } from './schema.ts';
import type { PluginConfig, PluginState, RenderedItem } from './types.ts';

export default definePlugin({
  name: '${pluginId}',
  inject: { required: ['source', 'http'] },
  apply(ctx) {
    ctx.source.register<PluginConfig, PluginState>({
      id: '${pluginId}',
      name: '${displayName}',
      description: '在此填写插件的一句话简介（展示在手机 App 插件选择卡片中）',
      version: '0.1.0',
      fields,
      // 若需要登录态，引入 schema.ts 中的 auth 并在此挂载：
      // auth,

      async run(job) {
        const { config, state, http, signal, log } = job;
        // 1. 按需获取用户在表单中选择的 AI 服务（未选择时为 null）
        const ai = job.getAI(config.aiProvider);

        // 2. 拉取数据（请透传 signal 以支持任务取消与超时控制）
        log('fetch', \`正在拉取 \${config.targetUrl}\`);
        void http;
        void AuthExpiredError;

        // TODO: 替换为你的真实抓取逻辑
        const fetched: RenderedItem[] = [
          {
            id: 'demo-1',
            title: '示例条目（请替换为真实抓取逻辑）',
            summary: \`来自 \${config.targetUrl}\`,
            url: config.targetUrl,
            publishedAt: Date.now(),
          },
        ];

        // 3. 利用 job.state 自主管理增量去重
        const seen = new Set<string>(state.seenIds || []);
        const fresh = fetched.filter((item) => !seen.has(item.id)).slice(0, config.limit || 5);
        const nextSeen = [...seen, ...fresh.map((item) => item.id)].slice(-500);

        if (!fresh.length) {
          return {
            message: null,
            state: { seenIds: nextSeen },
            detail: '本轮没有新内容',
          };
        }

        // 4. 可选：使用 AI 生成摘要
        let aiSummary = '';
        if (ai) {
          log('ai', '正在使用 AI 生成导读');
          aiSummary = await ai.generate(
            {
              system: '用一句话概括以下更新内容。',
              prompt: fresh.map((i) => \`- \${i.title}\`).join('\\n'),
            },
            signal,
          );
        }

        // 5. 使用可视化 HTML 模板渲染最终正文（浏览器直接打开 src/template/template.html 可实时预览样式）
        const html = renderHtmlTemplate(new URL('./template', import.meta.url), {
          taskName: job.taskName,
          aiSummary,
          items: fresh,
        });

        return {
          message: {
            title: \`\${job.taskName}（\${fresh.length} 条更新）\`,
            short: aiSummary || fresh[0].title,
            format: 'html',
            content: html,
          },
          state: { seenIds: nextSeen },
          detail: \`推送 \${fresh.length} 条更新\`,
        };
      },
    });
  },
});
`,
);

fs.writeFileSync(
  path.join(tplDir, 'template.html'),
  `<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${displayName}</title>
  <link rel="stylesheet" href="./style.css">
  <script src="./render.js"></script>
</head>
<body>
  <main>
    <section id="ai-banner" class="ai-banner" hidden>
      <div class="ai-tag">AI 导读</div>
      <p id="ai-summary"></p>
    </section>
    <div id="item-list" class="item-list"></div>
  </main>
</body>
</html>
`,
);

fs.writeFileSync(
  path.join(tplDir, 'style.css'),
  `:root {
  color-scheme: light dark;
  --bg: #fafaf8;
  --card: #ffffff;
  --text: #1f2328;
  --muted: #656d76;
  --border: #e8e8e3;
  --accent: #e36547;
}

@media (prefers-color-scheme: dark) {
  :root {
    --bg: #16181b;
    --card: #1f2227;
    --text: #e8e7e3;
    --muted: #9aa0a6;
    --border: #2e3239;
    --accent: #ff8c69;
  }
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  padding: 16px 14px 40px;
  background: var(--bg);
  color: var(--text);
  font: 15px/1.65 system-ui, -apple-system, sans-serif;
}

main {
  max-width: 720px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.ai-banner {
  background: var(--card);
  border: 1px solid var(--border);
  border-left: 3px solid var(--accent);
  border-radius: 12px;
  padding: 12px 14px;
}

.ai-tag {
  font-size: 11px;
  font-weight: 700;
  color: var(--accent);
  margin-bottom: 4px;
}

.ai-banner p {
  margin: 0;
  font-size: 14px;
}

.item-list {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

article.post {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 14px 16px;
}

article.post h2 {
  margin: 0 0 6px;
  font-size: 16px;
}

article.post h2 a {
  color: inherit;
  text-decoration: none;
}

article.post p {
  margin: 0;
  color: var(--muted);
  font-size: 14px;
}
`,
);

fs.writeFileSync(
  path.join(tplDir, 'render.js'),
  `function escapeHtml(text) {
  return String(text ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function render(data) {
  const { taskName = '${displayName}', aiSummary = '', items = [] } = data || testData;
  document.title = taskName;

  const banner = document.getElementById('ai-banner');
  const summaryEl = document.getElementById('ai-summary');
  if (banner && summaryEl) {
    if (aiSummary) {
      banner.removeAttribute('hidden');
      summaryEl.textContent = aiSummary;
    } else {
      banner.remove();
    }
  }

  const listEl = document.getElementById('item-list');
  if (!listEl) return;
  listEl.innerHTML = items
    .map(
      (item) => \`
      <article class="post">
        <h2><a href="\${escapeHtml(item.url)}">\${escapeHtml(item.title)}</a></h2>
        <p>\${escapeHtml(item.summary)}</p>
      </article>\`,
    )
    .join('\\n');
}

var testData = {
  taskName: '${displayName}（本地预览）',
  aiSummary: '这是浏览器本地预览时的示例 AI 导读。',
  items: [
    { title: '第一条示例内容', summary: '直接修改 style.css 并刷新浏览器即可实时调样式。', url: 'https://example.com/1' },
    { title: '第二条示例内容', summary: '服务端推送时会自动内联 CSS 并移除 script 标签。', url: 'https://example.com/2' },
  ],
};

if (typeof window !== 'undefined' && !window.__DINGDONG_SERVER__) {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => render(testData));
  } else {
    render(testData);
  }
}
`,
);

console.log(`✅ 已创建插件模板: services/engine/plugins/${pluginId}/`);
console.log(`   - 编辑逻辑: plugins/${pluginId}/src/index.ts`);
console.log(`   - 预览样式: 用浏览器直接打开 plugins/${pluginId}/src/template/template.html`);
console.log(`   - 校验插件: npm run plugin:test ./plugins/${pluginId}`);
