import type { HttpService } from 'dingdong-engine/sdk';

const BASE = 'https://api.fxtwitter.com';
const HEADERS = {
  accept: 'application/json',
  'user-agent': 'Dingdong/0.2.0 (public read-only client)',
};

async function getJson(
  http: HttpService,
  pathWithQuery: string,
  signal?: AbortSignal,
): Promise<Record<string, any>> {
  const res = await http.fetch(`${BASE}${pathWithQuery}`, {
    method: 'GET',
    signal,
    headers: HEADERS,
  });
  let body: Record<string, any> | null = null;
  try {
    body = (await res.json()) as Record<string, any>;
  } catch {
    body = null;
  }
  const status = res.ok ? Number(body?.code || 200) : res.status;
  if (status === 429) {
    throw new Error('X 公开接口暂时限流，请稍后重试');
  }
  if (status === 404) {
    throw new Error('未找到该 X 账号或内容（可能未公开）');
  }
  if (status !== 200 || !body) {
    throw new Error(`X 公开接口请求失败（HTTP ${status}）`);
  }
  return body;
}

export async function fetchXProfileStatuses(
  http: HttpService,
  handle: string,
  signal?: AbortSignal,
): Promise<any[]> {
  const clean = handle.trim().replace(/^@/, '');
  if (!/^[A-Za-z0-9_]{1,15}$/.test(clean)) {
    throw new Error(`X 用户名无效：${handle}`);
  }
  const body = await getJson(http, `/2/profile/${encodeURIComponent(clean)}/statuses`, signal);
  return Array.isArray(body.results) ? body.results : [];
}

export async function fetchXSearchStatuses(
  http: HttpService,
  query: string,
  signal?: AbortSignal,
): Promise<any[]> {
  const params = new URLSearchParams({
    q: query.trim(),
    feed: 'latest',
    count: '20',
  });
  const body = await getJson(http, `/2/search?${params.toString()}`, signal);
  return Array.isArray(body.results) ? body.results : [];
}
