import fs from 'node:fs';
import { chromium } from 'playwright-core';
import { BilibiliLogin } from './bilibili.mjs';

const platforms = {
  x: { name: 'X', domain: 'x.com', url: 'https://x.com/i/flow/login', cookies: ['auth_token', 'ct0', 'twid'] },
  xiaohongshu: { name: '小红书', domain: 'xiaohongshu.com', url: 'https://www.xiaohongshu.com/explore', cookies: ['web_session', 'a1', 'webId', 'webBuild', 'websectiga', 'sec_poison_id', 'gid', 'acw_tc', 'loadts'] },
};
export class PlatformLogin extends BilibiliLogin {
  constructor(vault, id) { super(vault); this.id = id; this.platform = platforms[id]; }
  async init() {
    if (this.context) return;
    const windows = 'C:/Program Files/Google/Chrome/Application/chrome.exe';
    const executablePath = process.env.CHROMIUM_EXECUTABLE || (fs.existsSync(windows) ? windows : '/usr/bin/chromium');
    // X can use its own proxy; domestic sources keep a direct connection.
    const proxy = this.id === 'x' ? process.env.X_PROXY || process.env.BROWSER_PROXY : undefined;
    this.browser = await chromium.launch({ executablePath, headless: true, proxy: proxy ? { server: proxy } : undefined });
    this.context = await this.newContext(this.vault.load());
  }
  async newContext(storageState) {
    const context = await this.browser.newContext({
      viewport: { width: 1000, height: 760 }, storageState,
      // Match the normal Chromium browser identity used by desktop Studio.
      // X rejects the default HeadlessChrome identity before showing its login UI.
      ...(this.id === 'x' ? { userAgent: `Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${this.browser.version()} Safari/537.36` } : {}),
    });
    context.on('page', page => {
      page.on('dialog', dialog => void dialog.dismiss());
      page.on('download', download => void download.cancel());
      page.on('popup', popup => void popup.close());
    });
    await context.route('**/*', route => {
      const request = route.request();
      if (request.isNavigationRequest() && request.frame() === request.frame().page().mainFrame()) {
        const url = new URL(request.url());
        if (url.protocol !== 'https:' || !(url.hostname === this.platform.domain || url.hostname.endsWith('.' + this.platform.domain))) return route.abort();
      }
      return route.continue();
    });
    return context;
  }
  async login() {
    await this.init();
    if (!this.page || this.page.isClosed()) this.page = await this.context.newPage();
    await this.page.goto(this.platform.url, { waitUntil: 'domcontentloaded', timeout: 30000 });
    this.status = { state: 'waiting', message: '请在官方页面登录，再验证账号与内容读取' };
  }
  async importPhone(header) {
    if (typeof header !== 'string' || header.length > 32000 || /[\r\n]/.test(header)) throw new Error('会话格式无效');
    const cookies = header.split(';').flatMap(part => {
      const split = part.indexOf('=');
      const name = part.slice(0, split).trim();
      const value = part.slice(split + 1).trim();
      return split > 0 && value && this.platform.cookies.includes(name) ? [{ name, value, domain: '.' + this.platform.domain, path: '/', secure: true, httpOnly: true, sameSite: 'Lax' }] : [];
    });
    const required = this.id === 'x' ? ['auth_token', 'ct0', 'twid'] : ['web_session'];
    if (required.some(name => !cookies.some(cookie => cookie.name === name))) throw new Error('尚未获取完整登录会话，请先完成官方登录');
    await this.init();
    const previous = this.context;
    const previousPage = this.page;
    const status = this.status;
    // Verify in a fresh profile. A failed replacement must preserve cookies AND
    // local storage of the working account, including its open Web login page.
    this.context = await this.newContext({ cookies, origins: [] });
    this.page = undefined;
    let result;
    try {
      result = await this.verify('phone');
    } catch (error) {
      await this.context.close().catch(() => {});
      this.context = previous;
      this.page = previousPage;
      this.status = status;
      throw error;
    }
    await previous.close().catch(() => {});
    return result;
  }
  async verify(source = 'web') {
    await this.init();
    try {
      const result = await this.check();
      this.vault.save(await this.context.storageState());
      this.status = { state: 'ready', source, ...result, checkedAt: new Date().toISOString(), message: '服务器已验证账号，并成功读取内容' };
      return this.status;
    } catch (error) {
      this.status = { state: 'error', message: /^(X |小红书|请先|尚未|无法更新 X)/.test(error.message) ? error.message : '账号验证失败，请检查服务器网络或在网页登录中完成验证' };
      throw new Error(this.status.message);
    }
  }
}
