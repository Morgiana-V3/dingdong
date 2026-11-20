import { ProxyAgent, fetch as undiciFetch } from 'undici';

const proxyUrl = process.env.HTTPS_PROXY || process.env.HTTP_PROXY || process.env.ENGINE_PROXY || '';
const dispatcher = proxyUrl ? new ProxyAgent(proxyUrl) : undefined;

export function isPrivateHost(hostname) {
  const host = String(hostname || '').toLowerCase().replace(/^\[|\]$/g, '');
  if (!host || host === 'localhost' || host.endsWith('.localhost') || host.endsWith('.local')) {
    return true;
  }
  if (/^127\./.test(host) || /^10\./.test(host) || /^192\.168\./.test(host) || /^169\.254\./.test(host)) {
    return true;
  }
  if (/^172\.(1[6-9]|2\d|3[01])\./.test(host) || host === '0.0.0.0') {
    return true;
  }
  if (host === '::1' || host.startsWith('fe80:') || host.startsWith('fc') || host.startsWith('fd')) {
    return true;
  }
  return false;
}

import type { HttpRequestOptions, HttpService } from '../sdk/dingdong-plugin.d.ts';

export function createHttpService(): HttpService {
  async function request(url: string, options: HttpRequestOptions = {}): Promise<Response> {
    const parsed = new URL(url);
    if (!['http:', 'https:'].includes(parsed.protocol)) {
      throw new Error(`不支持的协议: ${parsed.protocol}`);
    }
    const timeoutMs = options.timeout ?? 20000;
    const signals: AbortSignal[] = [AbortSignal.timeout(timeoutMs)];
    if (options.signal) {
      signals.push(options.signal);
    }
    const headers = new Headers(options.headers);
    if (!headers.has('user-agent')) {
      headers.set('user-agent', 'DingdongEngine/0.2 (+https://github.com/Morgiana-V3/dingdong)');
    }
    const useProxy = options.proxy === false ? undefined : dispatcher;
    return undiciFetch(parsed, {
      ...(options as Record<string, unknown>),
      headers: Object.fromEntries(headers.entries()),
      signal: AbortSignal.any(signals),
      dispatcher: useProxy,
    }) as unknown as Promise<Response>;
  }

  async function text(url: string, options: HttpRequestOptions = {}): Promise<string> {
    const res = await request(url, options);
    if (!res.ok) {
      await res.body?.cancel();
      throw new Error(`HTTP ${res.status}: ${url}`);
    }
    return res.text();
  }

  async function json<T = unknown>(url: string, options: HttpRequestOptions = {}): Promise<T> {
    const res = await request(url, options);
    if (!res.ok) {
      await res.body?.cancel();
      throw new Error(`HTTP ${res.status}: ${url}`);
    }
    return res.json() as Promise<T>;
  }

  return { fetch: request, text, json };
}
