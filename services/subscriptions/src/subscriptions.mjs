import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { createRequire } from 'node:module';
import { messagePreview } from './message-preview.mjs';
import { loadImage } from './subscription-images.mjs';
const require = createRequire(import.meta.url);
const { validateConfig, validateSchedule, nextRun, messageDigest } = require('../build/studio/src/domain.cjs');
const { DIGEST_ID, digestSources, digestOwner, validateOutput, combineMessages } = require('../build/studio/src/digest.cjs');
const { dingdongDocument } = require('../build/studio/src/dingdong-document.cjs');

function legacyVideoMessage(task, videos) {
  return {
    title: task.name,
    short: `${videos.length} 条新视频`,
    body: '',
    articles: videos.map(video => ({
      kind: 'bilibili',
      title: video.title,
      body: video.description || '',
      source: video.author,
      url: video.url,
      images: video.cover ? [video.cover] : [],
      duration: video.duration,
      publishedAt: video.publishedAt,
    })),
  };
}

export class SubscriptionError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}

export class SubscriptionRegistry {
  plugins = new Map();
  register(plugin) {
    if (this.plugins.has(plugin.id)) throw new Error('Duplicate subscription plugin');
    this.plugins.set(plugin.id, plugin);
    return () => this.plugins.delete(plugin.id);
  }
}

export class Subscriptions {
  constructor({ directory, registry, account, publish, runtime, now = Date.now }) {
    this.registry = registry;
    this.account = account;
    this.publish = publish;
    this.now = now;
    this.runtime = runtime;
    this.file = path.join(directory, 'subscriptions.json');
    this.running = new Set();
    this.state = fs.existsSync(this.file) ? JSON.parse(fs.readFileSync(this.file, 'utf8')) : { revision: 0, tasks: [] };
    if (!Number.isSafeInteger(this.state.revision) || !Array.isArray(this.state.tasks)) throw new Error('Invalid subscription store');
  }
  persist() {
    fs.writeFileSync(this.file + '.tmp', JSON.stringify(this.state), { mode: 0o600 });
    fs.renameSync(this.file + '.tmp', this.file);
  }
  sources(task) {
    const sources = digestSources(this.state.tasks, task);
    for (const source of sources) {
      const plugin = this.registry.plugins.get(source.pluginId);
      if (!plugin?.execute && !(plugin?.digestSource && plugin.collect)) throw new SubscriptionError('此来源插件暂不支持统一推送');
      if (source.pending) throw new SubscriptionError(`「${source.name}」有待确认投递，请先单独运行完成重试`);
    }
    return sources;
  }
  commitProgress(commits) {
    for (const { id, pluginState, lastDigest, seen } of commits) {
      const source = this.state.tasks.find(task => task.id === id);
      if (source) Object.assign(source, { pluginState, lastDigest, ...(seen ? { seen } : {}) });
    }
  }
  requiredAccounts() {
    const required = new Map();
    for (const task of this.dependencies()) {
      const plugin = this.registry.plugins.get(task.pluginId);
      if (!plugin?.accountId) continue;
      const entry = required.get(plugin.accountId) || { id: plugin.accountId, name: plugin.accountName, tasks: [] };
      entry.tasks.push({ id: task.id, name: task.name });
      required.set(entry.id, entry);
    }
    return [...required.values()].map(entry => {
      const { state, account, checkedAt, message } = this.account(entry.id);
      return { ...entry, state, account, checkedAt, message };
    });
  }
  dependencies() {
    const ids = new Set(this.state.tasks.filter(task => task.enabled).map(task => task.id));
    for (const task of this.state.tasks.filter(task => task.enabled && task.pluginId === DIGEST_ID)) {
      for (const id of String(task.config.sourceTaskIds || '').split(',')) ids.add(id);
    }
    return this.state.tasks.filter(task => ids.has(task.id));
  }
  blockers(task) {
    if (task.pluginId === DIGEST_ID) {
      const sources = this.state.tasks.filter(source => String(task.config.sourceTaskIds || '').split(',').includes(source.id));
      const blocked = sources.map(source => this.blockers(source));
      return blocked.length && blocked.every(Boolean) ? blocked[0] : undefined;
    }
    const tasks = [task];
    for (const source of tasks) {
      const plugin = this.registry.plugins.get(source.pluginId);
      if (!plugin) return 'unavailable';
      if (plugin.accountId && this.account(plugin.accountId).state !== 'ready') return 'needs_login';
      if (source.pluginId === 'bilibili-videos' && !source.config.upIds?.trim()) return 'needs_config';
      if ((plugin.capabilities?.includes('ai.tools') || source.config.useAI) && !this.runtime?.providers.some(provider => provider.id === source.providerId)) return 'needs_ai';
    }
  }
  snapshot() {
    return {
      revision: this.state.revision,
      plugins: [...this.registry.plugins.values()].filter(plugin => !plugin.legacy || this.state.tasks.some(task => task.pluginId === plugin.id)).map(({ collect, execute, location, entry, ...descriptor }) => descriptor),
      providers: this.runtime?.publicProviders() || [],
      channels: [{ id: 'current-relay', name: '当前叮咚收件箱', kind: 'dingdong' }],
      tasks: this.state.tasks.map(task => {
        const plugin = this.registry.plugins.get(task.pluginId);
        const owner = digestOwner(this.state.tasks, task.id);
        const state = !plugin ? 'unavailable' : this.running.has(task.id) ? 'running' : owner ? 'grouped' : !task.enabled ? 'paused' : this.blockers(task) || (task.lastError ? 'error' : 'active');
        const { seen, pending, pluginState, lastDigest, translate, ...publicTask } = task;
        return { ...publicTask, schedule: task.schedule || { type: 'interval', minutes: task.minutes }, state, owner: owner?.name, accountId: plugin?.accountId };
      }),
      accounts: this.requiredAccounts(),
    };
  }
  async command(input) {
    if (input.revision !== this.state.revision) throw new SubscriptionError('任务已变化，请刷新后重试', 409);
    if (input.action === 'models') {
      if (!this.runtime) throw new SubscriptionError('AI 配置服务不可用');
      try { return { models: await this.runtime.listModels(input.provider) }; }
      catch (error) { throw new SubscriptionError(this.runtime.store.redact(error.message)); }
    }
    const task = this.state.tasks.find(task => task.id === input.id);
    if (this.running.size && input.action !== 'cancel') throw new SubscriptionError('任务正在执行，请等待完成或先停止任务', 409);
    if (['saveProvider', 'deleteProvider'].includes(input.action)) {
      if (!this.runtime) throw new SubscriptionError('AI 配置服务不可用');
      try {
        if (input.action === 'saveProvider') this.runtime.saveProvider(input.provider);
        else {
          if (this.state.tasks.some(task => task.providerId === input.id)) throw new Error('请先修改使用此 AI 配置的任务');
          this.runtime.removeProvider(input.id);
        }
      } catch (error) { throw new SubscriptionError(error.message); }
      this.state.revision++; this.persist(); return this.snapshot();
    }
    if (input.action === 'save') {
      const plugin = this.registry.plugins.get(input.pluginId);
      if (!plugin) throw new SubscriptionError('该订阅插件未安装');
      if (input.id && !task) throw new SubscriptionError('任务不存在', 404);
      if (task && task.pluginId !== plugin.id) throw new SubscriptionError('不能更换现有任务的插件');
      if (typeof input.name !== 'string' || !input.name.trim() || input.name.length > 80) throw new SubscriptionError('请填写 1–80 字的任务名称');
      let schedule;
      try { schedule = validateSchedule(input.schedule || { type: 'interval', minutes: input.minutes }); }
      catch (error) { throw new SubscriptionError(error.message); }
      if (typeof input.enabled !== 'boolean') throw new SubscriptionError('启用状态无效');
      let config = {};
      if (plugin.studio) {
        try { config = validateConfig({ ...plugin, fields: plugin.fields.filter(field => field.type !== 'account') }, input.config || {}); }
        catch (error) { throw new SubscriptionError(error.message); }
        for (const field of plugin.fields.filter(field => field.type === 'account')) config[field.key] = typeof input.config?.[field.key] === 'string' ? input.config[field.key] : '';
        if (plugin.id === DIGEST_ID) {
          try { this.sources({ id: task?.id, enabled: input.enabled, config }); }
          catch (error) { throw new SubscriptionError(error.message); }
        }
      } else for (const field of plugin.fields) {
        const value = input.config?.[field.key] ?? field.default;
        if (field.type === 'number') {
          if (!Number.isInteger(value) || value < field.min || value > field.max) throw new SubscriptionError(`${field.label}超出范围`);
        } else if (typeof value !== 'string' || value.length > field.maxLength) throw new SubscriptionError(`${field.label}格式无效`);
        config[field.key] = value;
      }
      if (!task && this.state.tasks.length >= 30) throw new SubscriptionError('最多创建 30 个订阅任务');
      if (task?.pending) throw new SubscriptionError('此任务有待确认投递，请先运行以完成原消息重试');
      const aiPreview = input.aiPreview ?? task?.aiPreview ?? false;
      if (typeof aiPreview !== 'boolean') throw new SubscriptionError('AI 预览设置无效');
      if (aiPreview && !this.runtime?.providers.some(provider => provider.id === input.providerId)) throw new SubscriptionError('请先为任务选择 AI 配置');
      const values = { aiPreview, name: input.name.trim(), pluginId: plugin.id, minutes: schedule.minutes, schedule, providerId: String(input.providerId || ''), onlyChanged: input.onlyChanged !== false, enabled: input.enabled, config, nextRunAt: plugin.studio || input.schedule ? nextRun(schedule, this.now()) : this.now(), lastError: null };
      if (task) Object.assign(task, values);
      else this.state.tasks.push({ id: crypto.randomUUID(), ...values, seen: [] });
    } else {
      if (!task) throw new SubscriptionError('任务不存在', 404);
      if (input.action === 'toggle') {
        if (typeof input.enabled !== 'boolean') throw new SubscriptionError('启用状态无效');
        if (task.pluginId === DIGEST_ID && input.enabled) {
          try { this.sources({ ...task, enabled: true }); } catch (error) { throw new SubscriptionError(error.message); }
        }
        task.enabled = input.enabled;
        task.nextRunAt = task.schedule ? nextRun(task.schedule, this.now()) : this.now();
        task.lastError = null;
      } else if (input.action === 'delete') {
        if (this.state.tasks.some(other => other.pluginId === DIGEST_ID && String(other.config.sourceTaskIds || '').split(',').includes(task.id))) throw new SubscriptionError('请先从统一推送中移除此内容源');
        if (task.pending) throw new SubscriptionError('任务有待确认投递，请先完成重试，避免丢失投递进度');
        this.state.tasks = this.state.tasks.filter(value => value !== task);
      } else if (input.action === 'run') {
        if (digestOwner(this.state.tasks, task.id)) throw new SubscriptionError('此任务由统一推送管理，请运行对应汇总任务');
        if (this.registry.plugins.get(task.pluginId)?.studio) {
          const blocker = this.blockers(task);
          if (blocker) throw new SubscriptionError(blocker === 'needs_ai' ? '请先为任务配置 AI' : blocker === 'needs_config' ? '请先编辑任务并选择 UP 主' : '请先完成任务需要的账号登录');
          void this.runStudio(task).catch(() => {});
        } else await this.run(task);
        return this.snapshot();
      } else if (input.action === 'cancel') {
        this.controller?.abort();
        return this.snapshot();
      } else throw new SubscriptionError('不支持的任务操作');
    }
    this.state.revision++;
    this.persist();
    return this.snapshot();
  }
  async preview(html, message, task, signal) {
    const providers = this.runtime?.providers ?? [];
    const assigned = providers.find(provider => provider.id === task.providerId);
    const translator = assigned ?? providers[0];
    const generate = assigned && task.aiPreview
      ? (prompt, deadline) => this.runtime.services.generate(assigned.id, prompt, deadline)
      : undefined;
    const translate = translator
      ? (prompt, deadline) => this.runtime.services.generate(translator.id, prompt, deadline)
      : undefined;
    return messagePreview(html, message, task.name, generate, signal, translate);
  }
  async runStudio(task) {
    if (this.running.size) throw new SubscriptionError('已有任务正在执行');
    this.controller = new AbortController();
    this.running.add(task.id);
    task.trace = [];
    const trace = event => {
      if (task.trace.length >= 80) return;
      task.trace.push({ tool: String(event.tool || '').slice(0, 60), detail: this.runtime.store.redact(event.detail || '').slice(0, 300), status: event.status, at: this.now() });
    };
    const collect = async source => {
      const plugin = this.registry.plugins.get(source.pluginId);
      if (!plugin?.execute && !(plugin?.digestSource && plugin.collect)) throw new Error('此来源插件暂不支持统一推送');
      const blocker = this.blockers(source);
      if (blocker) throw new Error(blocker === 'needs_ai' ? '请配置 AI' : blocker === 'needs_config' ? '请选择 UP 主' : '请完成账号登录');
      const copy = structuredClone(source);
      for (const field of plugin.fields.filter(field => field.type === 'account')) copy.config[field.key] ||= this.account(plugin.accountId).account?.id || '';
      let output, seen;
      if (plugin.execute) output = await plugin.execute(copy, this.controller.signal, trace);
      else {
        const items = await plugin.collect(copy.config);
        this.controller.signal.throwIfAborted();
        const unseen = items.filter(item => !(source.seen || []).includes(item.id));
        seen = [...new Set([...(source.seen || []), ...unseen.map(item => item.id)])].slice(-1000);
        output = { message: unseen.length ? legacyVideoMessage(source, unseen) : null };
      }
      validateOutput(output);
      const digest = output.message ? messageDigest(output.message) : source.lastDigest;
      return { source, output, digest, seen, message: source.onlyChanged && digest === source.lastDigest ? null : output.message };
    };
    try {
      if (!task.pending) {
        const results = [];
        const failures = [];
        if (task.pluginId === DIGEST_ID) {
          for (const source of this.sources({ ...task, enabled: true })) {
            this.running.add(source.id);
            try { results.push(await collect(source)); }
            catch (error) { this.controller.signal.throwIfAborted(); failures.push(`${source.name}：${this.runtime.store.redact(error.message)}`); }
          }
          if (!results.length) throw new Error('所有内容源采集失败：' + failures.join('；'));
        } else results.push(await collect(task));
        const message = task.pluginId === DIGEST_ID ? combineMessages(task.name, results.filter(result => result.message).map(result => ({ name: result.source.name, message: result.message }))) : results[0].message;
        const commits = results.map(result => ({ id: result.source.id, pluginState: result.output.state ?? result.source.pluginState ?? {}, lastDigest: result.digest, ...(result.seen ? { seen: result.seen } : {}) }));
        const count = results.reduce((total, result) => total + (result.message ? result.message.articles?.length || 1 : 0), 0);
        const detail = failures.length ? '部分来源失败：' + failures.join('；') : results[0]?.output.detail || (message ? '消息已交给中转服务器' : '本轮没有新内容');
        if (message) {
          const { content } = await dingdongDocument(message, loadImage, this.controller.signal);
          this.controller.signal.throwIfAborted();
          const preview = await this.preview(content, message, task, this.controller.signal);
          this.controller.signal.throwIfAborted();
          task.pending = { payload: { id: 'node-' + crypto.randomUUID(), source: '订阅任务', ...preview, format: 'html', priority: 'normal' }, commits, count, detail };
          this.persist();
        } else {
          this.commitProgress(commits);
          task.lastCount = 0; task.lastDetail = detail;
        }
      }
      if (task.pending) {
        this.controller.signal.throwIfAborted();
        await this.publish(task.pending.payload);
        this.commitProgress(task.pending.commits);
        task.lastCount = task.pending.count; task.lastDetail = task.pending.detail;
        task.lastPublishedAt = this.now(); delete task.pending;
      }
      task.lastError = null;
    } catch (error) {
      task.lastError = this.controller.signal.aborted ? '任务已停止，采集进度未提交；待发消息会在下次运行时重试' : this.runtime.store.redact(error.message).slice(0, 600);
    } finally {
      task.lastRunAt = this.now();
      task.nextRunAt = nextRun(task.schedule || { type: 'manual' }, this.now());
      this.running.clear(); this.controller = undefined; this.persist();
    }
  }
  async run(task) {
    const plugin = this.registry.plugins.get(task.pluginId);
    if (!plugin) throw new SubscriptionError('订阅插件不存在');
    if (plugin.accountId && this.account(plugin.accountId).state !== 'ready') throw new SubscriptionError('请在右侧账号页完成此任务需要的登录', 409);
    if (this.running.has(task.id)) throw new SubscriptionError('任务正在执行', 409);
    this.running.add(task.id);
    try {
      // Persist an outbox before sending: retries after a lost response reuse identical ID and body.
      if (!task.pending) {
        const items = await plugin.collect(task.config);
        const unseen = items.filter(item => !(task.seen || []).includes(item.id));
        if (unseen.length) {
          const message = legacyVideoMessage(task, unseen);
          const imageDeadline = AbortSignal.timeout(30_000);
          const { content } = await dingdongDocument(message, loadImage, imageDeadline).catch(error => {
            if (!imageDeadline.aborted) throw error;
            return dingdongDocument(message);
          });
          const payload = { source: 'B 站订阅', ...await this.preview(content, message, task), format: 'html', priority: 'normal' };
          const fingerprint = crypto.createHash('sha256').update(task.id + JSON.stringify(payload)).digest('hex');
          task.pending = { payload: { id: 'node-' + fingerprint, ...payload }, ids: unseen.map(item => item.id) };
          this.persist();
        }
      }
      if (task.pending) {
        await this.publish(task.pending.payload);
        task.seen = [...new Set([...(task.seen || []), ...task.pending.ids])].slice(-1000);
        task.lastPublishedAt = this.now();
        task.lastCount = task.pending.ids.length;
        delete task.pending;
      } else task.lastCount = 0;
      task.lastError = null;
      task.lastRunAt = this.now();
    } catch (error) {
      task.lastError = error instanceof SubscriptionError ? error.message : /B 站|会话|登录/.test(error.message) ? error.message.slice(0, 160) : '采集或推送未完成，稍后将自动重试';
      throw new SubscriptionError(task.lastError, 502);
    } finally {
      task.nextRunAt = task.schedule ? nextRun(task.schedule, this.now()) : this.now() + task.minutes * 60000;
      this.running.delete(task.id);
      this.persist();
    }
  }
  async tick() {
    if (this.running.size) return;
    for (const task of this.state.tasks) {
      const plugin = this.registry.plugins.get(task.pluginId);
      if (!task.enabled || !plugin || task.nextRunAt == null || task.nextRunAt > this.now() || this.blockers(task) || digestOwner(this.state.tasks, task.id)) continue;
      try { if (plugin.studio) await this.runStudio(task); else await this.run(task); } catch { /* Persisted status is returned to the client. */ }
    }
  }
}

export function subscriptionRoutes({ subscriptions, credential, serial, body, send }) {
  return async (req, res, pathname) => {
    if (!pathname.startsWith('/v1/subscriptions')) return false;
    const hash = value => crypto.createHash('sha256').update(value || '').digest();
    if (!credential || !crypto.timingSafeEqual(hash(req.headers.authorization), hash('Bearer ' + credential))) {
      send(res, 401, { error: '接收密钥无效，请检查服务器设置' }); return true;
    }
    try {
      if (req.method === 'GET' && pathname === '/v1/subscriptions') send(res, 200, subscriptions.snapshot());
      else if (req.method === 'POST' && pathname === '/v1/subscriptions/commands') {
        const input = await body(req);
        send(res, 200, await serial(() => subscriptions.command(input)));
      } else send(res, 404, { error: '订阅接口不存在' });
    } catch (error) {
      if (!(error instanceof SubscriptionError)) throw error;
      send(res, error.status, { error: error.message });
    }
    return true;
  };
}
