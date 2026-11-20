import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createEngineRuntime, createEngineServer } from '../src/server.ts';

test('HTTP engine API enforces read token, revision conflict, and one-time pairing codes', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dd-http-'));
  const readToken = 'r'.repeat(40);
  const runtime = await createEngineRuntime({
    directory: path.join(dir, 'data'),
    pluginDirs: [],
    publish: async () => {},
  });
  runtime.registry.register({
    id: 'demo',
    name: 'Demo',
    auth: { id: 'demo-auth', name: 'Demo Auth', type: 'token' },
    fields: [{ key: 'q', label: 'Query', type: 'text', required: true }],
    async run() {
      return { message: null };
    },
  });

  const { server } = createEngineServer({ runtime, readToken });
  await new Promise<void>((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve());
  });
  const addr = server.address();
  const port = typeof addr === 'object' && addr ? addr.port : 0;
  const base = `http://127.0.0.1:${port}`;

  try {
    // Public health check
    const health = await fetch(`${base}/v1/engine/health`).then((r) => r.json());
    assert.equal(health.service, 'dingdong-engine');
    assert.ok(health.plugins.includes('demo'));

    // Unauthorized rejected
    const unauth = await fetch(`${base}/v1/engine/snapshot`);
    assert.equal(unauth.status, 401);

    // Authorized snapshot
    const snap = await fetch(`${base}/v1/engine/snapshot`, {
      headers: { Authorization: `Bearer ${readToken}` },
    }).then((r) => r.json());
    assert.equal(snap.revision, 0);

    // Stale revision rejected with 409
    const conflict = await fetch(`${base}/v1/engine/commands`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${readToken}` },
      body: JSON.stringify({ revision: 99, action: 'save' }),
    });
    assert.equal(conflict.status, 409);

    // Pairing code is single-use
    const pair = await fetch(`${base}/v1/engine/credentials/demo-auth/pair`, {
      method: 'POST',
      headers: { Authorization: `Bearer ${readToken}` },
    }).then((r) => r.json());
    assert.ok(pair.code);

    const imp1 = await fetch(`${base}/v1/engine/credentials/demo-auth/import`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${pair.code}` },
      body: JSON.stringify({ token: 'my-secret-token' }),
    });
    assert.equal(imp1.status, 200);

    const imp2 = await fetch(`${base}/v1/engine/credentials/demo-auth/import`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${pair.code}` },
      body: JSON.stringify({ token: 'reuse-attempt' }),
    });
    assert.equal(imp2.status, 401);
  } finally {
    server.close();
    await runtime.ctx.stop();
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
