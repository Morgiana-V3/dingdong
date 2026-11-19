import { EventEmitter } from 'node:events';

// A narrow adapter for Studio's platform sources, not an Electron runtime.
export function browserAdapter(login) {
  const session = new EventEmitter();
  session.setProxy = async () => {};
  session.setPermissionRequestHandler = session.setPermissionCheckHandler = () => {};
  session.clearCache = async () => {};
  session.clearStorageData = async () => { await login.init(); await login.context.clearCookies(); };
  session.cookies = {
    get: async ({ url } = {}) => { await login.init(); return login.context.cookies(url); },
    flushStore: async () => {},
  };
  session.fetch = async (url, options = {}) => {
    options.signal?.throwIfAborted();
    await login.init();
    const response = await login.context.request.fetch(url, {
      method: options.method || 'GET', headers: options.headers, data: options.body,
      maxRedirects: options.redirect === 'error' ? 0 : 5, timeout: 20000,
    });
    options.signal?.throwIfAborted();
    return new Response(await response.body(), { status: response.status(), headers: response.headers() });
  };
  class BrowserWindow extends EventEmitter {
    constructor() {
      super();
      this.destroyed = false;
      this.webContents = new EventEmitter();
      const contents = this.webContents;
      contents.getUserAgent = () => 'Mozilla/5.0';
      contents.setUserAgent = contents.setWindowOpenHandler = () => {};
      contents.isDestroyed = () => this.destroyed;
      contents.getURL = () => this.page?.url() || '';
      contents.executeJavaScript = async script => { await this.ready(); return this.page.evaluate(script); };
      const debuggerAPI = new EventEmitter();
      let cdp;
      debuggerAPI.attach = () => {
        cdp = this.ready().then(() => login.context.newCDPSession(this.page)).then(client => {
          for (const event of ['Network.requestWillBeSent', 'Network.responseReceived', 'Network.loadingFailed', 'Network.loadingFinished']) {
            client.on(event, params => debuggerAPI.emit('message', {}, event, params));
          }
          return client;
        });
      };
      debuggerAPI.sendCommand = async (method, params) => (await cdp).send(method, params);
      debuggerAPI.isAttached = () => !!cdp;
      debuggerAPI.detach = () => { void cdp?.then(client => client.detach()).catch(() => {}); cdp = undefined; };
      contents.debugger = debuggerAPI;
    }
    async ready() {
      if (this.destroyed) throw new Error('页面已关闭');
      if (!this.loading) this.loading = (async () => {
        await login.init();
        this.page = await login.context.newPage();
        if (this.destroyed) { await this.page.close(); throw new Error('页面已关闭'); }
      })();
      await this.loading;
    }
    async loadURL(url) { await this.ready(); await this.page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30000 }); }
    isDestroyed() { return this.destroyed; }
    show() {}
    focus() {}
    destroy() { if (this.destroyed) return; this.destroyed = true; void this.page?.close().catch(() => {}); this.emit('closed'); }
  }
  return { session, BrowserWindow };
}
