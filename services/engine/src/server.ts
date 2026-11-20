import crypto from 'node:crypto';
import fs from 'node:fs';
import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Context } from '@cordisjs/core';
import { AIService } from './ai.ts';
import { CredentialManager } from './credentials.ts';
import * as digestPlugin from './digest.ts';
import { createHttpService } from './http.ts';
import { loadDirectoryPlugins } from './loader.ts';
import { renderDocument } from './render.ts';
import { EngineError, SourceRegistry, TaskEngine } from './sources.ts';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export async function createEngineRuntime({
  directory = path.resolve(process.env.DATA_DIR || path.join(root, 'data')),
  pluginDirs = [path.resolve(process.env.PLUGINS_DIR || path.join(root, 'plugins'))],
  publish,
  render = renderDocument,
}: {
  directory?: string;
  pluginDirs?: string[];
  publish?: (payload: Record<string, unknown>) => Promise<void>;
  render?: typeof renderDocument;
} = {}) {
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  const ctx = new Context();
  const httpService = createHttpService();
  const ai = new AIService(directory, httpService);
  const credentials = new CredentialManager(directory, httpService);
  const registry = new SourceRegistry(credentials);

  ctx.provide('http', httpService, true);
  ctx.provide('ai', ai, true);
  ctx.provide('credentials', credentials, true);
  ctx.provide('source', registry, true);
  ctx.provide('render', render, true);

  ctx.plugin(digestPlugin);
  await loadDirectoryPlugins(ctx, pluginDirs, registry);
  await ctx.start();

  const defaultPublish = async (payload) => {
    const sendToken = process.env.DINGDONG_SEND_TOKEN;
    if (!sendToken) {
      throw new Error('服务器未配置 DINGDONG_SEND_TOKEN');
    }
    const relayUrl = (process.env.RELAY_INTERNAL_URL || 'http://127.0.0.1:18080').replace(/\/+$/, '');
    const res = await fetch(`${relayUrl}/v1/messages`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${sendToken}`,
      },
      body: JSON.stringify(payload),
      signal: AbortSignal.timeout(15000),
      redirect: 'error',
    });
    if (!res.ok) {
      throw new Error(`中转服务器未接收消息（HTTP ${res.status}）`);
    }
  };

  const engine = new TaskEngine({
    directory,
    registry,
    credentials,
    ai,
    http: httpService,
    publish: publish || defaultPublish,
    render,
  });

  return { ctx, engine, registry, credentials, ai, httpService, directory };
}

export function createEngineServer({
  runtime,
  readToken = process.env.DINGDONG_READ_TOKEN || '',
  webDir = path.join(root, 'web'),
}: {
  runtime: Awaited<ReturnType<typeof createEngineRuntime>>;
  readToken?: string;
  webDir?: string;
}) {
  const { engine, registry, credentials, directory } = runtime;
  const adminFile = path.join(directory, 'admin.key');
  if (!fs.existsSync(adminFile)) {
    fs.writeFileSync(adminFile, crypto.randomBytes(32).toString('hex'), { mode: 0o600, flag: 'wx' });
  }
  const adminKey = fs.readFileSync(adminFile, 'utf8').trim();
  const hash = (value) => crypto.createHash('sha256').update(String(value || '')).digest();
  const equal = (a, b) => crypto.timingSafeEqual(hash(a), hash(b));
  const sessions = new Map();
  let queue = Promise.resolve();
  const serial = (fn) => {
    const job = queue.then(fn);
    queue = job.catch(() => {});
    return job;
  };
  let failures = 0;
  let failureWindow = Date.now();

  async function readBody(req) {
    let size = 0;
    const chunks = [];
    for await (const chunk of req) {
      size += chunk.length;
      if (size > 65536) {
        throw new EngineError('请求体过大', 413);
      }
      chunks.push(chunk);
    }
    const text = Buffer.concat(chunks).toString('utf8').trim();
    return text ? JSON.parse(text) : {};
  }

  function send(res, status, data, headers = {}) {
    res.writeHead(status, {
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      ...headers,
    });
    res.end(JSON.stringify(data));
  }

  function checkReadToken(req) {
    if (!readToken || readToken.length < 32) {
      throw new EngineError('服务器尚未配置 DINGDONG_READ_TOKEN', 503);
    }
    const header = req.headers.authorization || '';
    if (!equal(header, 'Bearer ' + readToken)) {
      throw new EngineError('接收密钥无效，请检查服务器设置', 401);
    }
  }

  function checkAdminSession(req) {
    const cookie = req.headers.cookie || '';
    const match = /(?:^|;\s*)dingdong_admin=([a-f0-9]{64})(?:;|$)/.exec(cookie);
    const token = match?.[1];
    if (!token || (sessions.get(token) || 0) < Date.now()) {
      throw new EngineError('请先登录管理页', 401);
    }
  }

  const server = http.createServer(async (req, res) => {
    const host = req.headers.host || '';
    if (!/^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/.test(host)) {
      return send(res, 403, { error: '请通过反向代理或本地端口访问' });
    }
    const url = new URL(req.url, `http://${host}`);
    const pathname = url.pathname;

    try {
      // Public health endpoints (also used by App to detect engine availability)
      if ((pathname === '/health' || pathname === '/v1/engine/health') && req.method === 'GET') {
        return send(res, 200, {
          service: 'dingdong-engine',
          version: '0.2.0',
          plugins: [...registry.plugins.keys()],
        });
      }

      // Mobile App API: /v1/engine/snapshot & /v1/engine/commands
      if (pathname === '/v1/engine/snapshot' && req.method === 'GET') {
        checkReadToken(req);
        return send(res, 200, engine.snapshot());
      }
      if (pathname === '/v1/engine/commands' && req.method === 'POST') {
        checkReadToken(req);
        const input = await readBody(req);
        return send(res, 200, await serial(() => engine.command(input)));
      }

      // Mobile App Generic Credentials API: /v1/engine/credentials/:id[/:action]
      const credMatch = /^\/v1\/engine\/credentials\/([a-z][a-z0-9-]{0,63})(?:\/([a-z]+))?$/.exec(pathname);
      if (credMatch) {
        const [, authId, action] = credMatch;
        if (action === 'import' && req.method === 'POST') {
          const bearer = (req.headers.authorization || '').replace(/^Bearer /, '');
          const byPair = credentials.consumePairing(authId, bearer);
          const byRead = readToken.length >= 32 && equal(bearer, readToken);
          if (!byPair && !byRead) {
            return send(res, 401, { error: '本次授权码已失效，请重新发起授权' });
          }
          const input = await readBody(req);
          const status = await serial(() => credentials.importCredential(authId, input));
          return send(res, 200, status);
        }
        checkReadToken(req);
        if (!action && req.method === 'GET') {
          return send(res, 200, credentials.status(authId));
        }
        if (action === 'pair' && req.method === 'POST') {
          return send(res, 200, credentials.createPairing(authId));
        }
        if (action === 'verify' && req.method === 'POST') {
          return send(res, 200, await serial(() => credentials.verifySaved(authId)));
        }
        if (action === 'logout' && req.method === 'POST') {
          return send(res, 200, await serial(() => credentials.logout(authId)));
        }
        return send(res, 404, { error: '凭据接口不存在' });
      }

      // Static Web Dashboard assets
      const assets = {
        '/': ['index.html', 'text/html; charset=utf-8'],
        '/app.js': ['app.js', 'text/javascript; charset=utf-8'],
        '/style.css': ['style.css', 'text/css; charset=utf-8'],
      };
      if (assets[pathname] && req.method === 'GET') {
        const [file, type] = assets[pathname];
        res.writeHead(200, {
          'Content-Type': type,
          'Cache-Control': 'no-store',
          'Content-Security-Policy':
            "default-src 'self'; script-src 'self'; style-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'",
          'X-Content-Type-Options': 'nosniff',
        });
        return res.end(fs.readFileSync(path.join(webDir, file)));
      }

      // Loopback Web Dashboard API
      if (pathname === '/api/login' && req.method === 'POST') {
        if (Date.now() - failureWindow > 60_000) {
          failures = 0;
          failureWindow = Date.now();
        }
        if (failures >= 8) {
          return send(res, 429, { error: '尝试过于频繁，请稍后再试' });
        }
        const input = await readBody(req);
        if (!equal(input.key, adminKey)) {
          failures++;
          return send(res, 401, { error: '管理密钥不正确' });
        }
        const token = crypto.randomBytes(32).toString('hex');
        for (const [k, exp] of sessions) {
          if (exp < Date.now()) sessions.delete(k);
        }
        sessions.set(token, Date.now() + 8 * 3600_000);
        return send(
          res,
          200,
          { ok: true },
          { 'Set-Cookie': `dingdong_admin=${token}; HttpOnly; SameSite=Strict; Path=/; Max-Age=28800` },
        );
      }

      if (pathname.startsWith('/api/')) {
        if (req.method === 'POST' && req.headers.origin && ![`http://${host}`, `https://${host}`].includes(req.headers.origin)) {
          return send(res, 403, { error: '来源不匹配' });
        }
        checkAdminSession(req);
        if (pathname === '/api/snapshot' && req.method === 'GET') {
          return send(res, 200, engine.snapshot());
        }
        if (pathname === '/api/commands' && req.method === 'POST') {
          const input = await readBody(req);
          return send(res, 200, await serial(() => engine.command(input)));
        }
        const webCredMatch = /^\/api\/credentials\/([a-z][a-z0-9-]{0,63})\/(import|verify|logout)$/.exec(pathname);
        if (webCredMatch && req.method === 'POST') {
          const [, authId, action] = webCredMatch;
          if (action === 'import') {
            const input = await readBody(req);
            return send(res, 200, await serial(() => credentials.importCredential(authId, input)));
          }
          if (action === 'verify') {
            return send(res, 200, await serial(() => credentials.verifySaved(authId)));
          }
          if (action === 'logout') {
            return send(res, 200, await serial(() => credentials.logout(authId)));
          }
        }
      }

      return send(res, 404, { error: '接口不存在' });
    } catch (error) {
      if (error instanceof EngineError) {
        return send(res, error.status, { error: error.message });
      }
      return send(res, 400, { error: engine.redact(error?.message || '请求处理失败') });
    }
  });

  return { server, adminKey, serial };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const runtime = await createEngineRuntime();
  const { server, serial } = createEngineServer({ runtime });
  let tickPending = false;
  const timer = setInterval(() => {
    if (tickPending) return;
    tickPending = true;
    void serial(() => {
      void runtime.engine
        .tick()
        .catch(() => {})
        .finally(() => {
          tickPending = false;
        });
    }).catch(() => {
      tickPending = false;
    });
  }, 15_000);
  timer.unref();

  const port = Number(process.env.PORT || 18890);
  const host = process.env.HOST || '127.0.0.1';
  server.listen(port, host, () => {
    console.log(`Dingdong Engine listening on http://${host}:${port} (${runtime.registry.plugins.size} plugins)`);
  });
}
