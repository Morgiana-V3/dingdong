import crypto from 'node:crypto';
import { Vault } from './vault.ts';

function normalizeBaseUrl(value) {
  const url = new URL(String(value || '').trim());
  if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) {
    throw new Error('AI 服务地址必须为合法的 http/https 地址');
  }
  return url.toString().replace(/\/+$/, '');
}

export interface AIProviderRecord {
  id: string;
  name: string;
  baseUrl: string;
  model: string;
  maxOutputTokens: number;
  secret: string;
}

export class AIService {
  http: ReturnType<typeof import('./http.ts').createHttpService>;
  vault: Vault;
  providers: AIProviderRecord[];

  constructor(directory: string, http: ReturnType<typeof import('./http.ts').createHttpService>) {
    this.http = http;
    this.vault = new Vault(directory, 'ai-providers');
    this.providers = (this.vault.load() as AIProviderRecord[] | undefined) || [];
  }

  publicProviders() {
    return this.providers.map(({ secret, ...rest }) => ({ ...rest, hasKey: Boolean(secret) }));
  }

  redact(value) {
    let text = String(value ?? '');
    for (const provider of this.providers) {
      if (provider.secret) {
        text = text.replaceAll(provider.secret, '[密钥已隐藏]');
      }
    }
    return text;
  }

  saveProvider(input) {
    if (!input || typeof input !== 'object') {
      throw new Error('AI 配置无效');
    }
    const existing = this.providers.find((p) => p.id === input.id);
    const name = String(input.name || '').trim();
    const model = String(input.model || '').trim();
    const baseUrl = normalizeBaseUrl(input.baseUrl);
    const secret = String(input.key || '').trim() || existing?.secret || '';
    if (!name || name.length > 80) throw new Error('请填写 AI 配置名称（1–80 字）');
    if (!model || model.length > 200) throw new Error('请填写模型 ID');
    if (!secret) throw new Error('请填写 API Key');
    const maxOutputTokens = Number(input.maxOutputTokens || 4096);
    if (!Number.isInteger(maxOutputTokens) || maxOutputTokens < 100 || maxOutputTokens > 100000) {
      throw new Error('输出上限需为 100–100000');
    }
    const entry = {
      id: existing?.id || crypto.randomUUID(),
      name,
      baseUrl,
      model,
      maxOutputTokens,
      secret,
    };
    if (existing) {
      Object.assign(existing, entry);
    } else {
      this.providers.push(entry);
    }
    this.vault.save(this.providers);
    return entry;
  }

  removeProvider(id) {
    const index = this.providers.findIndex((p) => p.id === id);
    if (index < 0) throw new Error('AI 配置不存在');
    this.providers.splice(index, 1);
    this.vault.save(this.providers);
  }

  revealProviderKey(id: string): string {
    const provider = this.providers.find((p) => p.id === id);
    if (!provider || !provider.secret) {
      throw new Error('AI 配置或密钥不存在');
    }
    return provider.secret;
  }

  async testProvider(input: { id?: string; baseUrl?: string; model?: string; key?: string }) {
    const existing = this.providers.find((p) => p.id === input.id);
    const baseUrl = normalizeBaseUrl(input.baseUrl || existing?.baseUrl);
    const model = String(input.model || existing?.model || '').trim();
    const secret = String(input.key || '').trim() || existing?.secret || '';
    if (!secret) throw new Error('请先填写 API Key');
    if (!model) throw new Error('请先选择或填写模型 ID');
    const started = Date.now();
    const res = await this.http.fetch(`${baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${secret}`,
      },
      body: JSON.stringify({
        model,
        messages: [{ role: 'user', content: 'Reply OK' }],
        max_tokens: 16,
      }),
      timeout: 15000,
    });
    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      throw new Error(`连接失败（HTTP ${res.status}）: ${this.redact(detail).slice(0, 200)}`);
    }
    const data = (await res.json()) as { choices?: Array<{ message?: { content?: string } }> };
    const reply = String(data?.choices?.[0]?.message?.content || '').trim().slice(0, 60);
    return {
      ok: true,
      model,
      latencyMs: Date.now() - started,
      reply,
    };
  }

  async listModels(input) {
    const existing = this.providers.find((p) => p.id === input.id);
    const baseUrl = normalizeBaseUrl(input.baseUrl || existing?.baseUrl);
    const secret = String(input.key || '').trim() || existing?.secret || '';
    if (!secret) throw new Error('请先填写 API Key');
    const data = await this.http.json<{ data?: Array<string | { id?: string }> } | Array<string | { id?: string }>>(
      `${baseUrl}/models`,
      {
        headers: { Authorization: `Bearer ${secret}` },
        timeout: 20000,
      },
    );
    const list = Array.isArray(data) ? data : Array.isArray(data?.data) ? data.data : [];
    return list
      .map((item) => (typeof item === 'string' ? item : item?.id))
      .filter((id) => typeof id === 'string' && id.trim())
      .sort()
      .slice(0, 3000);
  }

  resolve(providerId) {
    const provider = providerId
      ? this.providers.find((p) => p.id === providerId)
      : this.providers[0];
    if (!provider) {
      throw new Error('未找到可用的 AI 配置');
    }
    return provider;
  }

  async generate(providerId, input, signal) {
    const provider = this.resolve(providerId);
    const opts = typeof input === 'string' ? { prompt: input } : input;
    const messages = [];
    if (opts.system) {
      messages.push({ role: 'system', content: String(opts.system) });
    }
    if (Array.isArray(opts.messages)) {
      messages.push(...opts.messages);
    } else if (opts.prompt) {
      messages.push({ role: 'user', content: String(opts.prompt) });
    }
    const body = {
      model: opts.model || provider.model,
      messages,
      max_tokens: opts.maxTokens || provider.maxOutputTokens,
      ...(opts.temperature !== undefined ? { temperature: opts.temperature } : {}),
      ...(opts.jsonMode ? { response_format: { type: 'json_object' } } : {}),
    };
    const res = await this.http.fetch(`${provider.baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${provider.secret}`,
      },
      body: JSON.stringify(body),
      signal,
      timeout: opts.timeout ?? 60000,
    });
    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      throw new Error(`AI 请求失败（HTTP ${res.status}）: ${this.redact(detail).slice(0, 200)}`);
    }
    const data = await res.json();
    const content = data?.choices?.[0]?.message?.content;
    if (typeof content !== 'string') {
      throw new Error('AI 未返回有效文本内容');
    }
    return content.trim();
  }

  async json(providerId, input, signal) {
    const opts = typeof input === 'string' ? { prompt: input } : input;
    const text = await this.generate(providerId, { ...opts, jsonMode: true }, signal);
    const cleaned = text.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/i, '').trim();
    return JSON.parse(cleaned);
  }

  forTask(providerId) {
    const provider = providerId ? this.providers.find((p) => p.id === providerId) : undefined;
    if (!provider) {
      return null;
    }
    return {
      config: {
        id: provider.id,
        name: provider.name,
        baseUrl: provider.baseUrl,
        apiKey: provider.secret,
        model: provider.model,
        maxOutputTokens: provider.maxOutputTokens,
      },
      generate: (input, signal) => this.generate(provider.id, input, signal),
      json: (input, signal) => this.json(provider.id, input, signal),
    };
  }
}
