#!/usr/bin/env node
/**
 * Validate and dry-run a Dingdong Cordis plugin locally.
 * Usage:
 *   node scripts/test-plugin.mjs <plugin-dir-or-file> [--config config.json] [--send]
 */
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { Context } from '@cordisjs/core';
import { createHttpService } from '../src/http.ts';
import { CredentialManager } from '../src/credentials.ts';
import { SourceRegistry } from '../src/sources.ts';
import { validateConfig, validateOutput } from '../src/domain.ts';
import { renderDocument } from '../src/render.ts';

const args = process.argv.slice(2);
const target = args[0];
if (!target) {
  console.error('用法: npm run plugin:test <插件目录或index.mjs> [--config config.json] [--send]');
  process.exit(1);
}

const configFlag = args.indexOf('--config');
const configFile = configFlag >= 0 ? args[configFlag + 1] : null;
const outFlag = args.indexOf('--out');
const outFile = outFlag >= 0 ? args[outFlag + 1] : null;
const shouldSend = args.includes('--send');

const resolved = path.resolve(target);
let entryFile = resolved;
if (fs.statSync(resolved).isDirectory()) {
  const pkgPath = path.join(resolved, 'package.json');
  let pkgMain: string | undefined;
  if (fs.existsSync(pkgPath)) {
    try {
      const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
      if (typeof pkg.main === 'string') {
        const candidate = path.resolve(resolved, pkg.main);
        if (fs.existsSync(candidate)) pkgMain = candidate;
      }
    } catch {
      // Fall through to conventional entry lookup
    }
  }
  entryFile =
    pkgMain ||
    ['src/index.ts', 'index.ts', 'index.mts', 'index.mjs', 'index.js']
      .map((name) => path.join(resolved, name))
      .find((p) => fs.existsSync(p)) ||
    path.join(resolved, 'src/index.ts');
}
if (!fs.existsSync(entryFile)) {
  console.error(`找不到插件入口（支持 package.json main / src/index.ts / index.ts）: ${entryFile}`);
  process.exit(1);
}

const ctx = new Context();
const httpService = createHttpService();
const registry = new SourceRegistry(new CredentialManager(path.join(process.cwd(), '.plugin-test-tmp'), httpService));
ctx.provide('http', httpService, true);
ctx.provide('source', registry, true);

const mod = await import(pathToFileURL(entryFile).href);
const plugin = mod.default && typeof mod.default.apply === 'function' ? mod.default : mod;
if (typeof plugin.apply !== 'function') {
  throw new Error('插件必须导出 apply(ctx) 函数');
}
ctx.plugin(plugin);
await ctx.start();

const sources = [...registry.plugins.values()];
if (!sources.length) {
  throw new Error('插件未调用 ctx.source.register(...) 注册任何内容源');
}
console.log(`✅ 插件加载成功，共注册 ${sources.length} 个内容源：`);
for (const src of sources) {
  console.log(`   - ${src.id} (${src.name}) | fields: ${src.fields.length} | auth: ${src.auth ? `${src.auth.id} (${src.auth.type})` : '无'}`);
}

if (configFile) {
  const rawConfig = JSON.parse(fs.readFileSync(path.resolve(configFile), 'utf8'));
  const source = sources[0];
  const { config, secrets } = validateConfig(source, rawConfig);
  console.log('✅ 配置校验通过，开始试运行...');
  const output = validateOutput(
    await source.run({
      taskId: 'dry-run',
      taskName: source.name,
      config: { ...config, ...secrets },
      state: {},
      credential: null,
      ai: null,
      getAI: () => null,
      http: httpService,
      signal: AbortSignal.timeout(60_000),
      log: (step, detail) => console.log(`   [${step}] ${detail}`),
    }),
  );
  if (!output.message) {
    console.log(`ℹ️ 试运行完成，无新消息：${output.detail || ''}`);
  } else {
    const { content } = await renderDocument(output.message);
    const bytes = Buffer.byteLength(content, 'utf8');
    console.log(`✅ 渲染成功：title="${output.message.title}" | HTML 大小=${bytes} bytes (上限 1,000,000)`);
    if (outFile) {
      fs.writeFileSync(path.resolve(outFile), content, 'utf8');
      console.log(`📄 已输出预览 HTML 到 ${path.resolve(outFile)}`);
    }
    if (shouldSend) {
      const url = process.env.DINGDONG_URL;
      const token = process.env.DINGDONG_SEND_TOKEN;
      if (!url || !token) {
        throw new Error('使用 --send 需设置环境变量 DINGDONG_URL 和 DINGDONG_SEND_TOKEN');
      }
      const res = await fetch(`${url.replace(/\/+$/, '')}/v1/messages`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          id: `plugin-test-${Date.now()}`,
          source: source.name,
          title: output.message.title,
          summary: output.message.short || '',
          format: 'html',
          content,
          priority: 'normal',
        }),
      });
      if (!res.ok) throw new Error(`发送失败: HTTP ${res.status}`);
      console.log('✅ 已发送测试预览消息到叮咚服务器');
    }
  }
}

await ctx.stop();
fs.rmSync(path.join(process.cwd(), '.plugin-test-tmp'), { recursive: true, force: true });
