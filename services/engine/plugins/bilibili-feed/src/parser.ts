import type { TaskAIService } from '../../../sdk/index.ts';
import type { BilibiliDynamicItem, ParsedDynamic } from './types.ts';

function normalizeUrl(raw?: string): string {
  if (!raw) return '';
  if (raw.startsWith('//')) return 'https:' + raw;
  return raw;
}

export function parseDynamics(
  rawItems: BilibiliDynamicItem[],
  seen: Set<string>,
  keywordsRaw?: string,
): ParsedDynamic[] {
  const keywords = String(keywordsRaw || '')
    .split(/[,，]/)
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);

  return rawItems
    .map((item): ParsedDynamic => {
      const id = item.id_str || '';
      const author = item.modules?.module_author?.name || 'B 站 UP 主';
      const pubTs = item.modules?.module_author?.pub_ts;
      const dyn = item.modules?.module_dynamic;
      const archive = dyn?.major?.archive;
      const opus = dyn?.major?.opus;
      const draw = dyn?.major?.draw;

      const title =
        archive?.title ||
        opus?.title ||
        (dyn?.desc?.text || '').split('\n')[0].slice(0, 60) ||
        `${author} 的新动态`;

      const body = [archive?.desc, opus?.summary?.text, dyn?.desc?.text]
        .filter((part): part is string => Boolean(part && part.trim()))
        .join('\n\n')
        .slice(0, 1200);

      const url = archive?.bvid
        ? `https://www.bilibili.com/video/${archive.bvid}`
        : normalizeUrl(archive?.jump_url || opus?.jump_url) ||
          (id ? `https://t.bilibili.com/${id}` : 'https://t.bilibili.com/');

      const images: string[] = [];
      if (archive?.cover) images.push(normalizeUrl(archive.cover));
      for (const pic of opus?.pics || []) {
        if (pic.url) images.push(normalizeUrl(pic.url));
      }
      for (const pic of draw?.items || []) {
        if (pic.src) images.push(normalizeUrl(pic.src));
      }

      return {
        id,
        title,
        body,
        source: author,
        url,
        images: images.slice(0, 3),
        publishedAt: pubTs ? pubTs * 1000 : undefined,
      };
    })
    .filter((item) => Boolean(item.id) && !seen.has(item.id))
    .filter((item) => {
      if (!keywords.length) return true;
      const hay = `${item.title} ${item.body} ${item.source}`.toLowerCase();
      return keywords.some((kw) => hay.includes(kw));
    });
}

export async function buildSummaryLine(
  items: ParsedDynamic[],
  useAI: boolean,
  ai: TaskAIService | null,
  signal: AbortSignal,
): Promise<string> {
  const fallback = items.slice(0, 2).map((i) => i.title).join('；');
  if (!useAI || !ai) return fallback;
  try {
    const digest = await ai.generate(
      {
        system: '用不超过 80 字的中文一句话概括以下 B 站动态看点，不要分点，不要使用 Markdown。',
        prompt: items.map((i) => `- [${i.source}] ${i.title}`).join('\n'),
        maxTokens: 200,
      },
      signal,
    );
    return digest || fallback;
  } catch {
    return fallback;
  }
}
