import { test } from 'node:test';
import assert from 'node:assert/strict';
import { MockAgent, setGlobalDispatcher } from 'undici';
import { accountProfile, browserProfile } from '../src/account-profile.mjs';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { Vault } from '../src/vault.mjs';

test('profile includes a bounded inline avatar and preserves identity when image download fails', async () => {
  const agent = new MockAgent();
  agent.disableNetConnect();
  setGlobalDispatcher(agent);
  try {
    agent.get('https://i0.hdslb.com').intercept({ path: '/avatar.png' }).reply(200, Buffer.from('fixture-image'), { headers: { 'content-type': 'image/png' } });
    const profile = await accountProfile('42', '测试昵称', 'http://i0.hdslb.com/avatar.png');
    assert.equal(profile.name, '测试昵称');
    assert.match(profile.avatar, /^data:image\/png;base64,/);
    assert.deepEqual(await accountProfile('42', '测试昵称', 'https://unsupported.example/avatar'), { id: '42', name: '测试昵称' });
  } finally { await agent.close(); }
});

test('browser identity extraction closes its page and falls back without invalidating login', async () => {
  let closed = 0;
  const login = { context: { newPage: async () => ({ goto: async () => {}, evaluate: async () => ({ name: 'Current user' }), close: async () => { closed++; } }) } };
  assert.deepEqual(await browserProfile(login, 'x', '42', '42'), { id: '42', name: 'Current user' });
  assert.equal(closed, 1);
  login.context.newPage = async () => { throw Error('not available'); };
  assert.deepEqual(await browserProfile(login, 'x', '42', 'Saved name'), { id: '42', name: 'Saved name' });
});

test('profile cache is encrypted and scoped to the authenticated account', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'profile-cache-'));
  const login = { vault: new Vault(directory, 'x'), context: { newPage: async () => ({ goto: async () => {}, evaluate: async () => ({ name: 'Private fixture name' }), close: async () => {} }) } };
  try {
    await browserProfile(login, 'x', '42', '42');
    assert.ok(!fs.readFileSync(path.join(directory, 'x-profile.session')).includes(Buffer.from('Private fixture name')));
    login.context.newPage = async () => { throw Error('temporarily unavailable'); };
    assert.equal((await browserProfile(login, 'x', '42', '42')).name, 'Private fixture name');
    assert.equal((await browserProfile(login, 'x', '43', '43')).name, '43');
    fs.writeFileSync(path.join(directory, 'x-profile.session'), 'invalid');
    assert.equal((await browserProfile(login, 'x', '42', '42')).name, '42');
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});
