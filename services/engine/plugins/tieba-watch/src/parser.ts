import type { TiebaThread } from './types.ts';

function safeImageUrl(raw: unknown): string {
  const value = typeof raw === 'string' ? raw.trim() : '';
  if (!value) return '';
  try {
    const u = new URL(value);
    if (u.protocol !== 'http:' && u.protocol !== 'https:') return '';
    if (
      u.protocol === 'http:' &&
      (u.hostname.endsWith('.bdimg.com') ||
        u.hostname.endsWith('.bdstatic.com') ||
        u.hostname === 'tiebapic.baidu.com' ||
        u.hostname === 'imgsrc.baidu.com')
    ) {
      u.protocol = 'https:';
    }
    return u.toString();
  } catch {
    return '';
  }
}

function formatTime(unixSec: unknown): string {
  const n = Number(unixSec || 0);
  if (!Number.isFinite(n) || n <= 0) return '';
  const d = new Date(n * 1000);
  const pad = (v: number) => String(v).padStart(2, '0');
  return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function parseTiebaThreads(
  payload: Record<string, any>,
  forumName: string,
  includePinned: boolean,
): TiebaThread[] {
  const kw = forumName.trim().replace(/吧$/, '');
  const list = Array.isArray(payload.thread_list) ? payload.thread_list : [];
  const users = new Map<string, string>();
  for (const u of Array.isArray(payload.user_list) ? payload.user_list : []) {
    if (u?.id != null) {
      users.set(String(u.id), String(u.name_show || u.name || '贴吧用户'));
    }
  }

  const out: TiebaThread[] = [];
  for (const raw of list) {
    const id = String(raw?.id || '').trim();
    if (!/^\d+$/.test(id)) continue;
    const isPinned = Number(raw?.is_top || 0) !== 0 || Number(raw?.is_membertop || 0) !== 0;
    if (isPinned && !includePinned) continue;
    const isGood = Number(raw?.is_good || 0) !== 0 || Number(raw?.is_excellent_thread || 0) !== 0;

    const authorObj = raw?.author && typeof raw.author === 'object' ? raw.author : null;
    const author =
      String(authorObj?.name_show || authorObj?.name || '').trim() ||
      users.get(String(authorObj?.id ?? raw?.author_id ?? '')) ||
      '贴吧用户';

    const title = String(raw?.title || '').trim();
    const parts: unknown[] = Array.isArray(raw?.first_post_content) && raw.first_post_content.length
      ? raw.first_post_content
      : Array.isArray(raw?.abstract)
        ? raw.abstract
        : [];
    const textSegments: string[] = [];
    const images: string[] = [];

    for (const part of parts as Array<Record<string, any>>) {
      const type = Number(part?.type || 0);
      if (type === 3) {
        const img =
          safeImageUrl(part?.origin_src) ||
          safeImageUrl(part?.big_cdn_src) ||
          safeImageUrl(part?.cdn_src) ||
          safeImageUrl(part?.src);
        if (img && !images.includes(img)) images.push(img);
      } else if (type === 2) {
        textSegments.push(`[${part?.c || '表情'}]`);
      } else if (part?.text) {
        textSegments.push(String(part.text));
      }
    }

    if (!images.length && Array.isArray(raw?.media)) {
      for (const m of raw.media) {
        if (Number(m?.type) !== 3) continue;
        const img =
          safeImageUrl(m?.origin_pic) ||
          safeImageUrl(m?.src_pic) ||
          safeImageUrl(m?.big_pic);
        if (img && !images.includes(img)) images.push(img);
      }
    }

    const excerpt = textSegments.join('').replace(/\s+/g, ' ').trim();
    const finalTitle = title || (excerpt ? excerpt.slice(0, 48) : '无标题帖子');

    out.push({
      id,
      forum: `${kw}吧`,
      title: finalTitle,
      author,
      excerpt: excerpt === finalTitle ? '' : excerpt.slice(0, 260),
      url: `https://tieba.baidu.com/p/${id}`,
      replyCount: Number(raw?.reply_num || 0),
      isPinned,
      isGood,
      publishedAt: formatTime(raw?.create_time || raw?.last_time_int),
      images: images.slice(0, 4),
    });
  }
  return out;
}
