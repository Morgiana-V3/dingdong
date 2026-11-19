import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

test('management requires authentication and same origin; phone code expires after one submission', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dingdong-http-'));
  const child = spawn(process.execPath, ['src/server.mjs'], { env: { ...process.env, DATA_DIR: directory, PORT: '0', DINGDONG_READ_TOKEN: 'fictional-read-credential-32-characters' }, stdio: ['ignore', 'pipe', 'pipe'] });
  try {
    const base = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Server did not start')), 10000);
      child.stdout.on('data', chunk => { const match = String(chunk).match(/http:\/\/127\.0\.0\.1:\d+/); if (match) { clearTimeout(timeout); resolve(match[0]); } });
      child.once('error', error => { clearTimeout(timeout); reject(error); });
    });
    assert.equal((await fetch(base + '/api/status')).status, 401);
    assert.equal((await fetch(base + '/v1/subscriptions')).status, 401);
    const readHeaders = { Authorization: 'Bearer fictional-read-credential-32-characters' };
    const catalog = await (await fetch(base + '/v1/subscriptions', { headers: readHeaders })).json();
    assert.deepEqual(catalog.plugins.map(p => p.id), ['bilibili-videos', 'tieba-subscription', 'x-interests', 'xiaohongshu-interests', 'minipush-digest']);
    assert.ok(catalog.plugins.every(p => !p.location && !p.entry));
    assert.deepEqual(catalog.accounts, []);
    const saved = await fetch(base + '/v1/subscriptions/commands', {
      method: 'POST', headers: { ...readHeaders, 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'save', revision: catalog.revision, name: 'Fictional disabled task', pluginId: catalog.plugins[0].id, enabled: false, schedule: { type: 'manual' }, config: { upIds: '123' } }),
    });
    assert.equal(saved.status, 200);
    const savedState = await saved.json();
    assert.equal(savedState.tasks[0].state, 'paused');
    assert.deepEqual(savedState.accounts, []);
    const key = fs.readFileSync(path.join(directory, 'admin.key'), 'utf8');
    const response = await fetch(base + '/api/login', { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: base }, body: JSON.stringify({ key }) });
    assert.equal(response.status, 200);
    const cookie = response.headers.get('set-cookie').split(';')[0];
    assert.equal((await fetch(base + '/api/pair', { method: 'POST', headers: { Cookie: cookie, Origin: 'https://untrusted.invalid' }, body: '{}' })).status, 403);
    assert.equal((await fetch(base + '/api/pair', { method: 'POST', headers: { Cookie: cookie }, body: '{}' })).status, 403);
    const webCommand = base + '/api/subscriptions/commands';
    const pause = JSON.stringify({ action: 'toggle', revision: savedState.revision, id: savedState.tasks[0].id, enabled: false });
    assert.equal((await fetch(base + '/api/subscriptions')).status, 401);
    assert.equal((await fetch(webCommand, { method:'POST', headers:{Cookie:cookie}, body:pause })).status, 403);
    assert.equal((await fetch(webCommand, { method:'POST', headers:{Cookie:cookie, Origin:base}, body:pause })).status, 200);
    assert.equal((await fetch(webCommand, { method:'POST', headers:{Cookie:cookie, Origin:base}, body:pause })).status, 409);
    const pairing = await (await fetch(base + '/api/pair', { method: 'POST', headers: { Cookie: cookie, Origin: base }, body: '{}' })).json();
    assert.match(pairing.code, /^[a-f0-9]{24}$/);
    assert.equal((await fetch(base + '/api/status', { headers: { Authorization: 'Bearer ' + pairing.code } })).status, 401);
    const submit = () => fetch(base + '/api/bilibili/import', { method: 'POST', headers: { Authorization: 'Bearer ' + pairing.code }, body: JSON.stringify({ cookie: 'invalid' }) });
    assert.equal((await submit()).status, 400);
    assert.equal((await submit()).status, 401);
    assert.equal((await fetch(base + '/api/status', { headers: { Cookie: cookie } })).status, 200);
  } finally {
    child.kill();
    await new Promise(resolve => { if (child.exitCode !== null) resolve(); else child.once('exit', resolve); });
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
