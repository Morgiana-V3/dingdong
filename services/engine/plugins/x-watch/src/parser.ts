import type { XPost } from './types.ts';

function safeHttps(raw: unknown): string {
  const v = typeof raw === 'string' ? raw.trim() : '';
  if (!v) return '';
  try {
    const u = new URL(v);
    return u.protocol === 'https:' ? u.toString() : '';
  } catch {
    return '';
  }
}

function formatDate(raw: unknown): string {
  if (!raw) return '';
  const d = typeof raw === 'number' ? new Date(raw * 1000) : new Date(String(raw));
  if (Number.isNaN(d.getTime())) return '';
  const pad = (v: number) => String(v).padStart(2, '0');
  return `${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

export function parseXStatuses(
  rows: unknown[],
  includeReposts: boolean,
): XPost[] {
  const out: XPost[] = [];
  for (const raw of rows as Array<Record<string, any>>) {
    const id = String(raw?.id || '').trim();
    if (raw?.type !== 'status' || !/^\d+$/.test(id)) continue;
    const author = raw?.author && typeof raw.author === 'object' ? raw.author : {};
    if (author.protected === true) continue;

    const repost = raw?.reposted_by && typeof raw.reposted_by === 'object' ? raw.reposted_by : null;
    if (repost && !includeReposts) continue;

    const handle = String(author.screen_name || '').trim();
    const name = String(author.name || handle || 'X 用户').trim();
    const text = String(raw?.text || '').trim();

    const images: string[] = [];
    let hasVideo = false;
    const mediaAll = Array.isArray(raw?.media?.all) ? raw.media.all : [];
    for (const m of mediaAll) {
      const isPhoto = m?.type === 'photo';
      if (!isPhoto) hasVideo = true;
      const img = safeHttps(isPhoto ? m?.url : m?.thumbnail_url);
      if (img && !images.includes(img)) images.push(img);
    }

    let quote: XPost['quote'];
    if (raw?.quote && typeof raw.quote === 'object') {
      const qa = raw.quote.author || {};
      const qt = String(raw.quote.text || '').trim();
      if (qt) {
        quote = {
          authorName: String(qa.name || qa.screen_name || 'X 用户'),
          authorHandle: String(qa.screen_name || ''),
          text: qt.slice(0, 220),
        };
      }
    }

    out.push({
      id,
      authorName: name,
      authorHandle: handle,
      repostedBy: repost ? String(repost.name || repost.screen_name || '') : undefined,
      text: text.slice(0, 800),
      url: handle ? `https://x.com/${handle}/status/${id}` : `https://x.com/i/status/${id}`,
      publishedAt: formatDate(raw?.created_timestamp || raw?.created_at),
      images: images.slice(0, 4),
      hasVideo,
      quote,
      likes: Number(raw?.likes || 0),
      reposts: Number(raw?.retweets || raw?.reposts || 0),
      replies: Number(raw?.replies || 0),
    });
  }
  return out;
}
