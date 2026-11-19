const $ = (id) => document.getElementById(id);
const states = {
  active: '已开启',
  paused: '已暂停',
  running: '运行中',
  grouped: '统一推送',
  needs_login: '等待登录',
  needs_ai: '等待 AI 配置',
  needs_config: '等待配置',
  unavailable: '插件不可用',
  error: '运行失败',
};
const attention = [
  'needs_login',
  'needs_ai',
  'needs_config',
  'unavailable',
  'error',
];
const presets = [
  ['OpenAI', 'https://api.openai.com/v1'],
  ['DeepSeek', 'https://api.deepseek.com'],
  ['Kimi', 'https://api.moonshot.cn/v1'],
  ['通义千问', 'https://dashscope.aliyuncs.com/compatible-mode/v1'],
  [
    '通义千问（国际）',
    'https://dashscope-intl.aliyuncs.com/compatible-mode/v1',
  ],
  ['OpenRouter', 'https://openrouter.ai/api/v1'],
  ['自定义', ''],
];
function element(tag, text, cls) {
  const node = document.createElement(tag);
  if (text != null) node.textContent = text;
  if (cls) node.className = cls;
  return node;
}
function input(type, value = '') {
  const node = element('input');
  node.type = type;
  if (type === 'checkbox') node.checked = Boolean(value);
  else node.value = value;
  return node;
}
function select(options, value) {
  const node = element('select');
  for (const [id, label] of options) node.add(new Option(label, id));
  if (value != null) node.value = value;
  return node;
}
function field(label, control) {
  const wrapper = element('label', label);
  if (control.type === 'checkbox') {
    wrapper.className = 'check';
    wrapper.prepend(control);
  } else wrapper.append(control);
  return wrapper;
}
function button(label, action, cls = 'secondary') {
  const node = element('button', label, cls);
  node.type = 'button';
  node.onclick = action;
  return node;
}
function group() {
  return element('div', null, 'form-group');
}
function cadence(schedule) {
  if (schedule?.type === 'daily')
    return (
      '每天 ' + (schedule.times || [schedule.time]).join('、') + '（北京时间）'
    );
  if (schedule?.type === 'interval') return '每 ' + schedule.minutes + ' 分钟';
  return '手动执行';
}

export function dashboard(api, notify) {
  let state;
  let epoch = 0;
  let saving = false;
  let submit;
  const dialog = $('editor');
  const fields = $('fields');
  function busy() {
    return state.tasks.some((t) => t.state === 'running');
  }
  function open(title, render, saveLabel = '保存') {
    if (dialog.open) return;
    $('dialog-title').textContent = title;
    fields.replaceChildren();
    $('form-error').textContent = '';
    $('save').textContent = saveLabel;
    submit = render();
    $('save').hidden = !submit;
    dialog.showModal();
  }
  $('close-dialog').onclick = () => {
    if (!saving) dialog.close();
  };
  dialog.oncancel = (event) => {
    if (saving) event.preventDefault();
  };
  dialog.onclose = () => {
    fields.replaceChildren();
    submit = undefined;
  };
  $('editor-form').onsubmit = async (event) => {
    event.preventDefault();
    if (saving || !submit) return;
    saving = true;
    $('save').disabled = true;
    $('form-error').textContent = '';
    try {
      await submit();
      dialog.close();
    } catch (error) {
      $('form-error').textContent = error.message;
    } finally {
      saving = false;
      $('save').disabled = false;
    }
  };
  async function command(payload, revision) {
    ++epoch;
    const result = await api('/api/subscriptions/commands', {
      ...payload,
      revision,
    });
    if (payload.action !== 'models') {
      ++epoch;
      state = result;
      draw();
    }
    return result;
  }
  async function refresh() {
    const ticket = ++epoch;
    const result = await api('/api/subscriptions');
    if (ticket !== epoch || JSON.stringify(state) === JSON.stringify(result))
      return;
    state = result;
    draw();
  }
  async function operate(payload) {
    try {
      await command(payload, state.revision);
    } catch (error) {
      notify(error.message);
    }
  }
  function confirmRemove(name, payload) {
    const revision = state.revision;
    open(
      '确认删除',
      () => {
        fields.append(element('p', '将删除「' + name + '」。'));
        return () => command(payload, revision);
      },
      '删除',
    );
  }
  function pluginFields(plugin, config, container) {
    const getters = [];
    for (const f of plugin.fields) {
      const value = config[f.key] ?? f.default ?? '';
      if (f.type === 'account') {
        getters.push(() => [f.key, value]);
        continue;
      }
      if (f.type === 'tasks') {
        const choices = group();
        const ids = String(value).split(',');
        const inputs = [];
        for (const task of state.tasks.filter(
          (t) => t.pluginId !== 'minipush-digest',
        )) {
          const check = input('checkbox', ids.includes(task.id));
          inputs.push([task.id, check]);
          choices.append(field(task.name, check));
        }
        container.append(element('h3', f.label), choices);
        if (!inputs.length)
          choices.append(
            element('p', '先保存一个来源任务，再选择它加入统一推送。'),
          );
        getters.push(() => [
          f.key,
          inputs
            .filter(([, check]) => check.checked)
            .map(([id]) => id)
            .join(','),
        ]);
        continue;
      }
      if (f.type === 'forums') {
        const rows = group();
        function add(item = {}) {
          const row = element('div', null, 'forum');
          row.append(
            field('吧名', input('text', item.name || '')),
            field('单独过滤规则', input('text', item.filter || '')),
            button('移除贴吧', () => row.remove(), 'quiet'),
          );
          rows.append(row);
        }
        for (const item of Array.isArray(value) ? value : [{}]) add(item);
        container.append(
          element('h3', f.label),
          rows,
          button('添加贴吧', () => {
            if (rows.children.length < 5) add();
          }),
        );
        getters.push(() => [
          f.key,
          Array.from(rows.children, (row) => {
            const [name, filter] = row.querySelectorAll('input');
            return { name: name.value, filter: filter.value };
          }),
        ]);
        continue;
      }
      const control =
        f.type === 'textarea'
          ? element('textarea')
          : input(
              f.type === 'boolean'
                ? 'checkbox'
                : f.type === 'number'
                  ? 'number'
                  : 'text',
              value,
            );
      if (f.type === 'textarea') control.value = value;
      if (f.required && control.type !== 'checkbox') control.required = true;
      if (f.min != null) control.min = f.min;
      if (f.max != null) control.max = f.max;
      if (f.maxLength) control.maxLength = f.maxLength;
      container.append(field(f.label, control));
      getters.push(() => [
        f.key,
        f.type === 'boolean'
          ? control.checked
          : f.type === 'number'
            ? Number(control.value)
            : control.value,
      ]);
    }
    return () => Object.fromEntries(getters.map((get) => get()));
  }
  function editTask(task) {
    const revision = state.revision;
    open(task ? '编辑任务' : '添加任务', () => {
      const plugins = state.plugins.filter(
        (p) => !p.legacy || p.id === task?.pluginId,
      );
      const plugin = select(
        plugins.map((p) => [p.id, p.name]),
        task?.pluginId,
      );
      plugin.disabled = !!task;
      const name = input('text', task?.name || '');
      name.required = true;
      name.maxLength = 80;
      const extra = group();
      let readConfig;
      function updateFields() {
        extra.replaceChildren();
        const definition = plugins.find((p) => p.id === plugin.value);
        extra.append(element('p', definition.description, 'hint'));
        readConfig = pluginFields(definition, task?.config || {}, extra);
      }
      plugin.onchange = updateFields;
      updateFields();
      const schedule = select(
        [
          ['manual', '手动'],
          ['interval', '固定间隔'],
          ['daily', '每天定点'],
        ],
        task?.schedule?.type || 'manual',
      );
      const minutes = input('number', task?.schedule?.minutes || 60);
      minutes.min = 1;
      minutes.max = 10080;
      const times = input(
        'text',
        (task?.schedule?.times || [task?.schedule?.time || '09:00']).join('、'),
      );
      const intervalField = field('间隔（分钟）', minutes);
      const dailyField = field('北京时间（多个时间用顿号分隔）', times);
      function scheduleFields() {
        intervalField.hidden = minutes.disabled = schedule.value !== 'interval';
        dailyField.hidden = times.disabled = schedule.value !== 'daily';
      }
      schedule.onchange = scheduleFields;
      scheduleFields();
      const provider = select(
        [['', '未分配'], ...state.providers.map((p) => [p.id, p.name])],
        task?.providerId || '',
      );
      provider.setAttribute('aria-label', 'AI 配置');
      const aiPreview = input('checkbox', task?.aiPreview ?? false);
      const enabled = input('checkbox', task?.enabled ?? true);
      const changed = input('checkbox', task?.onlyChanged ?? true);
      fields.append(
        field('订阅插件', plugin),
        field('任务名称', name),
        extra,
        field('执行时间', schedule),
        intervalField,
        dailyField,
        field('AI 配置', provider),
        field('AI 为多帖推送拟题和选图', aiPreview),
        element('p', '开启后，每期多帖推送将额外调用一次所选模型。', 'hint'),
        field('仅在内容变化时推送', changed),
        field('启用任务', enabled),
      );
      return () =>
        command(
          {
            action: 'save',
            id: task?.id,
            pluginId: plugin.value,
            name: name.value,
            config: readConfig(),
            enabled: enabled.checked,
            onlyChanged: changed.checked,
            providerId: provider.value,
            aiPreview: aiPreview.checked,
            schedule:
              schedule.value === 'daily'
                ? {
                    type: 'daily',
                    times: times.value.trim().split(/[,，、\s]+/),
                  }
                : schedule.value === 'interval'
                  ? { type: 'interval', minutes: Number(minutes.value) }
                  : { type: 'manual' },
          },
          revision,
        );
    });
  }
  function editProvider(provider) {
    const revision = state.revision;
    open(provider ? '编辑 AI 服务' : '添加 AI 服务', () => {
      const vendor = select(
        presets.map(([label, url]) => [url, label]),
        provider
          ? presets.find(([, u]) => u === provider.baseUrl)?.[1] || ''
          : presets[0][1],
      );
      const name = input('text', provider?.name || 'OpenAI');
      const base = input('url', provider?.baseUrl || vendor.value);
      const key = input('password');
      key.autocomplete = 'off';
      const model = input('text', provider?.model || '');
      model.setAttribute('list', 'model-options');
      const choices = element('datalist');
      choices.id = 'model-options';
      const limit = input('number', provider?.maxOutputTokens || 8000);
      limit.min = 100;
      limit.max = 100000;
      for (const control of [name, base, model, limit]) control.required = true;
      const values = () => ({
        id: provider?.id,
        name: name.value.trim(),
        baseUrl: base.value.trim(),
        key: key.value.trim(),
        model: model.value.trim(),
        maxOutputTokens: Number(limit.value),
      });
      vendor.onchange = () => {
        base.value = vendor.value;
        name.value = vendor.selectedOptions[0].text;
        key.value = '';
        model.value = '';
        choices.replaceChildren();
      };
      const load = button('读取可用模型', async () => {
        const request = values();
        load.disabled = true;
        try {
          const { models } = await command(
            { action: 'models', provider: request },
            revision,
          );
          if (
            !load.isConnected ||
            base.value.trim() !== request.baseUrl ||
            key.value.trim() !== request.key
          )
            return;
          choices.replaceChildren(...models.map((m) => new Option(m, m)));
          $('form-error').textContent = models.length
            ? ''
            : '服务未返回模型，请手动填写。';
          model.focus();
        } catch (e) {
          if (load.isConnected) $('form-error').textContent = e.message;
        } finally {
          load.disabled = false;
        }
      });
      fields.append(
        field('厂商', vendor),
        field('配置名称', name),
        field('API 地址', base),
        field(provider?.hasKey ? 'API Key（留空沿用）' : 'API Key', key),
        load,
        field('模型（可搜索或手动填写）', model),
        choices,
        field('最大输出 Token', limit),
      );
      return () =>
        command({ action: 'saveProvider', provider: values() }, revision);
    });
  }
  function entry(title, subtitle) {
    const row = element('article', null, 'entry');
    const main = element('div', null, 'entry-main');
    main.append(element('h3', title), element('p', subtitle));
    const actions = element('div', null, 'actions');
    row.append(main, actions);
    return { row, main, actions };
  }
  function draw() {
    if (!state) return;
    const list = $('task-list');
    const filter = $('filter').value;
    const query = $('search').value.trim().toLowerCase();
    const locked = busy();
    list.replaceChildren();
    for (const t of state.tasks) {
      const plugin = state.plugins.find((p) => p.id === t.pluginId);
      if (!(t.name + ' ' + (plugin?.name || '')).toLowerCase().includes(query))
        continue;
      if (
        (filter === 'on' && !t.enabled) ||
        (filter === 'off' && t.enabled) ||
        (filter === 'attention' && !attention.includes(t.state))
      )
        continue;
      const { row, main, actions } = entry(
        t.name,
        (plugin?.name || '插件未安装') + '　' + cadence(t.schedule),
      );
      main.append(
        element(
          'span',
          states[t.state] || t.state,
          'pill' + (attention.includes(t.state) ? ' attention' : ''),
        ),
      );
      const run = button(t.state === 'running' ? '停止' : '立即运行', () =>
        operate({ action: t.state === 'running' ? 'cancel' : 'run', id: t.id }),
      );
      run.disabled =
        t.state !== 'running' && (locked || t.state === 'grouped' || !plugin);
      const toggle = button(t.enabled ? '暂停' : '启用', () =>
        operate({ action: 'toggle', id: t.id, enabled: !t.enabled }),
      );
      const edit = button('编辑', () => editTask(t));
      const del = button(
        '删除',
        () => confirmRemove(t.name, { action: 'delete', id: t.id }),
        'quiet',
      );
      toggle.disabled = del.disabled = locked;
      edit.disabled = locked || !plugin;
      actions.append(
        run,
        toggle,
        edit,
        button(
          '记录',
          () =>
            open('执行记录', () => {
              fields.append(
                element('h3', t.name),
                element(
                  'p',
                  t.lastRunAt
                    ? new Date(t.lastRunAt).toLocaleString()
                    : '尚无执行记录',
                ),
                element('p', t.lastError || t.lastDetail || ''),
              );
              for (const event of t.trace || [])
                fields.append(element('p', event.detail));
            }),
          'quiet',
        ),
        del,
      );
      list.append(row);
    }
    const shown = list.children.length;
    if (!shown)
      list.append(
        element(
          'p',
          state.tasks.length
            ? '没有匹配的任务。'
            : '尚无订阅任务。点击「添加任务」选择服务器上的插件。',
          'empty',
        ),
      );
    $('task-count').textContent =
      shown + ' / ' + state.tasks.length + ' 个任务';
    $('new-task').disabled = locked || !state.plugins.some((p) => !p.legacy);
    const providers = $('provider-list');
    providers.replaceChildren();
    for (const p of state.providers) {
      const { row, actions } = entry(p.name, p.model + '　' + p.baseUrl);
      actions.append(
        button('编辑', () => editProvider(p)),
        button(
          '删除',
          () => confirmRemove(p.name, { action: 'deleteProvider', id: p.id }),
          'quiet',
        ),
      );
      for (const b of actions.children) b.disabled = locked;
      providers.append(row);
    }
    $('new-provider').disabled = locked;
    if (!state.providers.length)
      providers.append(
        element('p', '尚无 AI 服务。添加后可在任务中选择。', 'empty'),
      );
    const account = state.accounts.find((a) => a.id === $('platform').value);
    $('dependencies').textContent = account
      ? '关联任务　' + account.tasks.map((t) => t.name).join('、')
      : '当前没有已开启的任务需要此账号。';
  }
  $('search').oninput = $('filter').onchange = draw;
  $('new-task').onclick = () => editTask();
  $('new-provider').onclick = () => editProvider();
  $('new-task').disabled = $('new-provider').disabled = true;
  return {
    refresh,
    draw,
    reset() {
      ++epoch;
      state = undefined;
      if (dialog.open) dialog.close();
    },
  };
}
