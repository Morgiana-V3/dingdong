import { definePlugin } from 'dingdong-engine/sdk';

interface RssConfig {
  feeds: string[];
  keywords?: string;
  limit: number;
}

interface RssState {
  seenIds?: string[];
}

function decodeXml(str: string): string {
  return String(str || '')
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, '$1')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&')
    .trim();
}

function stripTags(html) {
  return decodeXml(html).replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
}

function tagText(block, tag) {
  const m = new RegExp(`<${tag}(?:\\s[^>]*)?>([\\s\\S]*?)<\\/${tag}>`, 'i').exec(block);
  return m ? decodeXml(m[1]) : '';
}

function parseFeed(xml) {
  const items = [];
  const rssMatches = [...xml.matchAll(/<item\b[^>]*>([\s\S]*?)<\/item>/gi)];
  if (rssMatches.length) {
    for (const [, block] of rssMatches) {
      const title = stripTags(tagText(block, 'title'));
      const link = stripTags(tagText(block, 'link'));
      const guid = stripTags(tagText(block, 'guid')) || link || title;
      const body = stripTags(tagText(block, 'description') || tagText(block, 'content:encoded')).slice(0, 800);
      const publishedAt = stripTags(tagText(block, 'pubDate'));
      if (title) items.push({ id: guid, title, url: link, body, publishedAt });
    }
    return items;
  }
  const atomMatches = [...xml.matchAll(/<entry\b[^>]*>([\s\S]*?)<\/entry>/gi)];
  for (const [, block] of atomMatches) {
    const title = stripTags(tagText(block, 'title'));
    const linkMatch = /<link\b[^>]*href=["']([^"']+)["']/i.exec(block);
    const link = linkMatch ? decodeXml(linkMatch[1]) : '';
    const id = stripTags(tagText(block, 'id')) || link || title;
    const body = stripTags(tagText(block, 'summary') || tagText(block, 'content')).slice(0, 800);
    const publishedAt = stripTags(tagText(block, 'updated') || tagText(block, 'published'));
    if (title) items.push({ id, title, url: link, body, publishedAt });
  }
  return items;
}

export default definePlugin({
  name: 'rss-watch',
  inject: { required: ['source', 'http'] },
  apply(ctx) {
    ctx.source.register<RssConfig, RssState>({
    id: 'rss-watch',
    name: 'RSS / Atom 订阅',
    description: '定时拉取任意 RSS 或 Atom 源，自动去重并推送新文章',
    version: '1.0.0',
    fields: [
      {
        key: 'feeds',
        label: '订阅地址列表',
        type: 'stringList',
        required: true,
        maxItems: 20,
        placeholder: '每行一个 RSS/Atom 地址，例如 https://hnrss.org/frontpage',
      },
      {
        key: 'keywords',
        label: '关键词过滤（可选）',
        type: 'text',
        placeholder: '逗号分隔，留空表示不过滤',
      },
      {
        key: 'limit',
        label: '单次最多推送条数',
        type: 'number',
        default: 10,
        min: 1,
        max: 30,
      },
    ],
    async run(job) {
      const { config, state, http, signal, log } = job;
      const seen = new Set(Array.isArray(state.seenIds) ? state.seenIds : []);
      const keywords = String(config.keywords || '')
        .split(/[,，]/)
        .map((s) => s.trim().toLowerCase())
        .filter(Boolean);

      const collected = [];
      for (const feedUrl of config.feeds || []) {
        signal.throwIfAborted();
        log('fetch', `拉取 ${feedUrl}`);
        const xml = await http.text(feedUrl, { signal });
        const feedHost = new URL(feedUrl).hostname;
        for (const item of parseFeed(xml)) {
          if (seen.has(item.id)) continue;
          if (keywords.length) {
            const hay = `${item.title} ${item.body}`.toLowerCase();
            if (!keywords.some((kw) => hay.includes(kw))) continue;
          }
          collected.push({ ...item, source: feedHost });
        }
      }

      const fresh = collected.slice(0, config.limit || 10);
      const nextSeen = [...seen, ...fresh.map((i) => i.id)].slice(-1000);
      if (!fresh.length) {
        return { message: null, state: { seenIds: nextSeen }, detail: '本轮没有新文章' };
      }
      return {
        message: {
          title: `${job.taskName}（${fresh.length} 篇更新）`,
          short: fresh.slice(0, 2).map((i) => i.title).join('；'),
          articles: fresh.map((item) => ({
            title: item.title,
            body: item.body,
            source: item.source,
            url: item.url,
            publishedAt: item.publishedAt,
          })),
        },
        state: { seenIds: nextSeen },
        detail: `发现并推送 ${fresh.length} 篇新文章`,
      };
    },
  });
  },
});
