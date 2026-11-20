import type { PluginField, WebCookieAuth } from 'dingdong-engine/sdk';
import { verifyBilibiliSession } from './client.ts';

export const bilibiliAuth: WebCookieAuth = {
  id: 'bilibili',
  name: '哔哩哔哩',
  type: 'web-cookie',
  loginUrl: 'https://passport.bilibili.com/h5-app/passport/login',
  cookieDomains: ['https://api.bilibili.com', 'https://www.bilibili.com'],
  requiredCookies: ['SESSDATA', 'DedeUserID'],
  verify: ({ cookie }, { http }) => verifyBilibiliSession(cookie, http),
};

export const bilibiliFields: PluginField[] = [
  {
    key: 'feedType',
    label: '动态范围',
    type: 'select',
    group: '内容范围',
    required: true,
    default: 'all',
    options: [
      { value: 'all', label: '全部动态（推荐）', description: '包含视频投稿、图文动态与文字动态' },
      { value: 'video', label: '仅视频投稿', description: '只获取关注 UP 主的新视频' },
    ],
  },
  {
    key: 'upIds',
    label: '指定关注 UP 主（可选）',
    type: 'remoteMultiSelect',
    group: '内容范围',
    optionsSource: 'followings',
    required: false,
    placeholder: '留空接收全部关注 UP 主，点击可搜索并多选',
    help: '读取你当前 B 站账号的关注列表，支持顶部搜索并多选，仅推送所选 UP 主的动态。',
  },
  {
    key: 'keywords',
    label: '关键词过滤（可选）',
    type: 'text',
    group: '内容范围',
    placeholder: '逗号分隔，留空表示不过滤',
    help: '匹配标题、正文或 UP 主名称，任意一个命中即保留。',
  },
  {
    key: 'limit',
    label: '单次最多推送条数',
    type: 'number',
    group: '内容范围',
    default: 8,
    min: 1,
    max: 20,
  },
  {
    key: 'filterModel',
    label: '过滤模型',
    type: 'aiProvider',
    group: 'AI 内容过滤',
    groupDescription: '选择模型后按提示词自动剔除广告、抽奖或水动态',
    required: false,
  },
  {
    key: 'filterPrompt',
    label: '过滤要求',
    type: 'textarea',
    group: 'AI 内容过滤',
    when: { field: 'filterModel', nonEmpty: true },
    placeholder: '例如：过滤掉纯抽奖转发、恰饭广告和无实质内容的水动态，保留干货评测与教程',
  },
  {
    key: 'summaryModel',
    label: '导读模型',
    type: 'aiProvider',
    group: 'AI 本期导读',
    groupDescription: '可单独指定另一个模型为本期内容生成顶部导读',
    required: false,
  },
];
