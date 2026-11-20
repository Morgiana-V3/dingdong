import { AuthExpiredError, definePlugin, renderHtmlTemplate } from '../../../sdk/index.ts';
import { fetchBilibiliDynamics } from './client.ts';
import { buildSummaryLine, parseDynamics } from './parser.ts';
import { bilibiliAuth, bilibiliFields } from './schema.ts';
import type { BilibiliFeedConfig, BilibiliFeedState } from './types.ts';

export default definePlugin({
  name: 'bilibili-feed',
  inject: { required: ['source', 'http'] },
  apply(ctx) {
    ctx.source.register<BilibiliFeedConfig, BilibiliFeedState>({
      id: 'bilibili-feed',
      name: 'B 站关注动态',
      description: '官方多文件插件参考：演示手机网页登录回传 Cookie、通用表单原语、增量去重与可选 AI 导读',
      version: '1.0.0',
      auth: bilibiliAuth,
      fields: bilibiliFields,
      async run(job) {
        const { config, state, credential, http, signal, log } = job;
        const ai = job.getAI(config.aiProvider);
        if (!credential || !('cookie' in credential)) {
          throw new AuthExpiredError('bilibili', '尚未配置 B 站登录会话');
        }

        const feedType = config.feedType === 'all' ? 'all' : 'video';
        log('fetch', `拉取 B 站关注动态（${feedType === 'video' ? '仅视频' : '全部'}）`);
        const rawItems = await fetchBilibiliDynamics(feedType, credential.cookie, http, signal);

        const seen = new Set<string>(Array.isArray(state.seenIds) ? state.seenIds : []);
        const fresh = parseDynamics(rawItems, seen, config.keywords).slice(0, config.limit || 8);
        const nextSeen = [...seen, ...rawItems.map((i) => i.id_str || '').filter(Boolean)].slice(-1000);

        if (!fresh.length) {
          return {
            message: null,
            state: { seenIds: nextSeen, initialized: true },
            detail: '本轮没有新的关注动态',
          };
        }

        if (ai) {
          log('ai', '正在使用 AI 生成动态导读');
        }
        const summaryLine = await buildSummaryLine(fresh, Boolean(ai), ai, signal);
        const html = renderHtmlTemplate(new URL('./template', import.meta.url), {
          taskName: job.taskName,
          aiSummary: ai ? summaryLine : '',
          items: fresh,
        });

        return {
          message: {
            title: `${job.taskName}（${fresh.length} 条更新）`,
            short: summaryLine,
            format: 'html',
            content: html,
          },
          state: { seenIds: nextSeen, initialized: true },
          detail: `发现并推送 ${fresh.length} 条 B 站动态`,
        };
      },
    });
  },
});
