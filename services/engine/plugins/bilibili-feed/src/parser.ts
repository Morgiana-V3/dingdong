import type { TaskAIService } from 'dingdong-engine/sdk';
import type { BilibiliDynamicItem, BilibiliRichTextNode, ParsedDynamic, RichSegment } from './types.ts';

function normalizeUrl(raw?: string): string {
  if (!raw) return '';
  if (raw.startsWith('//')) return 'https:' + raw;
  return raw.replace(/^http:\/\//i, 'https://');
}

function buildRichSegments(nodes?: BilibiliRichTextNode[], fallbackText?: string): RichSegment[] {
  if (Array.isArray(nodes) && nodes.length) {
    const segments: RichSegment[] = [];
    for (const node of nodes) {
      if (node.type === 'RICH_TEXT_NODE_TYPE_EMOJI' && node.emoji?.icon_url) {
        segments.push({
          type: 'emoji',
          text: node.emoji.text || node.text || '',
          url: normalizeUrl(node.emoji.icon_url),
        });
      } else {
        const text = node.text ?? node.orig_text ?? '';
        if (text) {
          segments.push({ type: 'text', text });
        }
      }
    }
    return segments;
  }
  return fallbackText ? [{ type: 'text', text: fallbackText }] : [];
}

export function parseDynamics(
  rawItems: BilibiliDynamicItem[],
  seen: Set<string>,
  options: { upIds?: string[]; keywords?: string } = {},
): ParsedDynamic[] {
  const allowedUps = new Set((options.upIds || []).map((id) => String(id).trim()).filter(Boolean));
  const keywords = String(options.keywords || '')
    .split(/[,，]/)
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);

  return rawItems
    .map((item): ParsedDynamic => {
      const id = item.id_str || '';
      const authorMid = item.modules?.module_author?.mid ? String(item.modules.module_author.mid) : '';
      const author = item.modules?.module_author?.name || 'B 站 UP 主';
      const pubTs = item.modules?.module_author?.pub_ts;
      const dyn = item.modules?.module_dynamic;
      const archive = dyn?.major?.archive;
      const opus = dyn?.major?.opus;
      const draw = dyn?.major?.draw;

      const isVideo = Boolean(archive?.bvid || archive?.title);
      const richNodes = opus?.summary?.rich_text_nodes || dyn?.desc?.rich_text_nodes;
      const fallbackText = [archive?.desc, opus?.summary?.text, dyn?.desc?.text]
        .filter((part): part is string => Boolean(part && part.trim()))
        .join('\n\n')
        .slice(0, 1200);
      const bodySegments = buildRichSegments(richNodes, fallbackText);
      const bodyText = bodySegments.map((s) => s.text).join('').slice(0, 1200);

      const title =
        archive?.title ||
        opus?.title ||
        bodyText.split('\n')[0].trim().slice(0, 64) ||
        `${author} 的新动态`;

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
        authorMid,
        title,
        bodyText,
        bodySegments,
        source: author,
        url,
        isVideo,
        duration: archive?.duration_text,
        images: [...new Set(images)].slice(0, 6),
        publishedAt: pubTs ? pubTs * 1000 : undefined,
      };
    })
    .filter((item) => Boolean(item.id) && !seen.has(item.id))
    .filter((item) => !allowedUps.size || allowedUps.has(item.authorMid))
    .filter((item) => {
      if (!keywords.length) return true;
      const hay = `${item.title} ${item.bodyText} ${item.source}`.toLowerCase();
      return keywords.some((kw) => hay.includes(kw));
    });
}

export async function filterDynamicsWithAI(
  items: ParsedDynamic[],
  filterPrompt: string | undefined,
  ai: TaskAIService | null,
  signal: AbortSignal,
): Promise<ParsedDynamic[]> {
  if (!ai || !filterPrompt?.trim() || !items.length) return items;
  try {
    const candidates = items.map((item, idx) => ({
      index: idx,
      author: item.source,
      title: item.title,
      body: item.bodyText.slice(0, 240),
    }));
    const res = await ai.json<{ keep?: number[] }>(
      {
        system:
          '你是内容过滤助手。根据用户的过滤要求，决定保留哪些候选动态。仅返回 JSON 对象 {"keep":[索引数字数组]}。',
        prompt: `过滤要求：${filterPrompt.trim()}\n\n候选列表：\n${JSON.stringify(candidates)}`,
        maxTokens: 300,
      },
      signal,
    );
    if (!Array.isArray(res?.keep)) return items;
    const keepSet = new Set(res.keep.filter((n) => Number.isInteger(n)));
    return items.filter((_, idx) => keepSet.has(idx));
  } catch {
    return items;
  }
}

export async function buildSummaryLine(
  items: ParsedDynamic[],
  ai: TaskAIService | null,
  signal: AbortSignal,
): Promise<string> {
  const fallback = items.slice(0, 2).map((i) => i.title).join('；');
  if (!ai || !items.length) return fallback;
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
