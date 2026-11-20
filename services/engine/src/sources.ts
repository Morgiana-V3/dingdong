import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {
  DIGEST_ID,
  digestOwner,
  digestSources,
  messageDigest,
  nextRun,
  validateConfig,
  validateOutput,
  validateSchedule,
  validateSourceDefinition,
} from './domain.ts';
import { AuthExpiredError } from './credentials.ts';
import { combineMessages, renderDocument } from './render.ts';
import { messagePreview } from './message-preview.ts';
import { Vault } from './vault.ts';

export class EngineError extends Error {
  status: number;

  constructor(message: string, status = 400) {
    super(message);
    this.status = status;
  }
}

export class SourceRegistry {
  credentials: any;
  plugins: Map<string, any>;
  errors: Array<{ plugin: string; error: string }>;

  constructor(credentials: any) {
    this.credentials = credentials;
    this.plugins = new Map();
    this.errors = [];
  }

  register(definition) {
    const validated = validateSourceDefinition(definition);
    if (this.plugins.has(validated.id)) {
      throw new Error(`插件 ID 重复: ${validated.id}`);
    }
    this.plugins.set(validated.id, validated);
    if (validated.auth && this.credentials) {
      this.credentials.register(validated.auth);
    }
    return () => {
      this.plugins.delete(validated.id);
    };
  }

  recordLoadError(pluginName, error) {
    this.errors.push({
      plugin: pluginName,
      error: String(error?.message || error).slice(0, 300),
    });
  }

  publicPlugins() {
    return [...this.plugins.values()].map(({ run, auth, optionsHandlers, ...descriptor }) => ({
      ...descriptor,
      authId: auth?.id || null,
      authName: auth?.name || null,
      authType: auth?.type || null,
    }));
  }
}

export class TaskEngine {
  directory: string;
  registry: SourceRegistry;
  credentials: any;
  ai: any;
  http: any;
  publish: (payload: Record<string, unknown>) => Promise<void>;
  render: typeof renderDocument;
  now: () => number;
  file: string;
  secretsVault: Vault;
  taskSecrets: Record<string, Record<string, string>>;
  running: Set<string>;
  controller: AbortController | undefined;
  state: { revision: number; tasks: Array<Record<string, any>> };

  constructor({
    directory,
    registry,
    credentials,
    ai,
    http,
    publish,
    render = renderDocument,
    now = Date.now,
  }: {
    directory: string;
    registry: SourceRegistry;
    credentials: any;
    ai: any;
    http: any;
    publish: (payload: Record<string, unknown>) => Promise<void>;
    render?: typeof renderDocument;
    now?: () => number;
  }) {
    this.directory = directory;
    this.registry = registry;
    this.credentials = credentials;
    this.ai = ai;
    this.http = http;
    this.publish = publish;
    this.render = render;
    this.now = now;
    fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
    this.file = path.join(directory, 'tasks.json');
    this.secretsVault = new Vault(directory, 'task-secrets');
    this.taskSecrets = this.secretsVault.load() || {};
    this.running = new Set();
    this.controller = undefined;
    this.state = fs.existsSync(this.file)
      ? JSON.parse(fs.readFileSync(this.file, 'utf8'))
      : { revision: 0, tasks: [] };
    if (!Number.isSafeInteger(this.state.revision) || !Array.isArray(this.state.tasks)) {
      throw new Error('任务配置文件损坏');
    }
  }

  persist() {
    fs.writeFileSync(this.file + '.tmp', JSON.stringify(this.state, null, 2), { mode: 0o600 });
    fs.renameSync(this.file + '.tmp', this.file);
    this.secretsVault.save(this.taskSecrets);
  }

  redact(value) {
    let text = this.ai ? this.ai.redact(value) : String(value ?? '');
    for (const map of Object.values(this.taskSecrets)) {
      for (const secret of Object.values(map || {})) {
        if (typeof secret === 'string' && secret.length >= 6) {
          text = text.replaceAll(secret, '[密钥已隐藏]');
        }
      }
    }
    return text;
  }

  dependencies() {
    const ids = new Set(this.state.tasks.filter((t) => t.enabled).map((t) => t.id));
    for (const task of this.state.tasks.filter((t) => t.enabled && t.pluginId === DIGEST_ID)) {
      for (const id of String(task.config?.sourceTaskIds || '').split(',')) {
        if (id) ids.add(id);
      }
    }
    return this.state.tasks.filter((t) => ids.has(t.id));
  }

  requiredCredentials() {
    const grouped = new Map();
    for (const task of this.dependencies()) {
      const plugin = this.registry.plugins.get(task.pluginId);
      if (!plugin?.auth) continue;
      const entry = grouped.get(plugin.auth.id) || {
        ...this.credentials.status(plugin.auth.id),
        tasks: [],
      };
      entry.tasks.push({ id: task.id, name: task.name });
      grouped.set(plugin.auth.id, entry);
    }
    return [...grouped.values()];
  }

  blockers(task) {
    if (task.pluginId === DIGEST_ID) {
      const sources = this.state.tasks.filter((s) =>
        String(task.config?.sourceTaskIds || '')
          .split(',')
          .includes(s.id),
      );
      const blocked = sources.map((s) => this.blockers(s));
      return blocked.length && blocked.every(Boolean) ? blocked[0] : undefined;
    }
    const plugin = this.registry.plugins.get(task.pluginId);
    if (!plugin) return 'unavailable';
    if (plugin.auth && this.credentials.status(plugin.auth.id).state !== 'ready') {
      return 'needs_login';
    }
    const aiFields = (plugin.fields || []).filter((f: any) => f.type === 'aiProvider' && f.required);
    if (aiFields.some((f: any) => !this.ai?.forTask(task.config?.[f.key]))) {
      return 'needs_ai';
    }
    if (plugin.capabilities.includes('ai.required') && !this.ai?.forTask(task.providerId)) {
      return 'needs_ai';
    }
    return undefined;
  }

  snapshot() {
    return {
      revision: this.state.revision,
      plugins: this.registry.publicPlugins(),
      pluginErrors: this.registry.errors,
      providers: this.ai ? this.ai.publicProviders() : [],
      tasks: this.state.tasks.map((task) => {
        const plugin = this.registry.plugins.get(task.pluginId);
        const owner = digestOwner(this.state.tasks, task.id);
        const state = !plugin
          ? 'unavailable'
          : this.running.has(task.id)
            ? 'running'
            : owner
              ? 'grouped'
              : !task.enabled
                ? 'paused'
                : this.blockers(task) || (task.lastError ? 'error' : 'active');
        const { pending, pluginState, lastDigest, ...publicTask } = task;
        return {
          ...publicTask,
          schedule: task.schedule || { type: 'manual' },
          state,
          owner: owner?.name || null,
          authId: plugin?.auth?.id || null,
        };
      }),
      accounts: this.requiredCredentials(),
    };
  }

  async command(input) {
    if (!input || typeof input !== 'object') {
      throw new EngineError('无效命令');
    }
    if (input.revision !== this.state.revision) {
      throw new EngineError('配置已变化，请刷新后重试', 409);
    }
    if (input.action === 'models') {
      if (!this.ai) throw new EngineError('AI 服务不可用');
      try {
        return { models: await this.ai.listModels(input.provider || {}) };
      } catch (error) {
        throw new EngineError(this.redact(error.message));
      }
    }
    if (input.action === 'revealProviderKey') {
      if (!this.ai) throw new EngineError('AI 服务不可用');
      try {
        return { key: this.ai.revealProviderKey(input.id) };
      } catch (error) {
        throw new EngineError(this.redact(error.message));
      }
    }
    if (input.action === 'testProvider') {
      if (!this.ai) throw new EngineError('AI 服务不可用');
      try {
        return await this.ai.testProvider(input.provider || {});
      } catch (error) {
        throw new EngineError(this.redact(error.message));
      }
    }
    if (input.action === 'fieldOptions') {
      const plugin = this.registry.plugins.get(input.pluginId);
      if (!plugin) throw new EngineError('插件不存在', 404);
      const field = (plugin.fields || []).find((f: any) => f.key === input.fieldKey);
      const handlerName = field?.optionsSource;
      const handler = handlerName ? plugin.optionsHandlers?.[handlerName] : null;
      if (typeof handler !== 'function') {
        throw new EngineError('该字段不支持远程列表筛选');
      }
      const credential = plugin.auth ? this.credentials.get(plugin.auth.id) : null;
      try {
        const options = await handler({
          query: String(input.query || '').trim(),
          credential,
          http: this.http,
          signal: AbortSignal.timeout(20000),
        });
        return { options: Array.isArray(options) ? options.slice(0, 500) : [] };
      } catch (error) {
        throw new EngineError(this.redact(error?.message || '读取选项列表失败'));
      }
    }
    if (this.running.size && input.action !== 'cancel') {
      throw new EngineError('有任务正在执行，请等待完成或先停止任务', 409);
    }
    if (input.action === 'saveProvider' || input.action === 'deleteProvider') {
      if (!this.ai) throw new EngineError('AI 服务不可用');
      try {
        if (input.action === 'saveProvider') {
          this.ai.saveProvider(input.provider);
        } else {
          if (this.state.tasks.some((t) => t.providerId === input.id)) {
            throw new Error('请先修改使用此 AI 配置的任务');
          }
          this.ai.removeProvider(input.id);
        }
      } catch (error) {
        throw new EngineError(error.message);
      }
      this.state.revision++;
      this.persist();
      return this.snapshot();
    }

    const task = this.state.tasks.find((t) => t.id === input.id);
    if (input.action === 'save') {
      const plugin = this.registry.plugins.get(input.pluginId);
      if (!plugin) throw new EngineError('该插件未安装');
      if (input.id && !task) throw new EngineError('任务不存在', 404);
      if (task && task.pluginId !== plugin.id) throw new EngineError('不能更换现有任务的插件');
      if (typeof input.name !== 'string' || !input.name.trim() || input.name.length > 80) {
        throw new EngineError('请填写 1–80 字的任务名称');
      }
      let schedule;
      try {
        schedule = validateSchedule(input.schedule || { type: 'manual' });
      } catch (error) {
        throw new EngineError(error.message);
      }
      if (typeof input.enabled !== 'boolean') {
        throw new EngineError('启用状态无效');
      }
      let config;
      let secrets;
      try {
        const previousSecrets = task ? this.taskSecrets[task.id] || {} : {};
        ({ config, secrets } = validateConfig(plugin, input.config || {}, previousSecrets));
        if (plugin.id === DIGEST_ID) {
          digestSources(this.state.tasks, { id: task?.id, enabled: input.enabled, config });
        }
      } catch (error) {
        throw new EngineError(error.message);
      }
      if (!task && this.state.tasks.length >= 50) {
        throw new EngineError('最多创建 50 个任务');
      }
      if (task?.pending) {
        throw new EngineError('此任务有待确认投递，请先运行完成重试');
      }
      const aiPreview = Boolean(input.aiPreview ?? task?.aiPreview ?? false);
      if (aiPreview && !this.ai?.forTask(input.providerId)) {
        throw new EngineError('开启 AI 摘要/选图前，请先为任务选择 AI 配置');
      }
      const id = task?.id || crypto.randomUUID();
      if (Object.keys(secrets).length) {
        this.taskSecrets[id] = secrets;
      } else {
        delete this.taskSecrets[id];
      }
      const values = {
        id,
        name: input.name.trim(),
        pluginId: plugin.id,
        schedule,
        providerId: String(input.providerId || ''),
        aiPreview,
        onlyChanged: input.onlyChanged === true,
        enabled: input.enabled,
        config,
        nextRunAt: nextRun(schedule, this.now()),
        lastError: null,
      };
      if (task) {
        Object.assign(task, values);
      } else {
        this.state.tasks.push({ ...values, pluginState: {} });
      }
    } else if (input.action === 'cancel') {
      this.controller?.abort();
      return this.snapshot();
    } else {
      if (!task) throw new EngineError('任务不存在', 404);
      if (input.action === 'toggle') {
        if (typeof input.enabled !== 'boolean') throw new EngineError('启用状态无效');
        if (task.pluginId === DIGEST_ID && input.enabled) {
          try {
            digestSources(this.state.tasks, { ...task, enabled: true });
          } catch (error) {
            throw new EngineError(error.message);
          }
        }
        task.enabled = input.enabled;
        task.nextRunAt = nextRun(task.schedule, this.now());
        task.lastError = null;
      } else if (input.action === 'delete') {
        if (
          this.state.tasks.some(
            (other) =>
              other.pluginId === DIGEST_ID &&
              String(other.config?.sourceTaskIds || '')
                .split(',')
                .includes(task.id),
          )
        ) {
          throw new EngineError('请先从统一推送汇总中移除此内容源');
        }
        if (task.pending) {
          throw new EngineError('任务有待确认投递，请先完成重试');
        }
        delete this.taskSecrets[task.id];
        this.state.tasks = this.state.tasks.filter((t) => t !== task);
      } else if (input.action === 'run') {
        if (digestOwner(this.state.tasks, task.id)) {
          throw new EngineError('此任务由统一推送管理，请运行对应汇总任务');
        }
        const blocker = this.blockers(task);
        if (blocker) {
          throw new EngineError(
            blocker === 'needs_ai'
              ? '请先为任务选择 AI 配置'
              : blocker === 'needs_login'
                ? '请先在「所需账号」完成登录或凭据配置'
                : '该任务对应的插件不可用',
          );
        }
        void this.executeTask(task).catch(() => {});
        return this.snapshot();
      } else {
        throw new EngineError('不支持的任务操作');
      }
    }

    this.state.revision++;
    this.persist();
    return this.snapshot();
  }

  async preview(html, message, task, signal) {
    const assigned = this.ai?.forTask(task.providerId);
    const defaultProvider = this.ai?.providers?.[0];
    const generate =
      assigned && task.aiPreview
        ? (prompt, deadline) => assigned.generate({ prompt }, deadline)
        : undefined;
    const translator = assigned
      ? (prompt, deadline) => assigned.generate({ prompt }, deadline)
      : defaultProvider
        ? (prompt, deadline) => this.ai.generate(defaultProvider.id, { prompt }, deadline)
        : undefined;
    return messagePreview(html, message, task.name, generate, signal, translator);
  }

  commitProgress(commits) {
    for (const { id, pluginState, lastDigest } of commits) {
      const target = this.state.tasks.find((t) => t.id === id);
      if (target) {
        target.pluginState = pluginState;
        target.lastDigest = lastDigest;
      }
    }
  }

  async executeTask(task) {
    if (this.running.size) {
      throw new EngineError('已有任务正在执行', 409);
    }
    this.controller = new AbortController();
    this.running.add(task.id);
    task.trace = [];
    const log = (step, detail, status = 'info') => {
      if (task.trace.length >= 80) return;
      task.trace.push({
        step: String(step || '').slice(0, 60),
        detail: this.redact(detail || '').slice(0, 300),
        status,
        at: this.now(),
      });
    };

    const collectSource = async (source) => {
      const plugin = this.registry.plugins.get(source.pluginId);
      if (!plugin || typeof plugin.run !== 'function') {
        throw new Error(`插件不可用: ${source.pluginId}`);
      }
      const blocker = this.blockers(source);
      if (blocker) {
        throw new Error(
          blocker === 'needs_ai' ? '缺少 AI 配置' : blocker === 'needs_login' ? '缺少登录凭据' : '插件不可用',
        );
      }
      const mergedConfig = {
        ...structuredClone(source.config || {}),
        ...(this.taskSecrets[source.id] || {}),
      };
      const aiField = (plugin.fields || []).find((f: any) => f.type === 'aiProvider');
      const effectiveProviderId = (aiField && mergedConfig[aiField.key]) || source.providerId || '';
      const credential = plugin.auth ? this.credentials.get(plugin.auth.id) : null;
      const job = {
        taskId: source.id,
        taskName: source.name,
        config: mergedConfig,
        state: structuredClone(source.pluginState || {}),
        credential,
        ai: this.ai ? this.ai.forTask(effectiveProviderId) : null,
        getAI: (providerId?: string) => (this.ai ? this.ai.forTask(providerId || effectiveProviderId) : null),
        http: this.http,
        signal: this.controller.signal,
        log,
      };
      let output;
      try {
        output = validateOutput(await plugin.run(job));
      } catch (error) {
        if (error instanceof AuthExpiredError && plugin.auth) {
          this.credentials.markExpired(plugin.auth.id, error.message);
          void this.notifyAuthExpired(plugin.auth.name, source.name, error.message);
        }
        throw error;
      }
      const digest = output.message ? messageDigest(output.message) : source.lastDigest;
      const changed = !source.onlyChanged || digest !== source.lastDigest;
      return {
        source,
        output,
        digest,
        message: changed ? output.message : null,
      };
    };

    try {
      if (!task.pending) {
        const results = [];
        const failures = [];
        if (task.pluginId === DIGEST_ID) {
          const sources = digestSources(this.state.tasks, { ...task, enabled: true });
          for (const source of sources) {
            this.running.add(source.id);
            try {
              results.push(await collectSource(source));
            } catch (error) {
              this.controller.signal.throwIfAborted();
              failures.push(`${source.name}：${this.redact(error.message)}`);
            }
          }
          if (!results.length) {
            throw new Error('所有内容源采集失败：' + failures.join('；'));
          }
        } else {
          results.push(await collectSource(task));
        }

        const message =
          task.pluginId === DIGEST_ID
            ? combineMessages(
                task.name,
                results.filter((r) => r.message).map((r) => ({ name: r.source.name, message: r.message })),
              )
            : results[0].message;

        const commits = results.map((r) => ({
          id: r.source.id,
          pluginState: r.output.state !== undefined ? r.output.state : r.source.pluginState || {},
          lastDigest: r.digest,
        }));
        const count = results.reduce(
          (sum, r) => sum + (r.message ? r.message.articles?.length || 1 : 0),
          0,
        );
        const detail = failures.length
          ? '部分来源失败：' + failures.join('；')
          : results[0]?.output.detail || (message ? '消息已交给中转服务器' : '本轮没有新内容');

        if (message) {
          const { content } = await this.render(message, undefined, this.controller.signal);
          this.controller.signal.throwIfAborted();
          const preview = await this.preview(content, message, task, this.controller.signal);
          this.controller.signal.throwIfAborted();
          task.pending = {
            payload: {
              id: 'engine-' + crypto.randomUUID(),
              source: message.source || task.name,
              ...preview,
              format: 'html',
              priority: 'normal',
            },
            commits,
            count,
            detail,
          };
          this.persist();
        } else {
          this.commitProgress(commits);
          task.lastCount = 0;
          task.lastDetail = detail;
        }
      }

      if (task.pending) {
        this.controller.signal.throwIfAborted();
        await this.publish(task.pending.payload);
        this.commitProgress(task.pending.commits);
        task.lastCount = task.pending.count;
        task.lastDetail = task.pending.detail;
        task.lastPublishedAt = this.now();
        delete task.pending;
      }
      task.lastError = null;
    } catch (error) {
      task.lastError = this.controller.signal.aborted
        ? '任务已停止，采集进度未提交；待发消息会在下次运行时重试'
        : this.redact(error.message).slice(0, 600);
    } finally {
      task.lastRunAt = this.now();
      task.nextRunAt = nextRun(task.schedule || { type: 'manual' }, this.now());
      this.running.clear();
      this.controller = undefined;
      this.persist();
    }
  }

  async notifyAuthExpired(authName, taskName, reason) {
    try {
      await this.publish({
        id: 'auth-expired-' + crypto.randomUUID(),
        source: '叮咚引擎',
        title: `${authName} 登录已失效`,
        summary: `任务「${taskName}」需要重新授权`,
        format: 'markdown',
        content: `任务 **${taskName}** 运行时检测到 **${authName}** 凭据已失效：\n\n> ${reason}\n\n请打开手机 App 的「订阅管理 → 所需账号」重新登录或更新凭据。`,
        priority: 'normal',
      });
    } catch {
      // Do not mask original task error
    }
  }

  async tick() {
    if (this.running.size) return;
    for (const task of this.state.tasks) {
      const plugin = this.registry.plugins.get(task.pluginId);
      if (
        !task.enabled ||
        !plugin ||
        task.nextRunAt == null ||
        task.nextRunAt > this.now() ||
        this.blockers(task) ||
        digestOwner(this.state.tasks, task.id)
      ) {
        continue;
      }
      try {
        await this.executeTask(task);
      } catch {
        // Error is persisted on task.lastError
      }
    }
  }
}
