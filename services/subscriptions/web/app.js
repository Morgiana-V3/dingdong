import { dashboard } from './dashboard.js';
const $ = (id) => document.getElementById(id);
let active = false;
let view = 'tasks';
let polling = false;
let authEpoch = 0;
let accountEpoch = 0;
let remote = false;
let frameURL;
let pointer;
const notify = (text) => {
  $('notice').textContent = text;
};
function clearFrame() {
  if (frameURL) URL.revokeObjectURL(frameURL);
  frameURL = undefined;
  pointer = undefined;
  remote = false;
  $('frame').removeAttribute('src');
  $('browser').hidden = true;
  $('remote-text').value = '';
  $('pair-code').textContent = '';
}
function signedOut() {
  active = false;
  ++authEpoch;
  ++accountEpoch;
  clearFrame();
  admin.reset();
  $('auth').hidden = false;
  $('signout').hidden = $('workspace').hidden = true;
}
async function api(url, data) {
  const epoch = authEpoch;
  const response = await fetch(
    url,
    data === undefined
      ? {}
      : {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(data),
        },
  );
  const result = await response.json();
  if (!response.ok) {
    if (response.status === 401 && epoch === authEpoch) signedOut();
    throw new Error(result.error || '请求失败');
  }
  return result;
}
const admin = dashboard(api, notify);
const platformURL = (path) =>
  path + '?platform=' + encodeURIComponent($('platform').value);
async function action(button, fn) {
  button.disabled = true;
  notify('');
  try {
    await fn();
  } catch (e) {
    notify(e.message);
  } finally {
    button.disabled = false;
  }
}
async function accountStatus() {
  const epoch = accountEpoch;
  const state = await api(platformURL('/api/status'));
  if (epoch !== accountEpoch || !active || view !== 'accounts') return;
  $('status').textContent = state.message || '';
  $('badge').textContent =
    {
      ready: '已验证',
      waiting: '等待登录',
      checking: '验证中',
      error: '需要处理',
      idle: '尚未验证',
    }[state.state] || state.state;
  $('account').textContent = state.account
    ? state.account.name + '　UID ' + state.account.id
    : '';
  $('samples').replaceChildren(
    ...(state.samples || []).map((s) => {
      const li = document.createElement('li');
      li.textContent = [s.author, s.title].filter(Boolean).join('　');
      return li;
    }),
  );
  remote = state.remoteOpen;
  $('browser').hidden = !remote;
  if (remote) await frame(epoch);
}
async function frame(epoch = accountEpoch) {
  const res = await fetch(platformURL('/api/browser/frame'));
  if (res.status === 401) {
    if (epoch === accountEpoch) signedOut();
    return;
  }
  if (!res.ok || epoch !== accountEpoch) return;
  const blob = await res.blob();
  if (epoch !== accountEpoch || !active || view !== 'accounts') return;
  const previous = frameURL;
  frameURL = URL.createObjectURL(blob);
  $('frame').src = frameURL;
  if (previous) URL.revokeObjectURL(previous);
}
async function switchView(tab) {
  view = tab;
  ++accountEpoch;
  clearFrame();
  notify('');
  for (const item of document.querySelectorAll('[data-tab]')) {
    if (item.dataset.tab === tab) item.setAttribute('aria-current', 'page');
    else item.removeAttribute('aria-current');
    $(item.dataset.tab).hidden = item.dataset.tab !== tab;
  }
  await admin.refresh();
  if (tab === 'accounts') await accountStatus();
}
async function enter() {
  // Fetch authenticated state before revealing the workspace.
  await admin.refresh();
  active = true;
  $('auth').hidden = true;
  $('workspace').hidden = $('signout').hidden = false;
  if (view === 'accounts') await accountStatus();
}
for (const tab of document.querySelectorAll('[data-tab]'))
  tab.onclick = () =>
    switchView(tab.dataset.tab).catch((e) => notify(e.message));
$('login-form').onsubmit = (event) => {
  event.preventDefault();
  action(event.submitter, async () => {
    await api('/api/login', { key: $('admin-key').value.trim() });
    $('admin-key').value = '';
    await enter();
  });
};
$('signout').onclick = (event) =>
  action(event.currentTarget, async () => {
    await api('/api/logout', {});
    signedOut();
  });
$('refresh').onclick = (event) =>
  action(event.currentTarget, () => admin.refresh());
$('platform').onchange = async () => {
  ++accountEpoch;
  clearFrame();
  $('status').textContent = '正在读取…';
  $('badge').textContent = '';
  $('account').textContent = '';
  $('samples').replaceChildren();
  $('legacy-pair').hidden = $('platform').value !== 'bilibili';
  admin.draw();
  try {
    await accountStatus();
  } catch (e) {
    notify(e.message);
  }
};
$('pair').onclick = (event) =>
  action(event.currentTarget, async () => {
    const epoch = accountEpoch;
    const result = await api('/api/pair', {});
    if (epoch === accountEpoch) $('pair-code').textContent = result.code;
  });
$('open-browser').onclick = (event) =>
  action(event.currentTarget, async () => {
    await api(platformURL('/api/browser/open'), {});
    await accountStatus();
  });
$('verify').onclick = (event) =>
  action(event.currentTarget, async () => {
    try {
      await api(platformURL('/api/bilibili/verify'), {});
    } finally {
      await accountStatus();
    }
  });
$('logout').onclick = (event) => {
  if (confirm('清除当前平台的服务器登录会话？'))
    action(event.currentTarget, async () => {
      await api(platformURL('/api/bilibili/logout'), {});
      clearFrame();
      await accountStatus();
    });
};
function position(event) {
  const box = $('frame').getBoundingClientRect();
  const width = $('frame').naturalWidth,
    height = $('frame').naturalHeight;
  return {
    x: Math.max(
      0,
      Math.min(width - 1, ((event.clientX - box.left) * width) / box.width),
    ),
    y: Math.max(
      0,
      Math.min(height - 1, ((event.clientY - box.top) * height) / box.height),
    ),
  };
}
$('frame').draggable = false;
$('frame').onpointerdown = (event) => {
  pointer = position(event);
  event.target.setPointerCapture(event.pointerId);
};
$('frame').onpointerup = async (event) => {
  if (!pointer) return;
  const start = pointer;
  pointer = undefined;
  const end = position(event);
  const data =
    Math.hypot(end.x - start.x, end.y - start.y) > 5
      ? { type: 'drag', ...start, toX: end.x, toY: end.y }
      : { type: 'click', ...end };
  try {
    await api(platformURL('/api/browser/input'), data);
    await frame();
  } catch (e) {
    notify(e.message);
  }
};
$('frame').onpointercancel = () => {
  pointer = undefined;
};
$('send-text').onclick = (event) =>
  action(event.currentTarget, async () => {
    const text = $('remote-text').value;
    $('remote-text').value = '';
    await api(platformURL('/api/browser/input'), { type: 'text', text });
    await frame();
  });
for (const b of document.querySelectorAll('[data-key]'))
  b.onclick = () =>
    action(b, async () => {
      await api(platformURL('/api/browser/input'), {
        type: 'key',
        key: b.dataset.key,
      });
      await frame();
    });
setInterval(async () => {
  if (!active || polling || document.hidden || $('editor').open) return;
  polling = true;
  try {
    await admin.refresh();
    if (view === 'accounts') await accountStatus();
  } catch (e) {
    notify(e.message);
  } finally {
    polling = false;
  }
}, 3500);
enter().catch((e) => {
  if (e.message !== '请先登录管理页') notify(e.message);
});
