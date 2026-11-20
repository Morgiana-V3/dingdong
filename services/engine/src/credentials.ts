import crypto from 'node:crypto';
import { Vault } from './vault.ts';

import type { PluginAuth, HttpService, CredentialValue } from '../sdk/dingdong-plugin.d.ts';

export class AuthExpiredError extends Error {
  authId: string;

  constructor(authId: string, message = '登录态已失效，请重新授权') {
    super(message);
    this.name = 'AuthExpiredError';
    this.authId = authId;
  }
}

export function parseCookieString(header) {
  if (typeof header !== 'string' || header.length > 64000 || /[\r\n]/.test(header)) {
    throw new Error('Cookie 格式无效');
  }
  const map = {};
  for (const part of header.split(';')) {
    const idx = part.indexOf('=');
    if (idx < 1) continue;
    const key = part.slice(0, idx).trim();
    const val = part.slice(idx + 1).trim();
    if (key && val) {
      map[key] = val;
    }
  }
  return map;
}

interface StoredCredential {
  value: CredentialValue;
  account: Record<string, unknown> | null;
  checkedAt: number;
}

interface CredentialStatusRecord {
  state: string;
  account: Record<string, unknown> | null;
  checkedAt: number | null;
  message: string;
}

export class CredentialManager {
  directory: string;
  http: HttpService;
  definitions: Map<string, PluginAuth>;
  vaults: Map<string, Vault>;
  statuses: Map<string, CredentialStatusRecord>;
  pairings: Map<string, { code: string; expires: number }>;

  constructor(directory: string, http: HttpService) {
    this.directory = directory;
    this.http = http;
    this.definitions = new Map();
    this.vaults = new Map();
    this.statuses = new Map();
    this.pairings = new Map();
  }

  register(authDef) {
    if (!authDef) return;
    this.definitions.set(authDef.id, authDef);
    if (!this.vaults.has(authDef.id)) {
      this.vaults.set(authDef.id, new Vault(this.directory, 'cred-' + authDef.id));
    }
    if (!this.statuses.has(authDef.id)) {
      const saved = this.vaults.get(authDef.id).load();
      this.statuses.set(authDef.id, {
        state: saved ? 'ready' : 'idle',
        account: saved?.account || null,
        checkedAt: saved?.checkedAt || null,
        message: saved ? '已保存凭据' : '尚未配置',
      });
    }
  }

  definition(authId) {
    const def = this.definitions.get(authId);
    if (!def) {
      throw new Error(`凭据定义不存在: ${authId}`);
    }
    return def;
  }

  status(authId) {
    const def = this.definitions.get(authId);
    const st = this.statuses.get(authId) || { state: 'idle', account: null, checkedAt: null, message: '尚未配置' };
    return {
      id: authId,
      name: def?.name || authId,
      type: def?.type || 'token',
      ...(def?.type === 'web-cookie'
        ? {
            loginUrl: def.loginUrl,
            cookieDomains: def.cookieDomains,
            requiredCookies: def.requiredCookies,
          }
        : {
            help: def?.help || '',
            placeholder: def?.placeholder || '',
          }),
      ...st,
    };
  }

  get(authId) {
    const vault = this.vaults.get(authId);
    const saved = vault?.load();
    return saved?.value ?? null;
  }

  markExpired(authId: string, message?: string) {
    const current = this.statuses.get(authId);
    this.statuses.set(authId, {
      account: current?.account ?? null,
      state: 'expired',
      checkedAt: Date.now(),
      message: message || '凭据已失效，请重新授权',
    });
  }

  createPairing(authId) {
    this.definition(authId);
    const pairing = {
      code: crypto.randomBytes(16).toString('hex'),
      expires: Date.now() + 10 * 60_000,
    };
    this.pairings.set(authId, pairing);
    return pairing;
  }

  consumePairing(authId, token) {
    const pairing = this.pairings.get(authId);
    this.pairings.delete(authId);
    if (!pairing || pairing.expires < Date.now() || typeof token !== 'string') {
      return false;
    }
    const a = crypto.createHash('sha256').update(token).digest();
    const b = crypto.createHash('sha256').update(pairing.code).digest();
    return crypto.timingSafeEqual(a, b);
  }

  async importCredential(authId, input) {
    const def = this.definition(authId);
    const vault = this.vaults.get(authId);
    const previous = vault.load();
    let value;
    if (def.type === 'web-cookie') {
      const rawCookie = typeof input?.cookie === 'string' ? input.cookie.trim() : '';
      const parsed = parseCookieString(rawCookie);
      const missing = def.requiredCookies.filter((name) => !parsed[name]);
      if (missing.length) {
        throw new Error(`缺少必要的登录 Cookie：${missing.join(', ')}`);
      }
      value = { cookie: rawCookie, cookies: parsed };
    } else {
      const token = typeof input?.token === 'string' ? input.token.trim() : '';
      if (!token || token.length > 16000) {
        throw new Error('请填写有效的 Token / 密钥');
      }
      value = { token };
    }

    let account = null;
    try {
      if (def.verify) {
        const result = await def.verify(value as never, { http: this.http });
        account =
          typeof result === 'object' && result
            ? (result as Record<string, unknown>)
            : { name: String(result || '已验证') };
      }
      const checkedAt = Date.now();
      vault.save({ value, account, checkedAt });
      const st = { state: 'ready', account, checkedAt, message: '凭据已验证并加密保存' };
      this.statuses.set(authId, st);
      return this.status(authId);
    } catch (error) {
      if (previous) {
        vault.save(previous);
      }
      throw new Error(error?.message || '凭据验证失败');
    }
  }

  async verifySaved(authId) {
    const def = this.definition(authId);
    const vault = this.vaults.get(authId);
    const saved = vault.load();
    if (!saved?.value) {
      const st = { state: 'idle', account: null, checkedAt: Date.now(), message: '尚未配置凭据' };
      this.statuses.set(authId, st);
      return this.status(authId);
    }
    try {
      let account = saved.account;
      if (def.verify) {
        const result = await def.verify(saved.value as never, { http: this.http });
        account =
          typeof result === 'object' && result
            ? (result as Record<string, unknown>)
            : { name: String(result || '已验证') };
      }
      const checkedAt = Date.now();
      vault.save({ ...saved, account, checkedAt });
      this.statuses.set(authId, { state: 'ready', account, checkedAt, message: '凭据有效' });
      return this.status(authId);
    } catch (error) {
      this.markExpired(authId, error?.message || '凭据验证失败');
      throw error;
    }
  }

  logout(authId) {
    this.definition(authId);
    this.pairings.delete(authId);
    this.vaults.get(authId)?.clear();
    this.statuses.set(authId, { state: 'idle', account: null, checkedAt: Date.now(), message: '已清除凭据' });
    return this.status(authId);
  }
}
