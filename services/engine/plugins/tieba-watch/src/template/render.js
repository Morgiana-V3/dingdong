const testData = {
  taskName: '贴吧数码监控',
  generatedAt: '2026-11-20 18:30',
  forums: ['图拉丁吧', '摄影吧'],
  aiSummary: '本期包含两篇高热度讨论，主要聚焦 mini 主机散热改造方案与定焦镜头实拍对比。',
  items: [
    {
      id: '100001',
      forum: '图拉丁吧',
      title: '百元捡漏小主机改造静音软路由实测，待机仅 6W',
      author: '折腾玩家',
      excerpt: '换了硅脂和静音风扇后连续烤机 12 小时温度稳定在 52 度，附上详细功耗记录。',
      url: 'https://tieba.baidu.com/p/100001',
      replyCount: 42,
      isPinned: false,
      isGood: true,
      publishedAt: '11-20 18:12',
      images: [],
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

function setMeta(name, content, isProp) {
  if (!content || typeof document === 'undefined' || !document.head) return;
  const tag = document.createElement('meta');
  tag.setAttribute(isProp ? 'property' : 'name', name);
  tag.setAttribute('content', String(content));
  document.head.appendChild(tag);
}

function render(data) {
  const root = document.getElementById('app');
  const items = Array.isArray(data?.items) ? data.items : [];
  const titleText = `${data?.taskName || '百度贴吧'}（${items.length} 条新帖）`;
  const descText =
    data?.aiSummary || items.slice(0, 2).map((i) => i.title).join('；');

  setMeta('dingdong:title', titleText, false);
  setMeta('dingdong:description', descText, false);
  setMeta('dingdong:task', data?.taskName || '百度贴吧', false);

  let firstCoverAssigned = false;
  const cards = items
    .map((item) => {
      const imgs = Array.isArray(item.images) ? item.images : [];
      const gridClass = imgs.length === 1 ? 'grid grid-1' : 'grid grid-2';
      const mediaHtml = imgs.length
        ? `<div class="${gridClass}">${imgs
            .map((src) => {
              const idAttr = !firstCoverAssigned
                ? ((firstCoverAssigned = true), ' id="tieba-cover-0"')
                : '';
              return `<img${idAttr} src="${esc(src)}" alt="${esc(item.title)}" />`;
            })
            .join('')}</div>`
        : '';
      return `
        <article class="card">
          <div class="card-meta">
            <span class="pill">${esc(item.forum)}</span>
            ${item.isGood ? '<span class="pill pill-good">精品</span>' : ''}
            ${item.isPinned ? '<span class="pill pill-pin">置顶</span>' : ''}
            <span>${esc(item.author)}</span>
          </div>
          <a class="card-title" href="${esc(item.url)}">${esc(item.title)}</a>
          ${item.excerpt ? `<p class="card-excerpt">${esc(item.excerpt)}</p>` : ''}
          ${mediaHtml}
          <div class="card-foot">
            <span>${esc(item.publishedAt || '')}</span>
            <span>${Number(item.replyCount || 0)} 条回复</span>
          </div>
        </article>
      `;
    })
    .join('');

  if (firstCoverAssigned) {
    setMeta('dingdong:cover', 'tieba-cover-0', false);
  }

  root.innerHTML = `
    <div class="wrap">
      <header class="hero">
        <div class="hero-left">
          <img class="brand-icon" aria-hidden="true" src="./assets/tieba-badge.svg" alt="" />
          <div>
            <h1 class="hero-title">${esc(data?.taskName || '百度贴吧')}</h1>
            <p class="hero-sub">${esc((data?.forums || []).join(' · '))} · ${esc(data?.generatedAt || '')}</p>
          </div>
        </div>
      </header>
      ${
        data?.aiSummary
          ? `<section class="ai-box">
              <div class="ai-head">
                <img class="ai-icon" aria-hidden="true" src="./assets/ai-spark.svg" alt="" />
                <span>AI 导读</span>
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
