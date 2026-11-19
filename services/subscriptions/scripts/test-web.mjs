import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import fs from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { chromium } from 'playwright-core';

const directory = await fs.mkdtemp(
  path.join(os.tmpdir(), 'dingdong-dashboard-'),
);
const child = spawn(process.execPath, ['src/server.mjs'], {
  env: {
    ...process.env,
    DATA_DIR: directory,
    PORT: '0',
    DINGDONG_SEND_TOKEN: '',
    DINGDONG_READ_TOKEN: 'test-web-only',
  },
  stdio: ['ignore', 'pipe', 'inherit'],
});
const exited = once(child, 'exit');
let browser;
try {
  const base = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('管理台启动超时')), 15000);
    child.stdout.on('data', (data) => {
      const match = String(data).match(/http:\/\/127\.0\.0\.1:\d+/);
      if (match) {
        clearTimeout(timer);
        resolve(match[0]);
      }
    });
    child.once('error', reject);
  });
  browser = await chromium.launch({
    executablePath:
      process.env.CHROMIUM_EXECUTABLE ||
      (process.platform === 'win32'
        ? 'C:/Program Files/Google/Chrome/Application/chrome.exe'
        : '/usr/bin/chromium'),
    headless: true,
  });
  const page = await browser.newPage({
    viewport: { width: 1100, height: 780 },
  });
  const errors = [];
  page.on('pageerror', (e) => errors.push(e.message));
  await page.goto(base);
  await page
    .getByLabel('管理密钥')
    .fill(
      (await fs.readFile(path.join(directory, 'admin.key'), 'utf8')).trim(),
    );
  await page.getByRole('button', { name: '登录', exact: true }).click();
  const btn = (name) => page.getByRole('button', { name, exact: true });
  const dialog = page.getByRole('dialog');
  async function save() {
    await dialog.getByRole('button', { name: '保存', exact: true }).click();
    await dialog.waitFor({ state: 'hidden', timeout: 5000 });
  }
  await btn('＋ 添加任务').click();
  await dialog.getByLabel('任务名称').fill('浏览器测试任务');
  await dialog.getByLabel('启用任务').uncheck();
  await save();
  await btn('编辑').click();
  await dialog.getByLabel('任务名称').fill('浏览器编辑后的任务');
  await dialog.getByLabel('执行时间').selectOption('daily');
  await dialog.getByLabel('北京时间').fill('09:00、18:00');
  await save();
  const phone = await (
    await fetch(base + '/v1/subscriptions', {
      headers: { Authorization: 'Bearer test-web-only' },
    })
  ).json();
  assert.equal(phone.tasks[0].name, '浏览器编辑后的任务');
  assert.deepEqual(phone.tasks[0].schedule.times, ['09:00', '18:00']);
  await btn('启用').click();
  await btn('暂停').click();
  await btn('记录').click();
  await dialog.getByText('尚无执行记录').waitFor();
  await btn('关闭').click();
  await btn('AI 服务').click();
  await btn('＋ 添加服务').click();
  await dialog.getByLabel('厂商').selectOption('https://api.deepseek.com');
  await dialog.getByLabel('API Key').fill('fictional-test-key');
  await dialog.getByLabel('模型（可搜索或手动填写）').fill('fixture-model');
  await save();
  await page.getByRole('heading', { name: 'DeepSeek' }).waitFor();
  await btn('订阅任务').click();
  await btn('编辑').click();
  await dialog
    .getByLabel('AI 配置', { exact: true })
    .selectOption({ label: 'DeepSeek' });
  assert.equal(await dialog.getByLabel('发送前翻译外文').count(), 0);
  await save();
  const translated = await (
    await fetch(base + '/v1/subscriptions', {
      headers: { Authorization: 'Bearer test-web-only' },
    })
  ).json();
  assert.equal(translated.tasks[0].translate, undefined);
  assert.equal(translated.tasks[0].providerId, translated.providers[0].id);
  await btn('编辑').click();
  await dialog.getByLabel('AI 配置', { exact: true }).selectOption('');
  await save();
  await btn('AI 服务').click();
  await btn('删除').click();
  await dialog.getByRole('button', { name: '删除' }).click();
  await dialog.waitFor({ state: 'hidden' });
  await btn('平台账号').click();
  await page.getByLabel('选择平台').selectOption('x');
  await page.getByText('当前没有已开启的任务需要此账号。').waitFor();
  await page.setViewportSize({ width: 360, height: 720 });
  await btn('订阅任务').click();
  assert.ok(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= window.innerWidth,
    ),
  );
  await btn('删除').click();
  await dialog.getByRole('button', { name: '删除' }).click();
  await page.getByText('尚无订阅任务。', { exact: false }).waitFor();
  await btn('退出管理台').click();
  await btn('登录').waitFor();
  assert.equal(
    (await page.request.get(base + '/api/subscriptions')).status(),
    401,
  );
  assert.deepEqual(errors, []);
  console.log(
    '通过：管理台登录、任务增改启停删、手机读取同一配置、执行记录、AI 配置、账号切换、窄屏和退出。',
  );
} finally {
  try {
    await browser?.close();
  } finally {
    child.kill();
    await exited;
    await fs.rm(directory, { recursive: true, force: true });
  }
}
