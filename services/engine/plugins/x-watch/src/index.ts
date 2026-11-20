import { definePlugin, renderHtmlTemplate } from 'dingdong-engine/sdk';
import { fetchXProfileStatuses, fetchXSearchStatuses } from './client.ts';
import { parseXStatuses } from './parser.ts';
import { xFields } from './schema.ts';
import type { XConfig, XPost, XTemplateData } from './types.ts';

const templateDir = new URL('./template', import.meta.url);

export default definePlugin({
  name: 'x-watch',
  inject: { required: ['source', 'http'] },
  apply(ctx) {
    ctx.source.register({
      id: 'x-watch',
      name: 'X（推特）',
      description: '免登录监控公开 X 账号推文或关键词最新动态，支持 AI 过滤与中文导读总结。',
      version: '1.0.0',
      fields: xFields,

      async run(job) {
        const cfg = job.config as unknown as XConfig;
        const handles = (Array.isArray(cfg.handles) ? cfg.handles : [])
          .map((h) => String(h || '').trim().replace(/^@/, ''))
          .filter(Boolean);
        const query = String(cfg.query || '').trim();
        if (!handles.length && !query) {
          return { message: null, state: job.state, detail: '请至少填写一个公开账号或关键词' };
        }

        const includeReposts = cfg.includeReposts !== false;
        const limit = Math.max(1, Math.min(30, Number(cfg.limit || 10)));
        const seen = new Set<string>(
          Array.isArray(job.state.seenIds) ? job.state.seenIds.map(String) : [],
        );

        const collected: XPost[] = [];
        for (const handle of handles) {
          job.log('fetch', `拉取 @${handle}`);
          const rows = await fetchXProfileStatuses(job.http, handle, job.signal);
          for (const post of parseXStatuses(rows, includeReposts)) {
            if (!seen.has(post.id)) collected.push(post);
          }
        }
        if (query) {
          job.log('search', `搜索关键词：${query}`);
          const rows = await fetchXSearchStatuses(job.http, query, job.signal);
          for (const post of parseXStatuses(rows, includeReposts)) {
            if (!seen.has(post.id)) collected.push(post);
          }
        }

        const deduped = new Map<string, XPost>();
        for (const p of collected) deduped.set(p.id, p);
        let fresh = [...deduped.values()]
          .sort((a, b) => (b.id.length - a.id.length) || b.id.localeCompare(a.id))
          .slice(0, limit);

        if (!fresh.length) {
          return {
            message: null,
            state: { seenIds: [...seen].slice(-500) },
            detail: '暂无新推文',
          };
        }

        const nextSeen = [...seen, ...fresh.map((p) => p.id)].slice(-500);
        let filteredOutCount = 0;

        // 可选：AI 过滤
        const filterAi = job.getAI(cfg.filterModel);
        const filterPrompt = String(cfg.filterPrompt || '').trim();
        if (filterAi && filterPrompt) {
          job.log('ai-filter', `使用 ${filterAi.config.name} 过滤 ${fresh.length} 条推文`);
          try {
            const brief = fresh.map((p) => ({
              id: p.id,
              author: `@${p.authorHandle}`,
              text: p.text.slice(0, 180),
              likes: p.likes,
            }));
            const result = await filterAi.json<{ keepIds?: string[] }>(
              {
                system:
                  '你是 X（推特）信息流过滤器。严格按用户要求筛选有价值的推文，只返回 JSON：{"keepIds": ["保留的id"]}',
                prompt: `用户过滤要求：${filterPrompt}\n\n候选推文：\n${JSON.stringify(brief)}`,
              },
              job.signal,
            );
            if (Array.isArray(result?.keepIds)) {
              const keep = new Set(result.keepIds.map(String));
              const before = fresh.length;
              fresh = fresh.filter((p) => keep.has(p.id));
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
            detail: `发现 ${filteredOutCount} 条新推文，已全部被 AI 过滤`,
          };
        }

        // 可选：AI 中文导读
        let aiSummary = '';
        const summaryAi = job.getAI(cfg.summaryModel);
        if (summaryAi) {
          job.log('ai-summary', `使用 ${summaryAi.config.name} 生成中文导读`);
          try {
            const lines = fresh
              .slice(0, 12)
              .map((p) => `@${p.authorHandle}: ${p.text.slice(0, 160)}`)
              .join('\n');
            aiSummary = (
              await summaryAi.generate(
                {
                  system: '用 2~3 句简洁自然的中文概括这批推文的核心重点，不要分点列表，不要客套。',
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

        const subtitleParts = [
          ...handles.slice(0, 4).map((h) => `@${h}`),
          ...(handles.length > 4 ? [`等 ${handles.length} 个账号`] : []),
          ...(query ? [`搜索：${query}`] : []),
        ];

        const data: XTemplateData = {
          taskName: job.taskName,
          generatedAt,
          subtitle: subtitleParts.join(' · '),
          aiSummary: aiSummary || undefined,
          filteredOutCount: filteredOutCount || undefined,
          items: fresh,
        };

        const html = renderHtmlTemplate(templateDir, { ...data });
        const title = `${job.taskName}（${fresh.length} 条新推文）`;
        const short =
          aiSummary ||
          fresh
            .slice(0, 2)
            .map((p) => `@${p.authorHandle}: ${p.text.slice(0, 40)}`)
            .join('；');

        return {
          message: {
            title,
            short,
            format: 'html',
            content: html,
          },
          state: { seenIds: nextSeen },
          detail: `推送 ${fresh.length} 条推文${filteredOutCount ? `（AI 过滤 ${filteredOutCount} 条）` : ''}`,
        };
      },
    });
  },
});
