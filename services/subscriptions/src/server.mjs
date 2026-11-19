import http from 'node:http';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Context } from '@cordisjs/core';
import { studioPlugin } from './studio-runtime.mjs';
import { Vault } from './vault.mjs';
import { bilibiliPlugin } from './bilibili.mjs';
import { accountRoutes } from './accounts.mjs';
import { SubscriptionError, SubscriptionRegistry, Subscriptions, subscriptionRoutes } from './subscriptions.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const directory = path.resolve(process.env.DATA_DIR || path.join(root, 'data'));
const vault = new Vault(directory);
const adminFile = path.join(directory, 'admin.key');
if (!fs.existsSync(adminFile)) fs.writeFileSync(adminFile, crypto.randomBytes(32).toString('hex'), { mode: 0o600, flag: 'wx' });
const admin = fs.readFileSync(adminFile, 'utf8').trim();
const hash = value => crypto.createHash('sha256').update(String(value || '')).digest();
const equal = (a, b) => crypto.timingSafeEqual(hash(a), hash(b));
const ctx = new Context();
const registry = new SubscriptionRegistry();
let login;
ctx.plugin(bilibiliPlugin, { vault, registry, register: value => { login = value; } });
let runtime;
ctx.plugin(studioPlugin, { directory, registry, login, register: value => { runtime = value; } });
await ctx.start();
const sessions = new Map();
let pair;
let queue = Promise.resolve();
const serial = fn => { const job = queue.then(fn); queue = job.catch(() => {}); return job; };
let failures = 0;
let failureWindow = Date.now();

async function body(req) {
  let size = 0; const chunks = [];
  for await (const chunk of req) { size += chunk.length; if (size > 64000) throw new Error('请求过大'); chunks.push(chunk); }
  return JSON.parse(Buffer.concat(chunks).toString() || '{}');
}
function send(res, status, data, headers = {}) {
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', ...headers });
  res.end(JSON.stringify(data));
}
const accountSerial = fn => serial(() => {
  if (subscriptions.running.size) throw new Error('请等待当前任务完成或先停止任务，再操作平台账号');
  return fn();
});
const accountApis = Object.entries(runtime.logins).map(([platform, login]) => accountRoutes({ credential: process.env.DINGDONG_READ_TOKEN, login, serial: accountSerial, body, send, platform, followings: platform === 'bilibili' ? input => runtime.services.bilibili.followings(input) : undefined }));
const subscriptions = new Subscriptions({
  directory, registry, runtime, account: id => runtime.logins[id]?.status || { state: 'idle' },
  publish: async payload => {
    if (!process.env.DINGDONG_SEND_TOKEN) throw new Error('服务器未配置推送密钥');
    const response = await fetch((process.env.RELAY_INTERNAL_URL || 'http://127.0.0.1:18080') + '/v1/messages', {
      method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + process.env.DINGDONG_SEND_TOKEN },
      body: JSON.stringify(payload), signal: AbortSignal.timeout(15000), redirect: 'error',
    });
    if (!response.ok) throw new Error(`中转服务器未接收消息（HTTP ${response.status}）`);
  },
});
const subscriptionApi = subscriptionRoutes({ subscriptions, credential: process.env.DINGDONG_READ_TOKEN, serial, body, send });
let tickPending = false;
const timer = setInterval(() => {
  if (tickPending) return;
  tickPending = true;
  // Do not hold the command queue during collection: cancel must remain responsive.
  void serial(() => {
    void subscriptions.tick().catch(() => {}).finally(() => { tickPending = false; });
  }).catch(() => { tickPending = false; });
}, 15000);
timer.unref();
for (const login of Object.values(runtime.logins)) if (login.vault.load()) {
  login.status = { state: 'checking', message: '正在恢复并验证服务器账号' };
  void serial(() => login.verify('saved')).catch(() => {});
}
const server = http.createServer(async (req, res) => {
  const host = req.headers.host || '';
  if (!/^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(host)) return send(res, 403, { error: '请通过本地端口或 SSH 转发访问' });
  const url = new URL(req.url, `http://${host}`);
  const platform = url.searchParams.get('platform') || 'bilibili';
  const browserLogin = Object.hasOwn(runtime.logins, platform) && runtime.logins[platform];
  if (!browserLogin) return send(res, 400, { error: '平台不存在' });
  if (req.method === 'POST' && req.headers.origin && ![`http://${host}`, `https://${host}`].includes(req.headers.origin)) return send(res, 403, { error: '来源不匹配' });
  try {
    for (const api of accountApis) if (await api(req, res, url.pathname)) return;
    if (await subscriptionApi(req, res, url.pathname)) return;
    if (url.pathname === '/health' && req.method === 'GET') return send(res, 200, { service: 'dingdong-node', plugins: [...registry.plugins.keys()].filter(id => id !== 'bilibili-following') });
    const assets = { '/': ['index.html', 'text/html; charset=utf-8'], '/app.js': ['app.js', 'text/javascript; charset=utf-8'], '/dashboard.js': ['dashboard.js', 'text/javascript; charset=utf-8'], '/style.css': ['style.css', 'text/css; charset=utf-8'] };
    if (assets[url.pathname] && req.method === 'GET') {
      const [name, type] = assets[url.pathname];
      res.writeHead(200, { 'Content-Type': type, 'Cache-Control': 'no-store', 'Content-Security-Policy': "default-src 'self'; img-src 'self' blob:; script-src 'self'; style-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'", 'X-Content-Type-Options': 'nosniff' });
      return res.end(fs.readFileSync(path.join(root, 'web', name)));
    }
    if (url.pathname === '/api/login' && req.method === 'POST') {
      if (Date.now() - failureWindow > 60000) { failures = 0; failureWindow = Date.now(); }
      if (failures >= 8) return send(res, 429, { error: '请稍后再试' });
      if (!equal((await body(req)).key, admin)) { failures++; return send(res, 401, { error: '管理密钥不正确' }); }
      const token = crypto.randomBytes(32).toString('hex');
      for (const [key, expires] of sessions) if (expires < Date.now()) sessions.delete(key);
      if (sessions.size >= 8) sessions.delete(sessions.keys().next().value);
      sessions.set(token, Date.now() + 8 * 3600000);
      return send(res, 200, { ok: true }, { 'Set-Cookie': `dingdong_admin=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800` });
    }
    if (url.pathname === '/api/bilibili/import' && req.method === 'POST') {
      const token = (req.headers.authorization || '').replace(/^Bearer /, '');
      if (!pair || pair.expires < Date.now() || !equal(token, pair.code)) return send(res, 401, { error: '配对码已失效，请在管理页重新生成' });
      pair = undefined;
      const input = await body(req);
      const status = await serial(() => login.importPhone(input.cookie));
      return send(res, 200, status);
    }
    const session = /(?:^|;\s*)dingdong_admin=([a-f0-9]{64})(?:;|$)/.exec(req.headers.cookie || '')?.[1];
    if (!session || (sessions.get(session) || 0) < Date.now()) return send(res, 401, { error: '请先登录管理页' });
    if (req.method === 'GET' && url.pathname === '/api/subscriptions') return send(res, 200, subscriptions.snapshot());
    if (req.method === 'GET' && url.pathname === '/api/status') return send(res, 200, { ...browserLogin.status, plugin: '平台账号验证', framework: 'Cordis', remoteOpen: !!browserLogin.page && !browserLogin.page.isClosed() });
    if (req.method === 'GET' && url.pathname === '/api/browser/frame') {
      const frame = await serial(() => browserLogin.screenshot());
      res.writeHead(200, { 'Content-Type': 'image/jpeg', 'Cache-Control': 'no-store' }); return res.end(frame);
    }
    if (req.method !== 'POST') return send(res, 404, { error: '接口不存在' });
    // Browser requests using an ambient session must have a same-origin Origin.
    if (!req.headers.origin) return send(res, 403, { error: '缺少请求来源' });
    const input = await body(req);
    if (url.pathname === '/api/logout') {
      sessions.delete(session);
      return send(res, 200, { ok: true }, { 'Set-Cookie': 'dingdong_admin=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0' });
    }
    if (url.pathname === '/api/subscriptions/commands') {
      try { return send(res, 200, await serial(() => subscriptions.command(input))); }
      catch (error) {
        if (error instanceof SubscriptionError) return send(res, error.status, { error: runtime.store.redact(error.message) });
        throw error;
      }
    }
    if (url.pathname === '/api/pair') {
      pair = { code: crypto.randomBytes(12).toString('hex'), expires: Date.now() + 10 * 60000 };
      return send(res, 200, pair);
    }
    if (url.pathname === '/api/browser/open') { await accountSerial(() => browserLogin.login()); return send(res, 200, { ok: true }); }
    if (url.pathname === '/api/browser/input') { await accountSerial(() => browserLogin.input(input)); return send(res, 200, { ok: true }); }
    if (url.pathname === '/api/bilibili/verify') return send(res, 200, await accountSerial(() => browserLogin.verify()));
    if (url.pathname === '/api/bilibili/logout') { await accountSerial(() => browserLogin.logout()); return send(res, 200, { ok: true }); }
    return send(res, 404, { error: '接口不存在' });
  } catch (error) {
    const message = /B 站|尚未|请先|会话|操作|请求|格式/.test(error.message) ? error.message.slice(0, 240) : '操作未完成，请检查浏览器环境和网络后重试';
    send(res, 400, { error: message });
  }
});
server.requestTimeout = 45000;
server.listen(Number(process.env.PORT || 18890), '127.0.0.1', () => console.log(`Dingdong Node: http://127.0.0.1:${server.address().port} (admin key: ${adminFile})`));
async function stop() {
  clearInterval(timer); server.close(); subscriptions.controller?.abort();
  await queue;
  while (subscriptions.running.size) await new Promise(resolve => setTimeout(resolve, 50));
  await ctx.stop(); process.exit(0);
}
process.on('SIGINT', stop); process.on('SIGTERM', stop);
