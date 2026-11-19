import { test } from 'node:test';
import assert from 'node:assert/strict';
import { parseHTML } from 'linkedom';
import { messagePreview } from '../src/message-preview.mjs';

const post = (title, image) =>
  '<article class="post"><div class="post-content"><h2>' +
  title +
  '</h2><p>正文</p><figure><img alt="原帖配图" src="data:image/png;base64,' +
  image +
  '"></figure></div></article>';
const html = (...posts) =>
  '<!doctype html><html><head><title>测试</title></head><body><main>' +
  posts.join('') +
  '</main></body></html>';
const msg = { title: '来源任务', short: '本期摘要' };
test('single article reuses original title and embedded cover without invoking AI', async () => {
  let called = false;
  const out = await messagePreview(
    html(post('新版本', 'AAAA')),
    msg,
    '任务',
    () => {
      called = true;
    },
  );
  assert.equal(called, false);
  assert.equal(out.title, '新版本');
  const { document } = parseHTML(out.content);
  assert.equal(
    document.querySelector('meta[property="og:title"]').content,
    out.title,
  );
  assert.equal(
    document
      .getElementById(
        document.querySelector('meta[name="dingdong:cover"]').content,
      )
      .getAttribute('src'),
    'data:image/png;base64,AAAA',
  );
  assert.equal(out.content.split('base64,AAAA').length, 2);
});
test('final multi-post selection includes all sources, validates ID and encodes title', async () => {
  const content = html(post('一', 'AAAA'), post('二', 'BBBB'));
  const result = await messagePreview(content, msg, '任务', async (prompt) => {
    assert.ok(prompt.includes('一') && prompt.includes('二'));
    assert.ok(!prompt.includes('base64'));
    return JSON.stringify({
      title: '本期 “焦点” <图>',
      description: '说明',
      cover: 'image-2',
    });
  });
  const { document } = parseHTML(result.content);
  const cover = document.querySelector('meta[name="dingdong:cover"]').content;
  assert.equal(
    document.getElementById(cover).getAttribute('src'),
    'data:image/png;base64,BBBB',
  );
  assert.equal(
    result.title,
    document.querySelector('meta[property="og:title"]').content,
  );
  const noCover = await messagePreview(
    content,
    msg,
    '任务',
    async () => '{"title":"选题","cover":"unknown"}',
  );
  assert.ok(
    !parseHTML(noCover.content).document.querySelector(
      'meta[name="dingdong:cover"]',
    ),
  );
  const failure = await messagePreview(content, msg, '任务', async () => {
    throw new Error('mock failure');
  });
  assert.equal(failure.title, '一；二');
});

test('translation keeps images, original text and original link in one push', async () => {
  const original = 'A new release is out';
  const content = html(
    '<article class="post"><div class="post-content"><h2><a href="https://example.test/post">' +
      original +
      '</a></h2><p>The release fixes "sync" &amp; backups.</p><figure><img src="data:image/png;base64,AAAA"></figure></div></article>',
    post('这条帖子主体使用中文', 'BBBB'),
  );
  const result = await messagePreview(
    content,
    msg,
    '翻译任务',
    undefined,
    undefined,
    async (prompt) => {
      const inputs = JSON.parse(prompt.split('\n').at(-1));
      assert.ok(
        !inputs.some(
          (text) => text.includes('base64') || text === '这条帖子主体使用中文',
        ),
      );
      return JSON.stringify(
        inputs.map((text) => {
          if (text.includes(original))
            return text.replace(original, '新版已发布');
          return '更新修复了同步和备份。';
        }),
      );
    },
  );
  const { document } = parseHTML(result.content);
  const link = document.querySelector('h2 a');
  assert.equal(link.textContent, '新版已发布');
  assert.equal(link.getAttribute('href'), 'https://example.test/post');
  assert.equal(
    link.firstElementChild.getAttribute('data-dingdong-original'),
    original,
  );
  assert.equal(
    document.querySelector('p span').getAttribute('data-dingdong-original'),
    'The release fixes "sync" & backups.',
  );
  assert.equal(
    document.querySelector('meta[name="dingdong:original-title"]').content,
    original + '；这条帖子主体使用中文',
  );
  assert.equal(result.title, '新版已发布；这条帖子主体使用中文');
  assert.equal(result.content.split('base64,AAAA').length, 2);
});

test('Chinese messages skip the model and an invalid translation preserves a deliverable original', async () => {
  let called = false;
  const chinese = await messagePreview(
    html(post('只有中文标题', 'AAAA')),
    msg,
    '任务',
    undefined,
    undefined,
    () => {
      called = true;
    },
  );
  assert.equal(called, false);
  assert.ok(!chinese.content.includes('dingdong:original-title'));
  const english = html(post('English release notes', 'AAAA'));
  const fallback = await messagePreview(
    english,
    msg,
    '任务',
    undefined,
    undefined,
    () => 'invalid response',
  );
  assert.equal(fallback.title, 'English release notes');
  assert.ok(!fallback.content.includes('dingdong:original-title'));
});
