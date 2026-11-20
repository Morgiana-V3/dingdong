const loginView = document.getElementById('login-view');
const mainView = document.getElementById('main-view');
const loginError = document.getElementById('login-error');
const bannerError = document.getElementById('banner-error');
let snapshot = null;

async function api(path, options = {}) {
  const res = await fetch(path, {
    headers: { 'Content-Type': 'application/json', ...(options.headers || {}) },
    ...options,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `HTTP ${res.status}`);
  return data;
}

function el(tag, attrs = {}, text = '') {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') node.className = v;
    else node.setAttribute(k, v);
  }
  if (text) node.textContent = text;
  return node;
}

async function runCommand(payload) {
  bannerError.textContent = '';
  try {
    snapshot = await api('/api/commands', {
      method: 'POST',
      body: JSON.stringify({ revision: snapshot.revision, ...payload }),
    });
    render();
  } catch (err) {
    bannerError.textContent = err.message;
  }
}

function render() {
  if (!snapshot) return;
  document.getElementById('plugin-count').textContent = `${snapshot.plugins.length} 个插件`;

  const taskList = document.getElementById('task-list');
  taskList.replaceChildren();
  if (!snapshot.tasks.length) {
    taskList.append(el('p', { class: 'muted' }, '暂无任务。可在手机 App 的「订阅管理」中创建任务。'));
  }
  for (const task of snapshot.tasks) {
    const row = el('div', { class: 'item' });
    const info = el('div');
    info.append(el('strong', {}, `${task.name} `), el('span', { class: 'badge' }, task.state));
    info.append(el('p', { class: 'muted' }, `插件：${task.pluginId}${task.lastDetail ? ' · ' + task.lastDetail : ''}`));
    if (task.lastError) info.append(el('p', { class: 'error' }, task.lastError));
    const actions = el('div', { class: 'actions' });
    const runBtn = el('button', {}, task.state === 'running' ? '停止' : '运行');
    runBtn.onclick = () => runCommand({ action: task.state === 'running' ? 'cancel' : 'run', id: task.id });
    const toggleBtn = el('button', {}, task.enabled ? '暂停' : '启用');
    toggleBtn.onclick = () => runCommand({ action: 'toggle', id: task.id, enabled: !task.enabled });
    actions.append(runBtn, toggleBtn);
    row.append(info, actions);
    taskList.append(row);
  }

  const pluginList = document.getElementById('plugin-list');
  pluginList.replaceChildren();
  for (const plugin of snapshot.plugins) {
    const row = el('div', { class: 'item' });
    const info = el('div');
    info.append(el('strong', {}, `${plugin.name} (${plugin.id})`));
    info.append(el('p', { class: 'muted' }, plugin.description || '自定义插件'));
    row.append(info);
    pluginList.append(row);
  }

  const credList = document.getElementById('credential-list');
  credList.replaceChildren();
  if (!snapshot.accounts.length) {
    credList.append(el('p', { class: 'muted' }, '当前已启用的任务不需要额外账号或凭据。'));
  }
  for (const acc of snapshot.accounts) {
    const row = el('div', { class: 'item' });
    const info = el('div');
    info.append(el('strong', {}, `${acc.name} `), el('span', { class: 'badge' }, acc.state));
    info.append(el('p', { class: 'muted' }, `${acc.type === 'web-cookie' ? '网页 Cookie 登录（可在手机 App 完成）' : 'Token 凭据'} · ${acc.message || ''}`));
    row.append(info);
    credList.append(row);
  }

  const providerList = document.getElementById('provider-list');
  providerList.replaceChildren();
  if (!snapshot.providers.length) {
    providerList.append(el('p', { class: 'muted' }, '尚未配置 AI 服务商，可在手机 App 中添加。'));
  }
  for (const p of snapshot.providers) {
    const row = el('div', { class: 'item' });
    const info = el('div');
    info.append(el('strong', {}, p.name));
    info.append(el('p', { class: 'muted' }, `${p.model} · ${p.baseUrl}`));
    row.append(info);
    providerList.append(row);
  }
}

async function refresh() {
  try {
    snapshot = await api('/api/snapshot');
    loginView.hidden = true;
    mainView.hidden = false;
    render();
  } catch {
    loginView.hidden = false;
    mainView.hidden = true;
  }
}

document.getElementById('login-form').onsubmit = async (e) => {
  e.preventDefault();
  loginError.textContent = '';
  try {
    await api('/api/login', { method: 'POST', body: JSON.stringify({ key: document.getElementById('admin-key').value }) });
    await refresh();
  } catch (err) {
    loginError.textContent = err.message;
  }
};
document.getElementById('refresh-btn').onclick = refresh;
refresh();
