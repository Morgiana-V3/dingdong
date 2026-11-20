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

function renderRichBody(item) {
  const segments = Array.isArray(item.bodySegments) && item.bodySegments.length
    ? item.bodySegments
    : item.bodyText
      ? [{ type: 'text', text: item.bodyText }]
      : [];
  if (!segments.length) return '';

  const html = segments
    .map((seg) => {
      if (seg.type === 'emoji' && seg.url) {
        return `<img class="bili-emoji" src="${escapeHtml(seg.url)}" alt="${escapeHtml(seg.text)}">`;
      }
      return escapeHtml(seg.text).replace(/\n/g, '<br>');
    })
    .join('');

  return `<div class="original"><p>${html}</p></div>`;
}

function renderGallery(images, title) {
  const list = Array.isArray(images) ? images.filter(Boolean) : [];
  if (!list.length) return '';
  const cols = list.length === 1 ? 'cols-1' : list.length === 2 || list.length === 4 ? 'cols-2' : 'cols-3';
  const figures = list
    .map((src) => `<figure><img src="${escapeHtml(src)}" alt="${escapeHtml(title)}"></figure>`)
    .join('');
  return `<div class="gallery ${cols}">${figures}</div>`;
}

function render(data) {
  const {
    taskName = 'B 站关注动态',
    aiSummary = '',
    items = [],
  } = data || testData;

  document.title = taskName;
  const titleEl = document.getElementById('issue-title');
  const subEl = document.getElementById('issue-sub');
  if (titleEl) titleEl.textContent = taskName;
  if (subEl) subEl.textContent = `共 ${items.length} 条更新 · 点击标题直达原动态`;

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
      const kindIcon = item.isVideo ? './assets/video-badge.svg' : './assets/bili-tv.svg';
      const durationBadge = item.duration ? `<span class="duration">${escapeHtml(item.duration)}</span>` : '';
      const bodyHtml = renderRichBody(item);
      const galleryHtml = renderGallery(item.images, item.title);

      return `
      <article class="post">
        <header class="post-header">
          <div class="origin">
            <img class="kind-icon" src="${kindIcon}" alt="${item.isVideo ? '视频' : '动态'}">
            <span class="source">${escapeHtml(item.source)}</span>
            ${durationBadge}
            ${time ? `<span class="time">${escapeHtml(time)}</span>` : ''}
          </div>
        </header>
        <div class="post-content">
          <h2><a href="${escapeHtml(item.url)}">${escapeHtml(item.title)}</a></h2>
          ${bodyHtml}
          ${galleryHtml}
        </div>
      </article>`;
    })
    .join('\n');
}

// 浏览器直接打开 template.html 调试样式时使用的示例数据
var testData = {
  taskName: 'B 站关注动态（预览）',
  aiSummary: '本期包含 1 条硬核工程视频和 1 条多图图文动态，均支持点击标题直接跳转。',
  items: [
    {
      title: '从零设计自部署消息收件箱：如何把容器从 1.7GB 瘦身到 460MB',
      bodySegments: [
        { type: 'text', text: '去掉无头浏览器依赖后内存直接降了 90%，顺便分享一下插件化架构踩坑记录 ' },
        { type: 'text', text: '[doge]' },
      ],
      source: '示例 UP 主',
      url: 'https://www.bilibili.com/video/BV1xx411c7mD',
      isVideo: true,
      duration: '12:34',
      images: [],
      publishedAt: Date.now() - 3600000,
    },
    {
      title: '周末桌搭与开源硬件小记',
      bodySegments: [
        { type: 'text', text: '终于把树莓派和小屏幕装好了，推送卡片深色模式效果意外舒服！' },
      ],
      source: '极客日记',
      url: 'https://t.bilibili.com/123456789',
      isVideo: false,
      images: [],
      publishedAt: Date.now() - 7200000,
    },
  ],
};

if (typeof window !== 'undefined' && !window.__DINGDONG_SERVER__) {
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => render(testData));
  } else {
    render(testData);
  }
}
