import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createRequire } from 'node:module';
import { StudioRuntime } from '../src/studio-runtime.mjs';
import { SubscriptionRegistry, Subscriptions } from '../src/subscriptions.mjs';
const require = createRequire(import.meta.url);
const { xPost, xModel } = require('../build/studio/tests/helpers/x-fixtures.cjs');
const { xhsNote, xhsModel, accountId } = require('../build/studio/tests/helpers/xhs-fixtures.cjs');
const { modelResponse } = require('../build/studio/tests/helpers/tool-model.cjs');
function fixture() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'dingdong-studio-runtime-'));
  const registry = new SubscriptionRegistry();
  const runtime = new StudioRuntime(directory, registry, {});
  runtime.logins.x.init = async () => {};
  runtime.logins.x.context = { cookies: async () => [] };
  runtime.providers.push({ id: 'fixture-provider' });
  const sent = [];
  const options = { directory, registry, runtime, account: id => ({ state: 'ready', account: { id: id === 'xiaohongshu' ? accountId : '100' } }), publish: async payload => { sent.push(payload); } };
  const subscriptions = new Subscriptions(options);
  const save = async (pluginId, config, extra = {}) => {
    const result = await subscriptions.command({ action: 'save', revision: subscriptions.state.revision, pluginId, config, name: pluginId, schedule: { type: 'manual' }, enabled: true, providerId: 'fixture-provider', ...extra });
    return subscriptions.state.tasks.find(task => task.id === result.tasks.at(-1).id);
  };
  return { directory, registry, runtime, subscriptions, options, sent, save, close: async () => { await runtime.close(); fs.rmSync(directory, { recursive: true, force: true }); } };
}

test('actual Studio plugins execute in Node children: Bilibili baseline and Tieba/X/XHS tool flows', async () => {
  const f = fixture();
  try {
    f.runtime.services.bilibili.feed = async () => ({ videos: [], truncated: false });
    const bili = await f.save('bilibili-videos', { upIds: '200' });
    await f.subscriptions.runStudio(bili);
    assert.equal(bili.lastError, null);
    assert.ok(bili.pluginState.checkedAt);
    assert.equal(f.sent.length, 0);
    const post = { id: '101', title: 'Fixture', body: 'Fixture body', createdAt: Date.now(), images: [], url: 'https://tieba.baidu.com/p/101' };
    f.runtime.services.tieba = { feed: async () => ({ mode: 'interests', entries: [post] }), search: async () => ({ mode: 'interests', entries: [] }), post: async () => ({ ...post, author: 'Fixture' }) };
    f.runtime.services.respond = async (_, request) => modelResponse(request);
    const tieba = await f.save('tieba-subscription', { forums: [{ name: '动画', filter: '' }], globalFilter: '动画', useSearch: false, includeImages: false });
    await f.subscriptions.runStudio(tieba);
    assert.equal(tieba.lastError, null);
    assert.match(f.sent.at(-1).content, /tieba\.baidu\.com|com\.baidu\.tieba/);
    f.runtime.services.x = { following: async () => ({ posts: [], query: '', scope: '' }), search: async () => ({ posts: [xPost()], query: 'fixture', scope: '' }), detail: async () => ({ post: xPost(), thread: [], scope: '' }) };
    f.runtime.services.respond = async (_, request) => xModel(request);
    const x = await f.save('x-interests', { interests: '开源模型', useFollowing: false, useSearch: true, includeImages: false });
    await f.subscriptions.runStudio(x);
    assert.equal(x.lastError, null);
    assert.match(f.sent.at(-1).content, /x\.com/);
    f.runtime.services.xiaohongshu = { feed: async () => ({ notes: [xhsNote()], scope: '' }), search: async () => ({ notes: [xhsNote()], scope: '' }), detail: async () => xhsNote() };
    f.runtime.services.respond = async (_, request) => xhsModel(request);
    const xhs = await f.save('xiaohongshu-interests', { interests: 'AI 工具', useFeed: true, useSearch: true, includeImages: false });
    await f.subscriptions.runStudio(xhs);
    assert.equal(xhs.lastError, null);
    assert.match(f.sent.at(-1).content, /xiaohongshu\.com/);
    const count = f.sent.length;
    await f.subscriptions.runStudio(xhs);
    assert.equal(f.sent.length, count, 'a second run must not deliver the same note');
  } finally { await f.close(); }
});

test('digest keeps atomic checkpoints and durable exact retries across restart; source errors do not erase healthy work', async () => {
  const f = fixture();
  try {
    const plugin = f.registry.plugins.get('bilibili-videos');
    let calls = 0;
    plugin.execute = async task => { calls++; if (task.name === 'broken') throw new Error('fixture source unavailable'); return { message: { title: 'Fixture', body: 'Original content', format: 'text' }, state: { cursor: 42 } }; };
    const first = await f.save(plugin.id, { upIds: '200' }, { name: 'healthy', enabled: false });
    const second = await f.save(plugin.id, { upIds: '300' }, { name: 'broken', enabled: false });
    const digest = await f.save('minipush-digest', { sourceTaskIds: [first.id, second.id].join(',') });
    assert.equal(f.subscriptions.requiredAccounts()[0].tasks.length, 2);
    assert.equal(f.subscriptions.snapshot().tasks[0].state, 'grouped');
    let attempt;
    f.subscriptions.publish = async payload => { attempt = payload; throw new Error('response lost'); };
    await f.subscriptions.runStudio(digest);
    assert.equal(first.pluginState, undefined);
    assert.ok(digest.pending);
    assert.equal(f.subscriptions.snapshot().tasks.at(-1).pending, undefined);
    const restored = new Subscriptions(f.options);
    await restored.runStudio(restored.state.tasks.at(-1));
    assert.equal(calls, 2, 'recovery must retry the outbox without recollecting');
    assert.deepEqual(f.sent[0], attempt);
    assert.deepEqual(restored.state.tasks[0].pluginState, { cursor: 42 });
    assert.equal(restored.state.tasks[1].pluginState, undefined);
    assert.match(restored.state.tasks.at(-1).lastDetail, /broken/);
    assert.equal(restored.state.tasks.at(-1).nextRunAt, null);
  } finally { await f.close(); }
});

test('task-dependent login, missing UP selection and AI readiness are distinct; credentials never enter snapshots', async () => {
  const f = fixture();
  try {
    const bili = await f.save('bilibili-videos', {});
    assert.equal(f.subscriptions.snapshot().tasks[0].state, 'needs_config');
    f.subscriptions.account = () => ({ state: 'idle' });
    assert.equal(f.subscriptions.snapshot().tasks[0].state, 'needs_login');
    f.runtime.saveProvider({ name: 'Fixture', baseUrl: 'https://ai.example/v1', model: 'fixture', key: 'fictional-private-key' });
    assert.ok(!JSON.stringify(f.subscriptions.snapshot()).includes('fictional-private-key'));
    assert.ok(!fs.readFileSync(path.join(f.directory, 'providers.session')).includes(Buffer.from('fictional-private-key')));
    assert.equal(bili.pluginState, undefined);
  } finally { await f.close(); }
});

test('a scheduled task can be cancelled without committing source progress', async () => {
  const f = fixture();
  try {
    f.registry.plugins.get('bilibili-videos').execute = (_, signal) => new Promise((resolve, reject) => signal.addEventListener('abort', () => reject(new Error('cancelled')), { once: true }));
    const task = await f.save('bilibili-videos', { upIds: '200' }, { schedule: { type: 'interval', minutes: 1 } });
    task.nextRunAt = 0;
    const tick = f.subscriptions.tick();
    assert.ok(f.subscriptions.running.has(task.id));
    await f.subscriptions.command({ action: 'cancel', id: task.id, revision: f.subscriptions.state.revision });
    await tick;
    assert.match(task.lastError, /已停止/);
    assert.equal(task.pluginState, undefined);
    assert.equal(f.subscriptions.running.size, 0);
    assert.equal(f.sent.length, 0);
  } finally { await f.close(); }
});

test('legacy and Studio sources share a digest, preserving deduplication and an exact durable retry', async () => {
  const f = fixture();
  try {
    let calls = 0;
    f.registry.register({ id: 'legacy-fixture', legacy: true, digestSource: true, fields: [], collect: async () => {
      calls++;
      return [{ id: 'old', title: 'already read' }, { id: 'new', title: 'New & safe', url: 'https://www.bilibili.com/video/BVtest', author: 'Fixture', duration: '01:23', publishedAt: 1700000000000 }];
    } });
    const legacy = await f.save('legacy-fixture', {}, { enabled: false });
    legacy.seen = ['old'];
    f.registry.plugins.get('bilibili-videos').execute = async () => ({ message: { title: 'Studio', body: 'Second source', format: 'text' }, state: { cursor: 7 } });
    const studio = await f.save('bilibili-videos', { upIds: '200' }, { enabled: false });
    const digest = await f.save('minipush-digest', { sourceTaskIds: `${legacy.id},${studio.id}` });
    await assert.rejects(f.subscriptions.command({ action: 'run', id: legacy.id, revision: f.subscriptions.state.revision }), /统一推送管理/);
    let attempt;
    f.subscriptions.publish = async payload => { attempt = payload; throw new Error('lost response'); };
    await f.subscriptions.runStudio(digest);
    assert.deepEqual(legacy.seen, ['old']);
    assert.equal(studio.pluginState, undefined);
    assert.match(attempt.content, /New &amp; safe/);
    assert.match(attempt.content, /<article class="post bilibili">/);
    assert.match(attempt.content, /<span class="duration">01:23<\/span>/);
    assert.match(attempt.content, /Second source/);
    assert.doesNotMatch(attempt.content, /already read/);
    const restored = new Subscriptions(f.options);
    await restored.runStudio(restored.state.tasks.at(-1));
    assert.equal(calls, 1);
    assert.deepEqual(f.sent[0], attempt);
    assert.deepEqual(restored.state.tasks[0].seen, ['old', 'new']);
    assert.deepEqual(restored.state.tasks[1].pluginState, { cursor: 7 });
    await restored.runStudio(restored.state.tasks.at(-1));
    assert.equal(f.sent.length, 1, 'seen items and unchanged Studio content must not be repeated');
  } finally { await f.close(); }
});

test('a source with its own pending delivery cannot be captured by a digest', async () => {
  const f = fixture();
  try {
    f.registry.register({ id: 'legacy-fixture', digestSource: true, fields: [], collect: async () => [] });
    const source = await f.save('legacy-fixture', {}, { enabled: false });
    source.pending = { payload: { id: 'pending-fixture' }, ids: ['one'] };
    await assert.rejects(f.save('minipush-digest', { sourceTaskIds: source.id }), /待确认投递/);
    assert.equal(f.subscriptions.state.tasks.length, 1);
    delete source.pending;
    const first = await f.save('minipush-digest', { sourceTaskIds: source.id });
    const second = await f.save('minipush-digest', { sourceTaskIds: source.id }, { enabled: false });
    await f.subscriptions.runStudio(second);
    assert.match(second.lastError, /已由/);
    assert.equal(first.enabled, true);
  } finally { await f.close(); }
});

test('model discovery does not mutate subscription snapshots or persist the supplied key', async () => {
  const f = fixture();
  try {
    f.runtime.listModels = async input => {
      assert.equal(input.key, 'fictional-listing-key');
      return ['fixture-small', 'fixture-large'];
    };
    const before = f.subscriptions.snapshot();
    f.subscriptions.running.add('fixture-running');
    const response = await f.subscriptions.command({ action: 'models', revision: before.revision, provider: { baseUrl: 'https://ai.example/v1', key: 'fictional-listing-key' } });
    assert.deepEqual(response, { models: ['fixture-small', 'fixture-large'] });
    f.subscriptions.running.clear();
    assert.deepEqual(f.subscriptions.snapshot(), before);
    assert.equal(f.runtime.providers.length, 1);
    assert.ok(!JSON.stringify(before).includes('fictional-listing-key'));
  } finally { await f.close(); }
});
