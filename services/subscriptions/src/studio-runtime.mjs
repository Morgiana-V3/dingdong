import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import { Vault } from './vault.mjs';
import { PlatformLogin } from './platform-login.mjs';
import { browserAdapter } from './browser-adapter.mjs';
import { utilityProcess } from './utility-process.mjs';
import { browserProfile } from './account-profile.mjs';
import { aiFetch } from './ai-network.mjs';
const require = createRequire(import.meta.url);
const { Engine } = require('../build/studio/src/engine.cjs');
const { Services } = require('../build/studio/src/services.cjs');
const { Bilibili } = require('../build/studio/src/bilibili.cjs');
const { Tieba } = require('../build/studio/src/tieba.cjs');
const { XSourceService } = require('../build/studio/src/x.cjs');
const { XHTTP } = require('../build/studio/src/x-http.cjs');
const { Xiaohongshu } = require('../build/studio/src/xiaohongshu.cjs');
const { digestPlugin } = require('../build/studio/src/digest.cjs');

export function studioPlugin(ctx, { directory, registry, login, register }) {
  const runtime = new StudioRuntime(directory, registry, login);
  register(runtime);
  ctx.on('dispose', () => runtime.close());
}
export class StudioRuntime {
  constructor(directory, registry, login) {
    this.logins = { bilibili: login, x: new PlatformLogin(new Vault(directory, 'x'), 'x'), xiaohongshu: new PlatformLogin(new Vault(directory, 'xiaohongshu'), 'xiaohongshu') };
    this.providerVault = new Vault(directory, 'providers');
    this.providers = this.providerVault.load() || [];
    this.store = { state: { providers: this.providers }, decrypt: value => value, redact: value => {
      let text = String(value);
      for (const provider of this.providers) if (provider.secret) text = text.replaceAll(provider.secret, '[密钥已隐藏]');
      return text;
    } };
    this.services = new Services(this.store, aiFetch);
    const bili = browserAdapter(login);
    this.services.bilibili = new Bilibili(bili.session, bili.BrowserWindow);
    this.services.tieba = new Tieba({ fetch });
    const x = browserAdapter(this.logins.x);
    const xCookies = { load: () => this.currentXCookies || [], save: value => { this.currentXCookies = value; }, clear: () => { this.currentXCookies = []; } };
    this.xHttp = new XHTTP(directory, utilityProcess, async () => {
      const proxy = process.env.X_PROXY || process.env.BROWSER_PROXY;
      if (!proxy) return 'DIRECT';
      const url = new URL(proxy);
      if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) throw new Error('X 代理需使用无账号的 HTTP/HTTPS 地址');
      return `${url.protocol === 'https:' ? 'HTTPS' : 'PROXY'} ${url.host}`;
    });
    this.services.x = new XSourceService(x.session, x.BrowserWindow, undefined, this.xHttp, xCookies);
    const xhs = browserAdapter(this.logins.xiaohongshu);
    this.services.xiaohongshu = new Xiaohongshu(xhs.session, xhs.BrowserWindow);
    this.logins.x.check = async () => {
      this.currentXCookies = await this.logins.x.context.cookies('https://x.com');
      const account = await this.services.x.account();
      if (!account.hasSession) throw new Error('尚未完成 X 登录');
      const result = await this.services.x.following({ accountId: account.id });
      return { account: await browserProfile(this.logins.x, 'x', account.id, account.id), itemCount: result.posts.length };
    };
    this.logins.xiaohongshu.check = async () => {
      const account = await this.services.xiaohongshu.account();
      if (!account.loggedIn) throw new Error('尚未完成小红书登录');
      const result = await this.services.xiaohongshu.feed({ accountId: account.id });
      return { account: await browserProfile(this.logins.xiaohongshu, 'xiaohongshu', account.id, account.name), itemCount: result.notes.length };
    };
    this.plugins = [];
    const base = fileURLToPath(new URL('../build/studio/examples/', import.meta.url));
    const accounts = { bilibili: ['bilibili', '哔哩哔哩'], x: ['x', 'X'], xiaohongshu: ['xiaohongshu', '小红书'] };
    for (const name of ['bilibili', 'tieba', 'x', 'xiaohongshu']) {
      const location = path.join(base, name);
      const manifest = JSON.parse(fs.readFileSync(path.join(location, 'plugin.json'), 'utf8'));
      this.plugins.push({ ...manifest, location });
      const account = accounts[name];
      registry.register({ ...manifest, ...(account ? { accountId: account[0], accountName: account[1] } : {}), studio: true,
        fields: manifest.fields.map(field => ['accountId', 'accountMid'].includes(field.key) ? { ...field, type: 'account', required: false, help: '保存任务后，在右侧「所需账号」登录，执行时自动关联。' } : field.key === 'upIds' ? { ...field, required: false, help: '可先保存任务并登录，再从关注列表选择。未选择时不会执行。' } : field),
        execute: (task, signal, trace) => this.execute(task, signal, trace) });
    }
    registry.register({ ...digestPlugin, studio: true });
    this.engine = new Engine(this.store, { list: () => this.plugins }, this.services, utilityProcess, () => {});
  }
  async execute(task, signal, trace) {
    if (task.pluginId === 'x-interests') {
      await this.logins.x.init();
      this.currentXCookies = await this.logins.x.context.cookies('https://x.com');
    }
    const plugin = this.plugins.find(plugin => plugin.id === task.pluginId);
    const controller = new AbortController();
    const abort = () => controller.abort();
    signal?.addEventListener('abort', abort, { once: true });
    try {
      signal?.throwIfAborted();
      return await this.engine.execute(plugin, structuredClone(task), controller, trace);
    } finally { signal?.removeEventListener('abort', abort); }
  }
  publicProviders() { return this.providers.map(({ secret, ...provider }) => ({ ...provider, hasKey: !!secret })); }
  async listModels(input) {
    const service = new Services(this.store, (url, options) => aiFetch(url, {
      ...options,
      signal: AbortSignal.any([options.signal, AbortSignal.timeout(25000)]),
    }));
    return (await service.listModels(input)).slice(0, 3000);
  }
  saveProvider(input) {
    const existing = this.providers.find(provider => provider.id === input.id);
    const { baseUrl, key } = this.services.providerConnection({ ...input, key: input.key || '' });
    if (typeof input.name !== 'string' || !input.name.trim() || input.name.length > 80) throw new Error('请填写 AI 配置名称');
    if (typeof input.model !== 'string' || !input.model.trim() || input.model.length > 300) throw new Error('请填写模型 ID');
    const maxOutputTokens = Number(input.maxOutputTokens || 8000);
    if (!Number.isInteger(maxOutputTokens) || maxOutputTokens < 100 || maxOutputTokens > 100000) throw new Error('输出上限需为 100–100000');
    const value = { id: existing?.id || crypto.randomUUID(), name: input.name.trim(), baseUrl, model: input.model.trim(), maxOutputTokens, secret: key };
    if (existing) Object.assign(existing, value); else this.providers.push(value);
    this.providerVault.save(this.providers);
  }
  removeProvider(id) { const index = this.providers.findIndex(provider => provider.id === id); if (index < 0) throw new Error('AI 配置不存在'); this.providers.splice(index, 1); this.providerVault.save(this.providers); }
  async close() { this.xHttp.stop(); for (const login of Object.values(this.logins)) await login.browser?.close(); }
}
