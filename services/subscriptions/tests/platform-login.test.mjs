import { test } from 'node:test';
import assert from 'node:assert/strict';
import { PlatformLogin } from '../src/platform-login.mjs';

test('failed X/XHS replacement discards the entire new profile and preserves the working account', async () => {
  for (const [id, header] of [['x', 'auth_token=new; ct0=new; twid=u%3D2'], ['xiaohongshu', 'web_session=new']]) {
    let oldClosed = false, candidateClosed = false;
    const previous = { close: async () => { oldClosed = true; } };
    const candidate = { close: async () => { candidateClosed = true; } };
    const login = new PlatformLogin({}, id);
    login.context = previous;
    login.page = { old: true };
    login.status = { state: 'ready', account: { id: 'original' } };
    login.newContext = async state => { assert.deepEqual(state.origins, []); assert.ok(state.cookies.length); return candidate; };
    login.verify = async () => { throw new Error('verification failed'); };
    await assert.rejects(login.importPhone(header), /verification failed/);
    assert.equal(login.context, previous);
    assert.deepEqual(login.page, { old: true });
    assert.equal(login.status.account.id, 'original');
    assert.equal(oldClosed, false);
    assert.equal(candidateClosed, true);
  }
});
