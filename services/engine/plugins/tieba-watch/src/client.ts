import { createHash } from 'node:crypto';
import type { HttpService } from 'dingdong-engine/sdk';

export async function fetchTiebaForumPage(
  http: HttpService,
  forumName: string,
  options: { sort: 'latest_reply' | 'latest_post' | 'good'; signal?: AbortSignal },
): Promise<Record<string, any>> {
  const kw = forumName.trim().replace(/吧$/, '');
  const params: Record<string, string> = {
    _client_type: '2',
    _client_version: '12.20.1.0',
    kw,
    sort_type: options.sort === 'latest_post' ? '0' : '1',
    is_good: options.sort === 'good' ? '1' : '0',
    pn: '1',
    rn: '30',
  };
  const sorted = Object.keys(params)
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join('');
  params.sign = createHash('md5')
    .update(`${sorted}tiebaclient!!!`, 'utf8')
    .digest('hex');

  const body = new URLSearchParams(params).toString();
  const res = await http.fetch('https://tieba.baidu.com/c/f/frs/page', {
    method: 'POST',
    signal: options.signal,
    headers: {
      'content-type': 'application/x-www-form-urlencoded; charset=utf-8',
      'user-agent': 'bdtb for Android 12.20.1.0',
    },
    body,
  });
  if (!res.ok) {
    throw new Error(`贴吧接口返回 HTTP ${res.status}（${kw}吧）`);
  }
  const text = await res.text();
  let data: Record<string, any>;
  try {
    data = JSON.parse(text);
  } catch {
    throw new Error(`贴吧（${kw}吧）返回非 JSON 响应，可能触发了频率限制`);
  }
  if (Number(data?.error_code) !== 0) {
    throw new Error(`贴吧接口异常（${kw}吧）：${data?.error_msg || data?.error_code}`);
  }
  return data;
}
