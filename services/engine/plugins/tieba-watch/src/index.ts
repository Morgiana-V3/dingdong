import { definePlugin, renderHtmlTemplate } from 'dingdong-engine/sdk';
import { fetchTiebaForumPage } from './client.ts';
import { parseTiebaThreads } from './parser.ts';
import { tiebaFields } from './schema.ts';
import type { TiebaConfig, TiebaTemplateData, TiebaThread } from './types.ts';

const templateDir = new URL('./template', import.meta.url);

export default definePlugin({
  name: 'tieba-watch',
  inject: { required: ['source', 'http'] },
  apply(ctx) {
    ctx.source.register({
      id: 'tieba-watch',
      name: '百度贴吧',
      description: '免登录监控指定贴吧最新帖子与精品贴，支持 AI 过滤水贴与导读总结。',
      version: '1.0.0',
      fields: tiebaFields,

      async run(job) {
        const cfg = job.config as unknown as TiebaConfig;
        const forums = (Array.isArray(cfg.forums) ? cfg.forums : [])
          .map((f) => String(f || '').trim().replace(/吧$/, ''))
          .filter(Boolean);
        if (!forums.length) {
          return { message: null, state: job.state, detail: '请至少填写一个贴吧名称' };
        }

        const sort = cfg.sort || 'latest_reply';
        const includePinned = cfg.includePinned === true;
        const limit = Math.max(1, Math.min(30, Number(cfg.limit || 10)));
        const seen = new Set<string>(
          Array.isArray(job.state.seenIds) ? job.state.seenIds.map(String) : [],
        );

        const collected: TiebaThread[] = [];
        for (const forum of forums) {
          job.log('fetch', `拉取 ${forum}吧`);
          const raw = await fetchTiebaForumPage(job.http, forum, {
            sort,
            signal: job.signal,
          });
          const threads = parseTiebaThreads(raw, forum, includePinned);
          for (const t of threads) {
            if (!seen.has(t.id)) collected.push(t);
          }
        }

        const deduped = new Map<string, TiebaThread>();
        for (const item of collected) deduped.set(item.id, item);
        let fresh = [...deduped.values()].slice(0, limit);

        if (!fresh.length) {
          return {
            message: null,
            state: { seenIds: [...seen].slice(-500) },
            detail: '暂无新帖',
          };
        }

        const nextSeen = [...seen, ...fresh.map((i) => i.id)].slice(-500);
        let filteredOutCount = 0;

        // 可选：AI 过滤水贴
        const filterAi = job.getAI(cfg.filterModel);
        const filterPrompt = String(cfg.filterPrompt || '').trim();
        if (filterAi && filterPrompt) {
          job.log('ai-filter', `使用 ${filterAi.config.name} 过滤 ${fresh.length} 条帖子`);
          try {
            const brief = fresh.map((t) => ({
              id: t.id,
              forum: t.forum,
              title: t.title,
              excerpt: t.excerpt.slice(0, 120),
              replyCount: t.replyCount,
            }));
            const result = await filterAi.json<{ keepIds?: string[] }>(
              {
                system:
                  '你是贴吧内容过滤器。严格按用户要求筛选有价值的帖子，只返回 JSON：{"keepIds": ["保留的id"]}',
                prompt: `用户过滤要求：${filterPrompt}\n\n候选帖子：\n${JSON.stringify(brief)}`,
              },
              job.signal,
            );
            if (Array.isArray(result?.keepIds)) {
              const keep = new Set(result.keepIds.map(String));
              const before = fresh.length;
              fresh = fresh.filter((t) => keep.has(t.id));
              filteredOutCount = before - fresh.length;
            }
          } catch (err) {
            job.log('ai-filter-warn', `AI 过滤失败，已保留原列表：${err instanceof Error ? err.message : String(err)}`);
          }
        }

        if (!fresh.length) {
          return {
            message: null,
            state: { seenIds: nextSeen },
            detail: `发现 ${filteredOutCount} 条新帖，已全部被 AI 过滤`,
          };
        }

        // 可选：AI 导读总结
        let aiSummary = '';
        const summaryAi = job.getAI(cfg.summaryModel);
        if (summaryAi) {
          job.log('ai-summary', `使用 ${summaryAi.config.name} 生成导读`);
          try {
            const lines = fresh
              .slice(0, 12)
              .map((t) => `[${t.forum}] ${t.title}${t.excerpt ? `：${t.excerpt.slice(0, 80)}` : ''}（${t.replyCount}回复）`)
              .join('\n');
            aiSummary = (
              await summaryAi.generate(
                {
                  system: '用 2~3 句精炼中文概括这批贴吧新帖的核心看点，不要分点列表，不要客套。',
                  prompt: lines,
                },
                job.signal,
              )
            ).trim();
          } catch (err) {
            job.log('ai-summary-warn', `AI 导读失败：${err instanceof Error ? err.message : String(err)}`);
          }
        }

        const now = new Date();
        const pad = (v: number) => String(v).padStart(2, '0');
        const generatedAt = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}`;

        const data: TiebaTemplateData = {
          taskName: job.taskName,
          generatedAt,
          forums: forums.map((f) => `${f}吧`),
          aiSummary: aiSummary || undefined,
          filteredOutCount: filteredOutCount || undefined,
          items: fresh,
        };

        const html = renderHtmlTemplate(templateDir, { ...data });
        const title = `${job.taskName}（${fresh.length} 条新帖）`;
        const short = aiSummary || fresh.slice(0, 2).map((t) => t.title).join('；');

        return {
          message: {
            title,
            short,
            format: 'html',
            content: html,
          },
          state: { seenIds: nextSeen },
          detail: `推送 ${fresh.length} 条新帖${filteredOutCount ? `（AI 过滤 ${filteredOutCount} 条）` : ''}`,
        };
      },
    });
  },
});
