import fs from 'node:fs';
import { chromium } from 'playwright-core';
import { bilibiliCookies } from './vault.mjs';
import { accountProfile } from './account-profile.mjs';

export class BilibiliLogin {
  constructor(vault) { this.vault = vault; this.status = { state: 'idle', message: '尚未验证账号' }; }
  async init() {
    if (this.context) return;
    const windows = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
    const executablePath = process.env.CHROMIUM_EXECUTABLE || (fs.existsSync(windows) ? windows : '/usr/bin/chromium');
    this.browser = await chromium.launch({ executablePath, headless: true, proxy: process.env.BROWSER_PROXY ? { server: process.env.BROWSER_PROXY } : undefined });
    this.context = await this.browser.newContext({ viewport: { width: 1000, height: 760 }, storageState: this.vault.load() });
    this.context.on('page', page => {
      page.on('dialog', dialog => void dialog.dismiss());
      page.on('download', download => void download.cancel());
    });
    await this.context.route('**/*', route => {
      const request = route.request();
      if (request.isNavigationRequest() && request.frame() === request.frame().page().mainFrame()) {
        const url = new URL(request.url());
        if (url.protocol !== 'https:' || !(url.hostname === 'bilibili.com' || url.hostname.endsWith('.bilibili.com'))) return route.abort();
      }
      return route.continue();
    });
  }
  async login() {
    await this.init();
    if (!this.page || this.page.isClosed()) this.page = await this.context.newPage();
    await this.page.goto('https://passport.bilibili.com/login', { waitUntil: 'domcontentloaded', timeout: 30000 });
    this.status = { state: 'waiting', message: '请在下方官方登录页面完成登录，然后点击验证' };
  }
  async importPhone(header) {
    const cookies = bilibiliCookies(header);
    await this.init();
    const previous = await this.context.storageState();
    const previousStatus = this.status;
    await this.context.clearCookies();
    await this.context.addCookies(cookies);
    try { return await this.verify('phone'); }
    catch (error) {
      await this.context.clearCookies();
      await this.context.addCookies(previous.cookies);
      this.status = previousStatus;
      throw error;
    }
  }
  async request(path, params = {}) {
    const url = new URL(path, 'https://api.bilibili.com');
    url.search = new URLSearchParams(params).toString();
    const response = await this.context.request.get(url.href, { headers: { Referer: 'https://www.bilibili.com/' }, timeout: 20000, maxRedirects: 0 });
    if (!response.ok()) throw new Error(`B 站请求失败（HTTP ${response.status()}）`);
    const body = await response.json();
    if (body.code !== 0) throw new Error(`B 站暂未允许读取（${body.code}），请检查登录状态`);
    return body.data;
  }
  async verify(source = 'web') {
    await this.init();
    try {
      const account = await this.request('/x/web-interface/nav');
      if (!account.isLogin || !account.mid) throw new Error('尚未登录，请先在官方页面完成登录');
      const feed = await this.request('/x/polymer/web-dynamic/v1/feed/all', { type: 'video' });
      const samples = (feed.items || []).slice(0, 5).map(item => ({ title: item.modules?.module_dynamic?.major?.archive?.title || '动态', author: item.modules?.module_author?.name || '' }));
      this.vault.save(await this.context.storageState());
      this.status = { state: 'ready', source, account: await accountProfile(account.mid, account.uname, account.face), checkedAt: new Date().toISOString(), itemCount: (feed.items || []).length, samples, message: '服务器已确认账号，并成功读取视频动态' };
      return this.status;
    } catch (error) {
      this.status = { state: 'error', message: error.message };
      throw error;
    }
  }
  async collect(config) {
    await this.init();
    let feed;
    try {
      feed = await this.request('/x/polymer/web-dynamic/v1/feed/all', { type: 'video' });
    } catch (error) {
      if (/\(-101\)|（-101）/.test(error.message)) this.status = { state: 'error', message: 'B 站登录已失效，请重新登录' };
      throw error;
    }
    const keyword = config.keyword.trim().toLocaleLowerCase();
    return (feed.items || []).flatMap(item => {
      const archive = item.modules?.module_dynamic?.major?.archive;
      const author = item.modules?.module_author;
      if (!archive || !/^BV[A-Za-z0-9]+$/.test(archive.bvid || '')) return [];
      const title = String(archive.title || '').slice(0, 300);
      const name = String(author?.name || '').slice(0, 100);
      if (keyword && !`${title} ${name}`.toLocaleLowerCase().includes(keyword)) return [];
      const cover = String(archive.cover || '').replace(/^http:/, 'https:');
      const duration = archive.duration_text;
      const publishedAt = Number(author?.pub_ts) * 1000;
      return [{
        id: archive.bvid,
        title,
        author: name,
        description: String(archive.desc || '').slice(0, 1200),
        url: `https://www.bilibili.com/video/${archive.bvid}`,
        cover: cover.length <= 3000 ? cover : undefined,
        duration: typeof duration === 'string' && /^[0-9:]{1,12}$/.test(duration) ? duration : undefined,
        publishedAt: Number.isSafeInteger(publishedAt) && publishedAt > 0 ? publishedAt : undefined,
      }];
    }).slice(0, config.limit);
  }
  async screenshot() {
    if (!this.page || this.page.isClosed()) throw new Error('请先打开网页登录');
    return this.page.screenshot({ type: 'jpeg', quality: 75 });
  }
  async input(action) {
    if (!this.page || this.page.isClosed()) throw new Error('请先打开网页登录');
    if (action.type === 'click' && Number.isFinite(action.x) && Number.isFinite(action.y) && action.x >= 0 && action.x < 1000 && action.y >= 0 && action.y < 760) await this.page.mouse.click(action.x, action.y);
    else if (action.type === 'drag' && [action.x, action.y, action.toX, action.toY].every(Number.isFinite) && action.x >= 0 && action.x < 1000 && action.toX >= 0 && action.toX < 1000 && action.y >= 0 && action.y < 760 && action.toY >= 0 && action.toY < 760) {
      await this.page.mouse.move(action.x, action.y);
      await this.page.mouse.down();
      try { await this.page.mouse.move(action.toX, action.toY, { steps: 20 }); }
      finally { await this.page.mouse.up(); }
    }
    else if (action.type === 'text' && typeof action.text === 'string' && action.text.length <= 1000) await this.page.keyboard.insertText(action.text);
    else if (action.type === 'key' && ['Tab', 'Enter', 'Backspace', 'ControlOrMeta+A'].includes(action.key)) await this.page.keyboard.press(action.key);
    else if (action.type === 'wheel' && Number.isFinite(action.delta)) await this.page.mouse.wheel(0, Math.max(-600, Math.min(600, action.delta)));
    else throw new Error('不支持的操作');
  }
  async logout() {
    await this.context?.close(); await this.browser?.close();
    this.context = undefined; this.page = undefined; this.vault.clear();
    this.status = { state: 'idle', message: '服务器登录会话已清除' };
  }
  async stop() { await this.browser?.close(); }
}

export function bilibiliPlugin(ctx, options) {
  const login = new BilibiliLogin(options.vault);
  options.register(login);
  if (options.registry) {
    const unregister = options.registry.register({
      id: 'bilibili-following', legacy: true, digestSource: true, name: 'B 站关注视频（旧版任务）', version: '1.0.0',
      description: '检查已关注 UP 主的新视频，有更新时推送到叮咚。',
      accountId: 'bilibili', accountName: '哔哩哔哩',
      fields: [
        { key: 'limit', label: '每次最多推送', type: 'number', min: 1, max: 20, default: 5, suffix: '条视频' },
        { key: 'keyword', label: '标题或 UP 主关键词', type: 'text', maxLength: 100, default: '', help: '留空接收所有关注视频' },
      ],
      collect: config => login.collect(config),
    });
    ctx.on('dispose', unregister);
  }
  ctx.on('dispose', () => login.stop());
}
