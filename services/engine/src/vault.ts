import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

export class Vault {
  name: string;
  directory: string;
  key: Buffer;

  constructor(directory: string, name = 'default') {
    if (!/^[a-z][a-z0-9_-]{0,63}$/.test(name)) {
      throw new Error('Invalid vault name');
    }
    this.name = name;
    this.directory = directory;
    fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
    const keyFile = path.join(directory, 'vault.key');
    if (!fs.existsSync(keyFile)) {
      fs.writeFileSync(keyFile, crypto.randomBytes(32), { mode: 0o600, flag: 'wx' });
    }
    this.key = fs.readFileSync(keyFile);
    if (this.key.length !== 32) {
      throw new Error('加密密钥文件无效');
    }
  }

  save(state) {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', this.key, iv);
    const content = Buffer.concat([cipher.update(JSON.stringify(state), 'utf8'), cipher.final()]);
    const file = path.join(this.directory, this.name + '.vault');
    fs.writeFileSync(file + '.tmp', Buffer.concat([iv, cipher.getAuthTag(), content]), { mode: 0o600 });
    fs.renameSync(file + '.tmp', file);
  }

  load() {
    const file = path.join(this.directory, this.name + '.vault');
    if (!fs.existsSync(file)) {
      return undefined;
    }
    const data = fs.readFileSync(file);
    const decipher = crypto.createDecipheriv('aes-256-gcm', this.key, data.subarray(0, 12));
    decipher.setAuthTag(data.subarray(12, 28));
    return JSON.parse(Buffer.concat([decipher.update(data.subarray(28)), decipher.final()]).toString('utf8'));
  }

  clear() {
    fs.rmSync(path.join(this.directory, this.name + '.vault'), { force: true });
  }
}
