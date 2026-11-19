import { loadImage } from './subscription-images.mjs';
import { Vault } from './vault.mjs';

export async function accountProfile(id, name, image) {
  const account = { id: String(id), name: String(name || id).slice(0, 100) };
  if (typeof image !== 'string') return account;
  try {
    account.avatar = await loadImage(image.replace(/^http:/, 'https:'), 12000, AbortSignal.timeout(8000));
  } catch { /* Account verification remains valid when its avatar is unavailable. */ }
  return account;
}

export async function browserProfile(login, platform, id, fallbackName) {
  const vault = login.vault?.directory ? new Vault(login.vault.directory, platform + '-profile') : undefined;
  let previous;
  try {
    const stored = vault?.load();
    if (stored?.id === String(id)) previous = stored;
  } catch { /* An unavailable profile cache must not invalidate a working session. */ }
  let page;
  try {
    page = await login.context.newPage();
    await page.setViewportSize?.({ width: 1440, height: 900 });
    await page.goto(platform === 'x' ? 'https://x.com/home' : 'https://www.xiaohongshu.com/explore', { waitUntil: 'domcontentloaded', timeout: 15000 }).catch(() => {});
    if (platform === 'x') await page.waitForSelector?.('[data-testid="SideNav_AccountSwitcher_Button"]', { timeout: 10000 }).catch(() => {});
    const profile = await page.evaluate(async ({ platform, id }) => {
      function read() {
        const state = window.__INITIAL_STATE__ || {};
        if (platform === 'x') {
          const user = state.entities?.users?.entities?.[id];
          const button = document.querySelector('[data-testid="SideNav_AccountSwitcher_Button"]');
          return { name: user?.name || button?.innerText?.split('\n').find(text => text.trim() && !text.trim().startsWith('@'))?.trim(), image: user?.profile_image_url_https || button?.querySelector('img')?.src };
        }
        const raw = state.user?.userInfo;
        const user = raw?.value ?? raw?._value ?? raw;
        const accountId = String(user?.userId || user?.user_id || '');
        return accountId === id ? { name: user?.nickname, image: user?.images || user?.image || user?.avatar } : {};
      }
      for (let attempt = 0; attempt < 20; attempt++) {
        const profile = read();
        if (profile.name && profile.image) return profile;
        await new Promise(resolve => setTimeout(resolve, 200));
      }
      return read();
    }, { platform, id });
    const account = await accountProfile(id, profile.name || previous?.name || fallbackName, profile.image);
    if (!account.avatar && previous?.avatar) account.avatar = previous.avatar;
    if (profile.name || account.avatar) vault?.save(account);
    return account;
  } catch {
    return previous || accountProfile(id, fallbackName);
  } finally {
    await page?.close().catch(() => {});
  }
}
