import { test } from 'node:test';
import assert from 'node:assert/strict';
import { accountRoutes } from '../src/accounts.mjs';

test('one-time codes are isolated by platform and cannot import another platform session', async () => {
  const credential = 'fictional-relay-credential-32-characters';
  const apis = ['bilibili', 'x', 'xiaohongshu'].map(platform => accountRoutes({ credential, platform, login: { status: { state: 'idle' }, importPhone: async () => ({ state: 'ready' }) }, serial: fn => fn(), body: async () => ({ cookie: 'fixture' }), send: (res, status, data) => Object.assign(res, { status, data }) }));
  const call = async (platform, action, token) => {
    const res = {};
    for (const api of apis) if (await api({ method: 'POST', headers: { authorization: 'Bearer ' + token } }, res, `/v1/accounts/${platform}/${action}`)) break;
    return res;
  };
  const code = (await call('x', 'pair', credential)).data.code;
  assert.equal((await call('xiaohongshu', 'import', code)).status, 401);
  assert.equal((await call('bilibili', 'import', code)).status, 401);
  assert.equal((await call('x', 'import', code)).status, 200);
  assert.equal((await call('x', 'import', code)).status, 401);
});

test('relay credential controls accounts; one-time import cannot read accounts or survive replacement', async () => {
  const credential = 'fictional-relay-credential-32-characters';
  let imports = 0;
  const login = {
    status: { state: 'idle', samples: [{ private: true }] },
    async importPhone(cookie) { imports++; assert.equal(cookie, 'fictional-cookie'); return { state: 'ready', account: { id: '100' }, samples: [{ private: true }] }; },
  };
  const routes = accountRoutes({ credential, login, serial: fn => fn(), body: req => req.data, send: (res, status, data) => Object.assign(res, { status, data }) });
  const call = async (path, method, token, data = {}) => {
    const res = {};
    await routes({ method, headers: { authorization: 'Bearer ' + token }, data }, res, '/v1/accounts/bilibili' + path);
    return res;
  };
  assert.equal((await call('', 'GET', 'wrong')).status, 401);
  assert.deepEqual((await call('', 'GET', credential)).data.samples, undefined);
  const first = (await call('/pair', 'POST', credential)).data.code;
  assert.equal((await call('', 'GET', first)).status, 401);
  const second = (await call('/pair', 'POST', credential)).data.code;
  assert.equal((await call('/import', 'POST', first)).status, 401);
  const imported = await call('/import', 'POST', second, { cookie: 'fictional-cookie' });
  assert.equal(imported.status, 200);
  assert.equal(imported.data.samples, undefined);
  assert.equal((await call('/import', 'POST', second)).status, 401);
  assert.equal(imports, 1);
});

test('failed import consumes code and a missing relay credential disables public account management', async () => {
  let result;
  const base = { login: { importPhone() { throw new Error('invalid session'); } }, serial: fn => fn(), body: () => ({}), send: (_, status, data) => { result = { status, data }; } };
  const routes = accountRoutes({ ...base, credential: 'fictional-relay-credential-32-characters' });
  await routes({ method: 'POST', headers: { authorization: 'Bearer fictional-relay-credential-32-characters' } }, {}, '/v1/accounts/bilibili/pair');
  const request = { method: 'POST', headers: { authorization: 'Bearer ' + result.data.code } };
  await assert.rejects(routes(request, {}, '/v1/accounts/bilibili/import'));
  await routes(request, {}, '/v1/accounts/bilibili/import');
  assert.equal(result.status, 401);
  await accountRoutes(base)({ headers: {}, method: 'GET' }, {}, '/v1/accounts/bilibili');
  assert.equal(result.status, 503);
});
