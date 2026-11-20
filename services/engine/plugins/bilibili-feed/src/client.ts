import { AuthExpiredError } from '../../../sdk/index.ts';
import type { HttpService } from '../../../sdk/index.ts';
import { loadImage } from '../../../src/images.ts';
import type { BilibiliDynamicItem, BilibiliFeedResponse, BilibiliNavResponse } from './types.ts';

export async function verifyBilibiliSession(cookie: string, http: HttpService) {
  const nav = await http.json<BilibiliNavResponse>('https://api.bilibili.com/x/web-interface/nav', {
    headers: {
      cookie,
      referer: 'https://www.bilibili.com/',
    },
  });
  if (nav.code !== 0 || !nav.data?.isLogin) {
    throw new Error(nav.message || 'B 站登录状态无效，请重新登录');
  }
  let avatar: string | undefined;
  const face = nav.data.face?.replace(/^http:\/\//i, 'https://');
  if (face && face.startsWith('https://')) {
    try {
      avatar = await loadImage(face, 32_000);
    } catch {
      // 头像拉取失败不影响登录验证
    }
  }
  return {
    id: String(nav.data.mid || ''),
    name: nav.data.uname || 'B 站用户',
    ...(avatar ? { avatar } : {}),
  };
}

export async function fetchBilibiliDynamics(
  feedType: 'all' | 'video',
  cookie: string,
  http: HttpService,
  signal: AbortSignal,
): Promise<BilibiliDynamicItem[]> {
  const typeParam = feedType === 'all' ? 'all' : 'video';
  const res = await http.json<BilibiliFeedResponse>(
    `https://api.bilibili.com/x/polymer/web-dynamic/v1/feed/all?type=${typeParam}`,
    {
      headers: {
        cookie,
        referer: 'https://t.bilibili.com/',
      },
      signal,
    },
  );
  if (res.code === -101 || res.code === -111) {
    throw new AuthExpiredError('bilibili', 'B 站登录会话已过期，请在手机重新登录');
  }
  if (res.code !== 0) {
    throw new Error(`B 站接口返回异常（code=${res.code}）：${res.message || '未知错误'}`);
  }
  return Array.isArray(res.data?.items) ? res.data.items : [];
}
