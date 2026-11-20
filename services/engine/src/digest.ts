import { DIGEST_ID } from './domain.ts';

export const name = 'builtin-digest';

export function apply(ctx) {
  ctx.source.register({
    id: DIGEST_ID,
    name: '统一推送汇总',
    description: '将 1–8 个已有订阅源合并为一条消息定时投递',
    version: '1.0.0',
    builtin: true,
    capabilities: ['ai.optional'],
    fields: [
      {
        key: 'sourceTaskIds',
        label: '内容源',
        type: 'tasks',
        required: true,
        minItems: 1,
        maxItems: 8,
        help: '选择 1–8 个已有任务，启用汇总后由汇总统一调度。',
      },
    ],
  });
}
