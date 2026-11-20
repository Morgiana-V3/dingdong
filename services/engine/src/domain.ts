import crypto from 'node:crypto';

export const DIGEST_ID = 'digest';
export const FIELD_TYPES = new Set([
  'text',
  'textarea',
  'number',
  'boolean',
  'select',
  'stringList',
  'secret',
  'aiProvider',
  'remoteMultiSelect',
  'tasks',
]);

export function validateSchedule(schedule) {
  if (!schedule || schedule.type === 'manual') {
    return { type: 'manual' };
  }
  if (schedule.type === 'interval') {
    const minutes = Number(schedule.minutes);
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 10080) {
      throw new Error('执行间隔必须为 1–10080 分钟');
    }
    return { type: 'interval', minutes };
  }
  const times = schedule.times ?? (schedule.time ? [schedule.time] : []);
  if (
    schedule.type !== 'daily' ||
    !Array.isArray(times) ||
    !times.length ||
    times.length > 24 ||
    times.some((t) => typeof t !== 'string' || !/^([01]\d|2[0-3]):[0-5]\d$/.test(t))
  ) {
    throw new Error('请配置 1–24 个有效的执行时间，格式为 HH:mm');
  }
  if (new Set(times).size !== times.length) {
    throw new Error('执行时间不能重复');
  }
  return { type: 'daily', times: [...times].sort() };
}

export function nextRun(input, now = Date.now()) {
  const schedule = validateSchedule(input);
  if (schedule.type === 'manual') {
    return null;
  }
  if (schedule.type === 'interval') {
    return now + schedule.minutes * 60000;
  }
  // Schedules use Asia/Shanghai (UTC+8) consistently regardless of server timezone.
  return Math.min(
    ...schedule.times.map((time) => {
      const local = new Date(now + 8 * 3600000);
      const [hour, minute] = time.split(':').map(Number);
      local.setUTCHours(hour, minute, 0, 0);
      let next = local.getTime() - 8 * 3600000;
      if (next <= now) {
        next += 86400000;
      }
      return next;
    }),
  );
}

export function validateSourceDefinition(def) {
  if (!def || typeof def !== 'object') {
    throw new Error('插件定义必须为对象');
  }
  if (typeof def.id !== 'string' || !/^[a-z][a-z0-9-]{0,63}$/.test(def.id)) {
    throw new Error(`插件 ID 格式无效: ${def.id}`);
  }
  if (typeof def.name !== 'string' || !def.name.trim() || def.name.length > 80) {
    throw new Error('插件名称不能为空，且不超过 80 个字符');
  }
  if (def.id !== DIGEST_ID && typeof def.run !== 'function') {
    throw new Error(`插件 ${def.id} 必须提供 run(job) 函数`);
  }
  const fields = def.fields ?? [];
  if (!Array.isArray(fields) || fields.length > 30) {
    throw new Error('fields 必须为数组，最多 30 项');
  }
  const seen = new Set();
  for (const field of fields) {
    if (!field || typeof field.key !== 'string' || !/^[a-zA-Z][a-zA-Z0-9_]{0,63}$/.test(field.key)) {
      throw new Error(`字段 key 无效: ${field?.key}`);
    }
    if (seen.has(field.key)) {
      throw new Error(`字段 key 重复: ${field.key}`);
    }
    seen.add(field.key);
    if (typeof field.label !== 'string' || !field.label.trim() || field.label.length > 80) {
      throw new Error(`字段 ${field.key} 缺少有效 label`);
    }
    if (!FIELD_TYPES.has(field.type)) {
      throw new Error(`字段 ${field.key} 使用了不支持的类型: ${field.type}`);
    }
    if (field.type === 'select') {
      if (!Array.isArray(field.options) || !field.options.length) {
        throw new Error(`select 字段 ${field.key} 必须提供非空 options`);
      }
    }
  }
  if (def.auth) {
    validateAuthDefinition(def.auth);
  }
  return {
    id: def.id,
    name: def.name.trim(),
    description: typeof def.description === 'string' ? def.description.trim().slice(0, 300) : '',
    version: typeof def.version === 'string' ? def.version.trim().slice(0, 32) : '0.1.0',
    capabilities: Array.isArray(def.capabilities)
      ? def.capabilities.filter((c) => ['ai.required', 'ai.optional'].includes(c))
      : [],
    fields,
    auth: def.auth || null,
    optionsHandlers: def.optionsHandlers || null,
    builtin: Boolean(def.builtin),
    run: def.run,
  };
}

export function validateAuthDefinition(auth) {
  if (!auth || typeof auth !== 'object') {
    throw new Error('auth 定义必须为对象');
  }
  if (typeof auth.id !== 'string' || !/^[a-z][a-z0-9-]{0,63}$/.test(auth.id)) {
    throw new Error(`auth.id 格式无效: ${auth.id}`);
  }
  if (typeof auth.name !== 'string' || !auth.name.trim() || auth.name.length > 80) {
    throw new Error('auth.name 不能为空');
  }
  if (!['web-cookie', 'token'].includes(auth.type)) {
    throw new Error(`不支持的 auth.type: ${auth.type}`);
  }
  if (auth.type === 'web-cookie') {
    if (typeof auth.loginUrl !== 'string' || !auth.loginUrl.startsWith('https://')) {
      throw new Error('web-cookie 认证的 loginUrl 必须以 https:// 开头');
    }
    if (!Array.isArray(auth.cookieDomains) || !auth.cookieDomains.length) {
      throw new Error('web-cookie 认证必须声明至少一个 cookieDomains');
    }
    for (const domain of auth.cookieDomains) {
      if (typeof domain !== 'string' || !domain.startsWith('https://')) {
        throw new Error(`cookieDomains 必须为 https:// 地址: ${domain}`);
      }
    }
    if (!Array.isArray(auth.requiredCookies) || !auth.requiredCookies.length) {
      throw new Error('web-cookie 认证必须声明至少一个 requiredCookies');
    }
  }
  if (auth.verify !== undefined && typeof auth.verify !== 'function') {
    throw new Error('auth.verify 必须为函数');
  }
}

export function validateConfig(
  plugin: { fields?: Array<Record<string, any>> },
  input: Record<string, unknown>,
  previousSecrets: Record<string, string> = {},
): { config: Record<string, any>; secrets: Record<string, string> } {
  const raw: Record<string, unknown> = input && typeof input === 'object' ? input : {};
  const validated: Record<string, any> = {};
  const secrets: Record<string, string> = {};
  for (const field of plugin.fields || []) {
    let value = raw[field.key];
    if (value === undefined || value === null) {
      value = field.default;
    }
    switch (field.type) {
      case 'boolean': {
        validated[field.key] = Boolean(value);
        break;
      }
      case 'number': {
        if (value === '' || value === undefined || value === null) {
          if (field.required) throw new Error(`请填写「${field.label}」`);
          validated[field.key] = field.default ?? 0;
          break;
        }
        const num = Number(value);
        if (!Number.isFinite(num)) throw new Error(`「${field.label}」必须为有效数字`);
        if (field.integer !== false && !Number.isInteger(num)) {
          throw new Error(`「${field.label}」必须为整数`);
        }
        if (field.min !== undefined && num < field.min) {
          throw new Error(`「${field.label}」不能小于 ${field.min}`);
        }
        if (field.max !== undefined && num > field.max) {
          throw new Error(`「${field.label}」不能大于 ${field.max}`);
        }
        validated[field.key] = num;
        break;
      }
      case 'select': {
        const str = typeof value === 'string' ? value : '';
        const allowed = new Set(field.options.map((o) => String(o.value)));
        if (!str && field.required) throw new Error(`请选择「${field.label}」`);
        if (str && !allowed.has(str)) throw new Error(`「${field.label}」选项无效`);
        validated[field.key] = str;
        break;
      }
      case 'stringList': {
        let items;
        if (Array.isArray(value)) {
          items = value.map((v) => String(v).trim()).filter(Boolean);
        } else if (typeof value === 'string') {
          items = value.split(/\r?\n/).map((v) => v.trim()).filter(Boolean);
        } else {
          items = [];
        }
        const maxItems = field.maxItems ?? 50;
        if (field.required && !items.length) throw new Error(`请至少填写一项「${field.label}」`);
        if (items.length > maxItems) throw new Error(`「${field.label}」最多填写 ${maxItems} 项`);
        validated[field.key] = items;
        break;
      }
      case 'secret': {
        const str = typeof value === 'string' ? value.trim() : '';
        const maxLength = field.maxLength ?? 4096;
        if (str.length > maxLength) throw new Error(`「${field.label}」长度超出限制`);
        if (str) {
          secrets[field.key] = str;
          validated[field.key] = true; // Public flag: indicates secret is set without leaking value
        } else if (previousSecrets[field.key]) {
          secrets[field.key] = previousSecrets[field.key];
          validated[field.key] = true;
        } else if (field.required) {
          throw new Error(`请填写「${field.label}」`);
        } else {
          validated[field.key] = false;
        }
        break;
      }
      case 'tasks': {
        const ids = Array.isArray(value)
          ? value.map((v) => String(v).trim()).filter(Boolean)
          : typeof value === 'string'
            ? value.split(',').map((v) => v.trim()).filter(Boolean)
            : [];
        const unique = [...new Set(ids)];
        const minItems = field.minItems ?? 1;
        const maxItems = field.maxItems ?? 8;
        if (unique.length < minItems || unique.length > maxItems) {
          throw new Error(`请选择 ${minItems}–${maxItems} 个内容源`);
        }
        validated[field.key] = unique.join(',');
        break;
      }
      case 'remoteMultiSelect': {
        const items = Array.isArray(value)
          ? value.map((v) => String(v).trim()).filter(Boolean)
          : typeof value === 'string'
            ? value.split(',').map((v) => v.trim()).filter(Boolean)
            : [];
        const unique = [...new Set(items)];
        const maxItems = field.maxItems ?? 100;
        if (field.required && !unique.length) throw new Error(`请至少选择一项「${field.label}」`);
        if (unique.length > maxItems) throw new Error(`「${field.label}」最多选择 ${maxItems} 项`);
        validated[field.key] = unique;
        break;
      }
      case 'aiProvider': {
        const str = typeof value === 'string' ? value.trim() : '';
        if (field.required && !str) throw new Error(`请选择「${field.label}」`);
        validated[field.key] = str;
        break;
      }
      case 'textarea':
      case 'text':
      default: {
        const str = typeof value === 'string' ? value.trim() : '';
        const maxLength = field.maxLength ?? (field.type === 'textarea' ? 10000 : 500);
        if (field.required && !str) throw new Error(`请填写「${field.label}」`);
        if (str.length > maxLength) throw new Error(`「${field.label}」最多 ${maxLength} 个字符`);
        validated[field.key] = str;
        break;
      }
    }
  }
  return { config: validated, secrets };
}

export function validateOutput(output) {
  if (!output || typeof output !== 'object') {
    throw new Error('插件 run() 必须返回对象');
  }
  if (output.message === null || output.message === undefined) {
    return { message: null, state: output.state, detail: output.detail };
  }
  const msg = output.message;
  if (typeof msg !== 'object' || typeof msg.title !== 'string' || !msg.title.trim()) {
    throw new Error('插件返回的 message 必须包含非空 title');
  }
  if (msg.articles !== undefined) {
    if (!Array.isArray(msg.articles) || !msg.articles.length) {
      throw new Error('message.articles 必须为非空数组');
    }
    for (const article of msg.articles) {
      if (!article || typeof article.title !== 'string' || !article.title.trim()) {
        throw new Error('每篇 article 必须包含非空 title');
      }
    }
  } else if (typeof msg.content !== 'string' && typeof msg.body !== 'string') {
    throw new Error('插件返回的 message 必须提供 articles 或 content');
  }
  return output;
}

export function messageDigest(message) {
  if (!message) return '';
  return crypto.createHash('sha256').update(JSON.stringify(message)).digest('hex');
}

export function digestOwner(tasks, taskId) {
  return tasks.find(
    (task) =>
      task.enabled &&
      task.pluginId === DIGEST_ID &&
      String(task.config?.sourceTaskIds || '')
        .split(',')
        .includes(taskId),
  );
}

export function digestSources(tasks, digestTask) {
  const ids = String(digestTask.config?.sourceTaskIds || '')
    .split(',')
    .map((id) => id.trim())
    .filter(Boolean);
  if (!ids.length || ids.length > 8) {
    throw new Error('统一推送需选择 1–8 个内容源');
  }
  const result = [];
  for (const id of ids) {
    if (id === digestTask.id) throw new Error('统一推送不能包含自身');
    const source = tasks.find((t) => t.id === id);
    if (!source) throw new Error('存在已删除的内容源，请重新选择');
    if (source.pluginId === DIGEST_ID) throw new Error('统一推送不能嵌套其他汇总任务');
    const owner = tasks.find(
      (other) =>
        other.id !== digestTask.id &&
        other.enabled &&
        other.pluginId === DIGEST_ID &&
        String(other.config?.sourceTaskIds || '')
          .split(',')
          .includes(id),
    );
    if (digestTask.enabled && owner) {
      throw new Error(`「${source.name}」已被「${owner.name}」占用`);
    }
    result.push(source);
  }
  return result;
}
