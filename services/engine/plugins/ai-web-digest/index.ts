import { definePlugin } from '../../sdk/index.ts';

interface DigestConfig {
  url: string;
  interest: string;
  limit: number;
  aiProvider: string;
}

interface DigestAIResult {
  title?: string;
  items?: Array<{ title?: string; summary?: string; url?: string }>;
}

function htmlToText(html: string): string {
  return String(html || '')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export default definePlugin({
  name: 'ai-web-digest',
  inject: { required: ['source', 'http'] },
  apply(ctx) {
    ctx.source.register<DigestConfig>({
    id: 'ai-web-digest',
    name: 'AI 网页兴趣速览',
    description: '抓取指定网页或 JSON 接口，由 AI 按你的自然语言规则提炼重点',
    version: '1.0.0',
    fields: [
      {
        key: 'aiProvider',
        label: 'AI 模型',
        type: 'aiProvider',
        required: true,
        help: '选择服务器已配置的 AI 服务商用于内容筛选与提炼。',
      },
      {
        key: 'url',
        label: '目标网址',
        type: 'text',
        required: true,
        placeholder: 'https://news.ycombinator.com',
      },
      {
        key: 'interest',
        label: '筛选与总结要求',
        type: 'textarea',
        required: true,
        placeholder: '例如：只挑出与 AI Agent、开源工具相关的内容，每条用 2 句话说明核心价值',
      },
      {
        key: 'limit',
        label: '最多提炼条数',
        type: 'number',
        default: 5,
        min: 1,
        max: 15,
      },
    ],
    async run(job) {
      const { config, ai, http, signal, log } = job;
      log('fetch', `读取 ${config.url}`);
      const raw = await http.text(config.url, { signal });
      const text = htmlToText(raw).slice(0, 18000);
      if (!text) {
        return { message: null, detail: '目标页面正文为空' };
      }

      log('ai', '正在使用 AI 筛选并总结');
      if (!ai) {
        return { message: null, detail: '未配置 AI 服务' };
      }
      const result = await ai.json<DigestAIResult>(
        {
          system:
            '你是信息筛选与摘要助手。请严格返回 JSON 对象：{"title":"简短标题","items":[{"title":"条目标题","summary":"中文摘要","url":"原文链接或空字符串"}]}。若无符合要求的内容，items 返回空数组。',
          prompt: `用户关注要求：${config.interest}\n最多条数：${config.limit || 5}\n来源地址：${config.url}\n\n页面内容：\n${text}`,
        },
        signal,
      );

      const items = Array.isArray(result?.items) ? result.items.filter((i): i is { title: string; summary?: string; url?: string } => Boolean(i?.title)).slice(0, config.limit || 5) : [];
      if (!items.length) {
        return { message: null, detail: 'AI 未发现符合关注要求的新内容' };
      }

      return {
        message: {
          title: result.title || job.taskName,
          short: items.slice(0, 2).map((i) => i.title).join('；'),
          articles: items.map((item) => ({
            title: item.title,
            body: item.summary || '',
            source: new URL(config.url).hostname,
            url: item.url || config.url,
          })),
        },
        detail: `AI 提炼了 ${items.length} 条重点`,
      };
    },
  });
  },
});
