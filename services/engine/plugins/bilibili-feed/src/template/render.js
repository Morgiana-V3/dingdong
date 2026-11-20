function escapeHtml(text) {
  return String(text ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function formatTime(ts) {
  if (!ts) return '';
  const local = new Date(ts + 8 * 3600000);
  const m = String(local.getUTCMonth() + 1).padStart(2, '0');
  const d = String(local.getUTCDate()).padStart(2, '0');
  const hh = String(local.getUTCHours()).padStart(2, '0');
  const mm = String(local.getUTCMinutes()).padStart(2, '0');
  return `${m}-${d} ${hh}:${mm}`;
}

function render(data) {
  const {
    taskName = 'B 站关注动态',
    aiSummary = '',
    items = [],
  } = data || testData;

  document.title = taskName;

  const banner = document.getElementById('ai-banner');
  const summaryEl = document.getElementById('ai-summary');
  if (banner && summaryEl) {
    if (aiSummary) {
      banner.removeAttribute('hidden');
      summaryEl.textContent = aiSummary;
    } else {
      banner.remove();
    }
  }

  const listEl = document.getElementById('feed-list');
  if (!listEl) return;

  listEl.innerHTML = items
    .map((item) => {
      const time = formatTime(item.publishedAt);
      const bodyHtml = item.body
        ? item.body
            .split(/\n{2,}/)
            .map((p) => `<p>${escapeHtml(p).replace(/\n/g, '<br>')}</p>`)
            .join('')
        : '';
      const figuresHtml = (item.images || [])
        .map(
          (src) =>
            `<figure class="cover"><img src="${escapeHtml(src)}" alt="${escapeHtml(item.title)}"></figure>`,
        )
        .join('');

      return `
      <article class="post">
        <header class="post-header">
          <div class="origin">
            <span class="badge">B站</span>
            <span class="source">${escapeHtml(item.source)}</span>
            ${time ? `<span class="time">${escapeHtml(time)}</span>` : ''}
          </div>
        </header>
        <div class="post-content">
          <h2><a href="${escapeHtml(item.url)}">${escapeHtml(item.title)}</a></h2>
          ${figuresHtml}
          ${bodyHtml ? `<div class="original">${bodyHtml}</div>` : ''}
          <div class="footer-link"><a href="${escapeHtml(item.url)}">打开原动态 / 视频 →</a></div>
        </div>
      </article>`;
    })
    .join('\n');
}

// 浏览器直接打开 template.html 调试样式时使用的示例数据
var testData = {
  taskName: 'B 站关注动态（预览）',
  aiSummary: '本期聚焦开源硬件评测与 Rust 工程实践，包含 2 条高赞视频更新。',
  items: [
    {
      title: '从零用 Rust 写一个轻量级自部署消息中转服务',
      body: '本期视频完整演示如何设计断线重连、SQLite WAL 落盘确认与幂等去重。\n\n源码已开源，欢迎在评论区交流架构细节。',
      source: '示例 UP 主',
      url: 'https://www.bilibili.com/video/BV1xx411c7mD',
      images: [],
      publishedAt: Date.now() - 3600000,
    },
    {
      title: '周末折腾记录：512MB 小服务器如何流畅跑多套容器服务',
      body: '去掉无头浏览器依赖后，内存占用直接从 1.2GB 降到 90MB。',
      source: '极客日记',
      url: 'https://www.bilibili.com/video/BV1yy411c7mE',
      images: [],
      publishedAt: Date.now() - 7200000,
    },
  ],
};

// 浏览器本地直接打开 template.html 预览时自动渲染 testData；服务端渲染由宿主显式调用 render(data)
if (typeof window !== 'undefined' && !window.__DINGDONG_SERVER__) {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => render(testData));
  } else {
    render(testData);
  }
}
