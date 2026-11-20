const testData = {
  taskName: 'X 科技前沿',
  generatedAt: '2026-11-20 18:35',
  subtitle: '@GoogleDeepMind · @OpenAI',
  aiSummary: '本期推文重点介绍了新一代推理模型的长上下文基准测试表现，以及开源工具链的最新更新。',
  items: [
    {
      id: '1859000000000000001',
      authorName: 'Google DeepMind',
      authorHandle: 'GoogleDeepMind',
      text: 'Sharing our latest benchmarks on long-context reasoning and developer tooling.',
      url: 'https://x.com/GoogleDeepMind/status/1859000000000000001',
      publishedAt: '11-20 18:10',
      images: [],
      hasVideo: false,
      likes: 1240,
      reposts: 260,
      replies: 88,
    },
  ],
};

function esc(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function setMeta(name, content) {
  if (!content || typeof document === 'undefined' || !document.head) return;
  const tag = document.createElement('meta');
  tag.setAttribute('name', name);
  tag.setAttribute('content', String(content));
  document.head.appendChild(tag);
}

function render(data) {
  const root = document.getElementById('app');
  const items = Array.isArray(data?.items) ? data.items : [];
  const titleText = `${data?.taskName || 'X（推特）'}（${items.length} 条新推文）`;
  const descText =
    data?.aiSummary ||
    items
      .slice(0, 2)
      .map((p) => `@${p.authorHandle}: ${String(p.text || '').slice(0, 42)}`)
      .join('；');

  setMeta('dingdong:title', titleText);
  setMeta('dingdong:description', descText);
  setMeta('dingdong:task', data?.taskName || 'X（推特）');

  let firstCoverAssigned = false;
  const cards = items
    .map((item) => {
      const imgs = Array.isArray(item.images) ? item.images : [];
      const gridClass = imgs.length === 1 ? 'grid grid-1' : 'grid grid-2';
      const mediaHtml = imgs.length
        ? `<div class="${gridClass}">${imgs
            .map((src) => {
              const idAttr = !firstCoverAssigned
                ? ((firstCoverAssigned = true), ' id="x-cover-0"')
                : '';
              return `<img${idAttr} src="${esc(src)}" alt="" />`;
            })
            .join('')}</div>`
        : '';
      const quoteHtml = item.quote
        ? `<div class="quote">
            <div class="quote-author">${esc(item.quote.authorName)} @${esc(item.quote.authorHandle)}</div>
            <p class="quote-text">${esc(item.quote.text)}</p>
          </div>`
        : '';
      return `
        <article class="card">
          ${item.repostedBy ? `<div class="repost-tag">↻ ${esc(item.repostedBy)} 转发</div>` : ''}
          <div class="author-row">
            <a class="author-link" href="${esc(item.url)}">
              ${esc(item.authorName)}<span class="handle">@${esc(item.authorHandle)}</span>
            </a>
            <span class="time">${esc(item.publishedAt || '')}</span>
          </div>
          ${item.text ? `<p class="post-text">${esc(item.text)}</p>` : ''}
          ${quoteHtml}
          ${mediaHtml}
          <div class="card-foot">
            <span>回复 ${Number(item.replies || 0)}</span>
            <span>转发 ${Number(item.reposts || 0)}</span>
            <span>喜欢 ${Number(item.likes || 0)}</span>
            ${item.hasVideo ? '<span>含视频</span>' : ''}
          </div>
        </article>
      `;
    })
    .join('');

  if (firstCoverAssigned) {
    setMeta('dingdong:cover', 'x-cover-0');
  }

  root.innerHTML = `
    <div class="wrap">
      <header class="hero">
        <img class="brand-icon" aria-hidden="true" src="./assets/x-badge.svg" alt="" />
        <div>
          <h1 class="hero-title">${esc(data?.taskName || 'X（推特）')}</h1>
          <p class="hero-sub">${esc(data?.subtitle || '')}${data?.generatedAt ? ` · ${esc(data.generatedAt)}` : ''}</p>
        </div>
      </header>
      ${
        data?.aiSummary
          ? `<section class="ai-box">
              <div class="ai-head">
                <img class="ai-icon" aria-hidden="true" src="./assets/ai-spark.svg" alt="" />
                <span>AI 中文导读</span>
              </div>
              <p class="ai-text">${esc(data.aiSummary)}</p>
            </section>`
          : ''
      }
      ${cards}
    </div>
  `;
}

if (typeof window !== 'undefined' && typeof document !== 'undefined') {
  render(window.__DINGDONG_DATA__ || testData);
}
