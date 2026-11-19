import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export class Vault {
  constructor(directory, name = 'bilibili') {
    if (!/^[a-z][a-z0-9-]*$/.test(name)) throw new Error('Invalid vault name');
    this.name = name;
    this.directory = directory;
    fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
    const keyFile = path.join(directory, 'vault.key');
    if (!fs.existsSync(keyFile)) fs.writeFileSync(keyFile, crypto.randomBytes(32), { mode: 0o600, flag: 'wx' });
    this.key = fs.readFileSync(keyFile);
    if (this.key.length !== 32) throw new Error('会话加密密钥无效');
  }
  save(state) {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', this.key, iv);
    const content = Buffer.concat([cipher.update(JSON.stringify(state), 'utf8'), cipher.final()]);
    const file = path.join(this.directory, this.name + '.session');
    fs.writeFileSync(file + '.tmp', Buffer.concat([iv, cipher.getAuthTag(), content]), { mode: 0o600 });
    fs.renameSync(file + '.tmp', file);
  }
  load() {
    const file = path.join(this.directory, this.name + '.session');
    if (!fs.existsSync(file)) return undefined;
    const data = fs.readFileSync(file);
    const decipher = crypto.createDecipheriv('aes-256-gcm', this.key, data.subarray(0, 12));
    decipher.setAuthTag(data.subarray(12, 28));
    return JSON.parse(Buffer.concat([decipher.update(data.subarray(28)), decipher.final()]).toString());
  }
  clear() { fs.rmSync(path.join(this.directory, this.name + '.session'), { force: true }); }
}

export function bilibiliCookies(header) {
  if (typeof header !== 'string' || header.length > 32000 || /[\r\n]/.test(header)) throw new Error('会话格式无效');
  const allowed = new Set(['SESSDATA', 'bili_jct', 'DedeUserID', 'DedeUserID__ckMd5', 'sid', 'buvid3', 'buvid4', 'b_nut', 'bili_ticket', 'bili_ticket_expires']);
  const cookies = new Map();
  for (const part of header.split(';')) {
    const pos = part.indexOf('=');
    if (pos < 1) continue;
    const name = part.slice(0, pos).trim();
    const value = part.slice(pos + 1).trim();
    if (allowed.has(name) && value) cookies.set(name, { name, value, domain: '.bilibili.com', path: '/', secure: true, httpOnly: name === 'SESSDATA', sameSite: 'Lax' });
  }
  if (!cookies.has('SESSDATA') || !cookies.has('DedeUserID')) throw new Error('尚未获取 B 站登录会话，请先完成登录');
  return [...cookies.values()];
}
