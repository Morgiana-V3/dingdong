import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Vault, bilibiliCookies } from '../src/vault.mjs';

test('session is encrypted, survives restart and rejects tampering', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dingdong-vault-'));
  try {
    const state = { cookies: [{ name: 'SESSDATA', value: 'fictional-sensitive-session' }], origins: [] };
    new Vault(directory).save(state);
    const file = path.join(directory, 'bilibili.session');
    const data = fs.readFileSync(file);
    assert.ok(!data.includes(Buffer.from('fictional-sensitive-session')));
    assert.deepEqual(new Vault(directory).load(), state);
    data[data.length - 1] ^= 1;
    fs.writeFileSync(file, data);
    assert.throws(() => new Vault(directory).load());
    new Vault(directory).clear();
    assert.equal(new Vault(directory).load(), undefined);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('phone import only accepts necessary Bilibili cookies and rejects malformed input', () => {
  const cookies = bilibiliCookies('SESSDATA=fictional%3Dvalue; DedeUserID=100; foreign_secret=hidden; Path=/');
  assert.equal(cookies.length, 2);
  assert.equal(cookies[0].value, 'fictional%3Dvalue');
  assert.ok(cookies.every(cookie => cookie.domain === '.bilibili.com' && cookie.secure));
  assert.throws(() => bilibiliCookies('SESSDATA=test\r\nX: bad; DedeUserID=100'));
  assert.throws(() => bilibiliCookies('DedeUserID=100'));
  assert.throws(() => bilibiliCookies({}));
});
