import type { PluginField, WebCookieAuth } from '../../../sdk/index.ts';
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
    required: true,
    default: 'video',
    options: [
      { value: 'video', label: '仅视频投稿', description: '只获取关注 UP 主的新视频' },
      { value: 'all', label: '全部动态', description: '包含视频、图文与文字动态' },
    ],
  },
  {
    key: 'keywords',
    label: '关键词过滤（可选）',
    type: 'text',
    placeholder: '逗号分隔，留空表示不过滤',
    help: '匹配标题、正文或 UP 主名称，任意一个命中即保留。',
  },
  {
    key: 'limit',
    label: '单次最多推送条数',
    type: 'number',
    default: 8,
    min: 1,
    max: 20,
  },
  {
    key: 'aiProvider',
    label: 'AI 导读模型（可选）',
    type: 'aiProvider',
    required: false,
    help: '选择服务器已配置的 AI 模型后，将在推送顶部附带导读；留空则不使用 AI。',
  },
];
