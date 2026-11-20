import { AuthExpiredError, definePlugin, renderHtmlTemplate } from 'dingdong-engine/sdk';
import { fetchBilibiliDynamics, fetchBilibiliFollowings } from './client.ts';
import { buildSummaryLine, filterDynamicsWithAI, parseDynamics } from './parser.ts';
import { bilibiliAuth, bilibiliFields } from './schema.ts';
import type { BilibiliFeedConfig, BilibiliFeedState } from './types.ts';

export default definePlugin({
  name: 'bilibili-feed',
  inject: { required: ['source', 'http'] },
  apply(ctx) {
    ctx.source.register<BilibiliFeedConfig, BilibiliFeedState>({
      id: 'bilibili-feed',
      name: 'B 站关注动态',
      description: '官方示范插件：支持关注 UP 主搜索多选、双模型过滤与导读、B 站表情与图文排版',
      version: '1.1.0',
      auth: bilibiliAuth,
      fields: bilibiliFields,

      // 供 App「指定关注 UP 主」字段按需拉取并搜索关注列表
      optionsHandlers: {
        async followings({ query, credential, http, signal }) {
          if (!credential || !('cookie' in credential)) {
            throw new Error('请先在「所需账号」完成哔哩哔哩登录');
          }
          return fetchBilibiliFollowings(credential.cookie, http, query, signal);
        },
      },

      async run(job) {
        const { config, state, credential, http, signal, log } = job;
        if (!credential || !('cookie' in credential)) {
          throw new AuthExpiredError('bilibili', '尚未配置 B 站登录会话');
        }

        const feedType = config.feedType === 'video' ? 'video' : 'all';
        log('fetch', `拉取 B 站关注动态（${feedType === 'video' ? '仅视频' : '全部'}）`);
        const rawItems = await fetchBilibiliDynamics(feedType, credential.cookie, http, signal);

        const seen = new Set<string>(Array.isArray(state.seenIds) ? state.seenIds : []);
        let candidates = parseDynamics(rawItems, seen, {
          upIds: config.upIds,
          keywords: config.keywords,
        });

        // 模型 1（可选）：按提示词过滤不需要的内容
        const filterAI = job.getAI(config.filterModel);
        if (filterAI && config.filterPrompt?.trim() && candidates.length) {
          log('ai-filter', `使用 ${filterAI.config.name} 按提示词过滤（候选 ${candidates.length} 条）`);
          candidates = await filterDynamicsWithAI(candidates, config.filterPrompt, filterAI, signal);
        }

        const fresh = candidates.slice(0, config.limit || 8);
        const nextSeen = [...seen, ...rawItems.map((i) => i.id_str || '').filter(Boolean)].slice(-1000);

        if (!fresh.length) {
          return {
            message: null,
            state: { seenIds: nextSeen, initialized: true },
            detail: '本轮没有符合条件的新动态',
          };
        }

        // 模型 2（可选）：为筛选后的本期内容生成导读
        const summaryAI = job.getAI(config.summaryModel);
        if (summaryAI) {
          log('ai-summary', `使用 ${summaryAI.config.name} 生成本期导读`);
        }
        const summaryLine = await buildSummaryLine(fresh, summaryAI, signal);

        const html = renderHtmlTemplate(new URL('./template', import.meta.url), {
          taskName: job.taskName,
          aiSummary: summaryAI ? summaryLine : '',
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
