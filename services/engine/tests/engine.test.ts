import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createEngineRuntime } from '../src/server.ts';
import { AuthExpiredError } from '../src/credentials.ts';
import { validateConfig, validateSchedule, nextRun } from '../src/domain.ts';
import { renderHtmlTemplate } from '../src/template-engine.ts';

function tempDir(prefix) {
  return fs.mkdtempSync(path.join(os.tmpdir(), prefix));
}

test('domain validates all generic field types and masks secrets', () => {
  const plugin = {
    fields: [
      { key: 'title', label: '标题', type: 'text', required: true },
      { key: 'rules', label: '规则', type: 'textarea', default: 'all' },
      { key: 'count', label: '数量', type: 'number', min: 1, max: 10, default: 5 },
      { key: 'flag', label: '开关', type: 'boolean', default: true },
      { key: 'mode', label: '模式', type: 'select', options: [{ value: 'fast', label: '快速' }], default: 'fast' },
      { key: 'urls', label: '地址', type: 'stringList', required: true },
      { key: 'apiKey', label: '密钥', type: 'secret', required: true },
    ],
  };
  const { config, secrets } = validateConfig(plugin, {
    title: ' 测试 ',
    count: '8',
    flag: false,
    urls: 'https://a.com\nhttps://b.com',
    apiKey: 'secret-123456',
  });
  assert.equal(config.title, '测试');
  assert.equal(config.count, 8);
  assert.equal(config.flag, false);
  assert.deepEqual(config.urls, ['https://a.com', 'https://b.com']);
  assert.equal(config.apiKey, true);
  assert.equal(secrets.apiKey, 'secret-123456');

  // Empty secret reuses previous secret
  const next = validateConfig(plugin, { ...config, apiKey: '' }, secrets);
  assert.equal(next.secrets.apiKey, 'secret-123456');
  assert.equal(next.config.apiKey, true);

  assert.deepEqual(validateSchedule({ type: 'daily', times: ['18:00', '08:30'] }), {
    type: 'daily',
    times: ['08:30', '18:00'],
  });
  assert.ok(nextRun({ type: 'interval', minutes: 10 }, 1000) === 601000);
});

test('dynamic plugin loading, error isolation, generic web-cookie auth, and outbox atomic retry', async () => {
  const dir = tempDir('dd-engine-');
  const pluginsDir = path.join(dir, 'plugins');
  fs.mkdirSync(path.join(pluginsDir, 'good-plugin'), { recursive: true });
  fs.mkdirSync(path.join(pluginsDir, 'ts-plugin'), { recursive: true });
  fs.mkdirSync(path.join(pluginsDir, 'broken-plugin'), { recursive: true });

  fs.writeFileSync(
    path.join(pluginsDir, 'ts-plugin', 'index.ts'),
    `
    export const name: string = 'ts-plugin';
    export function apply(ctx: any): void {
      ctx.source.register({
        id: 'ts-demo',
        name: 'TypeScript 原生插件',
        fields: [{ key: 'msg', label: '内容', type: 'text', default: 'ok' }],
        async run(job: any) {
          return { message: { title: String(job.config.msg), format: 'text', content: 'from ts' } };
        },
      });
    }
    `,
  );

  fs.writeFileSync(
    path.join(pluginsDir, 'broken-plugin', 'index.ts'),
    'export const name = "broken"; export function apply() { throw new Error("boom"); }\n',
  );
  fs.writeFileSync(
    path.join(pluginsDir, 'good-plugin', 'index.ts'),
    `
    export const name = 'good-plugin';
    export function apply(ctx) {
      ctx.source.register({
        id: 'good-source',
        name: '自定义示例源',
        auth: {
          id: 'my-site',
          name: '某测试站',
          type: 'web-cookie',
          loginUrl: 'https://example.com/login',
          cookieDomains: ['https://example.com'],
          requiredCookies: ['sid'],
          async verify(cred) {
            if (cred.cookies.sid !== 'valid-sid') throw new Error('无效 sid');
            return { name: '测试用户' };
          }
        },
        fields: [{ key: 'tag', label: '标签', type: 'text', required: true }],
        async run(job) {
          const count = (job.state.count || 0) + 1;
          return {
            message: {
              title: job.config.tag + ' #' + count,
              articles: [{ title: '文章 ' + count, body: '内容 ' + job.credential.cookies.sid }],
            },
            state: { count },
            detail: '已运行第 ' + count + ' 次',
          };
        },
      });
    }
    `,
  );

  const published = [];
  let failPublish = true;
  const runtime = await createEngineRuntime({
    directory: path.join(dir, 'data'),
    pluginDirs: [pluginsDir],
    publish: async (payload) => {
      if (failPublish) throw new Error('relay offline');
      published.push(payload);
    },
  });

  try {
    const snap = runtime.engine.snapshot();
    assert.ok(snap.plugins.some((p) => p.id === 'good-source'));
    assert.ok(snap.plugins.some((p) => p.id === 'ts-demo'));
    assert.ok(snap.plugins.some((p) => p.id === 'digest'));
    assert.equal(snap.pluginErrors.length, 1);

    // Create enabled task -> requires my-site credential
    const afterCreate = (await runtime.engine.command({
      revision: snap.revision,
      action: 'save',
      name: '我的任务',
      pluginId: 'good-source',
      enabled: true,
      schedule: { type: 'manual' },
      config: { tag: '日报' },
    })) as ReturnType<typeof runtime.engine.snapshot>;
    assert.equal(afterCreate.tasks[0].state, 'needs_login');
    assert.equal(afterCreate.accounts.length, 1);
    assert.equal(afterCreate.accounts[0].id, 'my-site');
    assert.equal(afterCreate.accounts[0].loginUrl, 'https://example.com/login');

    // Invalid cookie rejected
    await assert.rejects(
      () => runtime.credentials.importCredential('my-site', { cookie: 'sid=bad' }),
      /无效 sid/,
    );

    // Valid cookie accepted and encrypted
    const credStatus = await runtime.credentials.importCredential('my-site', { cookie: 'sid=valid-sid; foo=bar' });
    assert.equal(credStatus.state, 'ready');
    assert.equal(credStatus.account.name, '测试用户');

    // First run fails publish -> outbox persisted, state not committed yet
    const task = runtime.engine.state.tasks[0];
    await runtime.engine.executeTask(task);
    assert.ok(task.pending);
    assert.equal(task.pluginState.count, undefined);
    const pendingId = task.pending.payload.id;

    // Second run succeeds publish -> reuses identical message ID and commits state
    failPublish = false;
    await runtime.engine.executeTask(task);
    assert.equal(task.pending, undefined);
    assert.equal(published.length, 1);
    assert.equal(published[0].id, pendingId);
    assert.equal(task.pluginState.count, 1);
  } finally {
    await runtime.ctx.stop();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('AuthExpiredError marks credential expired and notifies user via relay', async () => {
  const dir = tempDir('dd-auth-exp-');
  const published = [];
  const runtime = await createEngineRuntime({
    directory: path.join(dir, 'data'),
    pluginDirs: [],
    publish: async (payload) => {
      published.push(payload);
    },
  });
  try {
    runtime.registry.register({
      id: 'exp-source',
      name: '过期测试源',
      auth: { id: 'tok', name: 'GitHub', type: 'token' },
      fields: [],
      async run() {
        throw new AuthExpiredError('tok', 'Token 已过期');
      },
    });
    await runtime.credentials.importCredential('tok', { token: 'ghp_test123' });
    const snap = runtime.engine.snapshot();
    await runtime.engine.command({
      revision: snap.revision,
      action: 'save',
      name: '仓库监控',
      pluginId: 'exp-source',
      enabled: true,
      schedule: { type: 'manual' },
      config: {},
    });
    await runtime.engine.executeTask(runtime.engine.state.tasks[0]);
    assert.equal(runtime.credentials.status('tok').state, 'expired');
    assert.equal(published.length, 1);
    assert.match(published[0].title, /GitHub 登录已失效/);
  } finally {
    await runtime.ctx.stop();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('renderHtmlTemplate compiles template.html + style.css + render.js into script-free static HTML', () => {
  const html = renderHtmlTemplate(
    new URL('../plugins/bilibili-feed/src/template', import.meta.url),
    {
      taskName: 'B 站测试推送',
      aiSummary: '今天有 1 条新动态',
      items: [
        {
          title: '测试视频标题',
          body: '第一段\n\n第二段',
          source: '测试 UP',
          url: 'https://www.bilibili.com/video/BV1test',
          images: [],
          publishedAt: 1700000000000,
        },
      ],
    },
  );
  assert.match(html, /<style>/);
  assert.doesNotMatch(html, /<script/i);
  assert.doesNotMatch(html, /<link[^>]+stylesheet/i);
  assert.match(html, /测试视频标题/);
  assert.match(html, /今天有 1 条新动态/);
  assert.match(html, /测试 UP/);

  const noBanner = renderHtmlTemplate(
    new URL('../plugins/bilibili-feed/src/template', import.meta.url),
    {
      taskName: '无导读',
      aiSummary: '',
      items: [{ title: '条目', body: '', source: 'UP', url: 'https://example.com', images: [] }],
    },
  );
  assert.doesNotMatch(noBanner, /id="ai-banner"/);
});
