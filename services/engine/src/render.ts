import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import MarkdownIt from 'markdown-it';
import { parseHTML } from 'linkedom';
import { loadImage } from './images.ts';

const assetsDir = fileURLToPath(new URL('./assets/', import.meta.url));
const markdown = new MarkdownIt({ html: false, breaks: true, linkify: true });
const contentCss = fs.readFileSync(path.join(assetsDir, 'push-content.css'), 'utf8');
const markdownCss = fs.readFileSync(path.join(assetsDir, 'push-markdown.css'), 'utf8');

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export function safeLink(address) {
  try {
    const url = new URL(String(address || ''));
    if (['http:', 'https:', 'mailto:'].includes(url.protocol) && !url.username && !url.password) {
      return url.href;
    }
  } catch {
    // Ignore invalid links
  }
  return undefined;
}

function formatTime(value) {
  if (!value) return '';
  const date = typeof value === 'number' ? new Date(value) : new Date(String(value));
  if (Number.isNaN(date.getTime())) return String(value);
  const local = new Date(date.getTime() + 8 * 3600000);
  const y = local.getUTCFullYear();
  const m = String(local.getUTCMonth() + 1).padStart(2, '0');
  const d = String(local.getUTCDate()).padStart(2, '0');
  const hh = String(local.getUTCHours()).padStart(2, '0');
  const mm = String(local.getUTCMinutes()).padStart(2, '0');
  return `${y}-${m}-${d} ${hh}:${mm}`;
}

export function renderArticleCard(article) {
  const source = article.source ? `<span class="source">${escapeHtml(article.source)}</span>` : '';
  const time = article.publishedAt ? `<span class="time">${escapeHtml(formatTime(article.publishedAt))}</span>` : '';
  const link = safeLink(article.url);
  const titleHtml = link
    ? `<h2><a href="${escapeHtml(link)}">${escapeHtml(article.title)}</a></h2>`
    : `<h2>${escapeHtml(article.title)}</h2>`;
  const bodyRaw = typeof article.body === 'string' ? article.body.trim() : '';
  const bodyHtml = bodyRaw ? `<div class="original">${markdown.render(bodyRaw)}</div>` : '';
  const images = Array.isArray(article.images) ? article.images.slice(0, 6) : [];
  const figures = images
    .map((item) => {
      const src = typeof item === 'string' ? item : item?.url;
      const alt = typeof item === 'string' ? article.title : item?.caption || article.title;
      if (!src) return '';
      return `<figure><img src="${escapeHtml(src)}" alt="${escapeHtml(alt)}"></figure>`;
    })
    .filter(Boolean)
    .join('');
  return `<article class="post"><header class="post-header"><div class="origin">${source}${time}</div></header><div class="post-content">${titleHtml}${bodyHtml}${figures}</div></article>`;
}

export function combineMessages(title, entries) {
  if (!entries.length) return null;
  const sections = entries.map(({ name, message }) => ({ name, message }));
  const total = entries.reduce((sum, { message }) => sum + (message.articles?.length || 1), 0);
  return {
    title,
    short: `${entries.length} 个来源，共 ${total} 条更新`,
    sections,
  };
}

function buildRawHtml(message) {
  if (Array.isArray(message.sections)) {
    const cards = message.sections
      .flatMap((section) => {
        const item = section.message;
        if (Array.isArray(item.articles) && item.articles.length) {
          return item.articles.map((article) => ({
            html: renderArticleCard({ ...article, source: article.source || section.name }),
            ts: Number(new Date(article.publishedAt || 0)) || 0,
          }));
        }
        const raw = item.content ?? item.body ?? '';
        const inner =
          item.format === 'html'
            ? raw
            : item.format === 'text'
              ? `<pre>${escapeHtml(raw)}</pre>`
              : markdown.render(raw);
        return [
          {
            html: `<article class="post digest-note"><header class="post-header"><div class="origin"><span class="source">${escapeHtml(section.name)}</span></div></header><div class="post-content"><h2>${escapeHtml(item.title)}</h2>${inner}</div></article>`,
            ts: 0,
          },
        ];
      })
      .sort((a, b) => b.ts - a.ts)
      .map((entry) => entry.html)
      .join('\n');
    return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escapeHtml(message.title)}</title><style>${contentCss}</style></head><body><main>${cards}</main></body></html>`;
  }

  if (Array.isArray(message.articles) && message.articles.length) {
    const cards = message.articles.map(renderArticleCard).join('\n');
    return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escapeHtml(message.title)}</title><style>${contentCss}</style></head><body><main>${cards}</main></body></html>`;
  }

  const raw = message.content ?? message.body ?? '';
  if (message.format === 'html') {
    return /<html[\s>]/i.test(raw)
      ? raw
      : `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escapeHtml(message.title)}</title><style>${markdownCss}</style></head><body><main>${raw}</main></body></html>`;
  }
  if (message.format === 'text') {
    return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escapeHtml(message.title)}</title><style>${markdownCss}</style></head><body><main><h1>${escapeHtml(message.title)}</h1><pre>${escapeHtml(raw)}</pre></main></body></html>`;
  }
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>${escapeHtml(message.title)}</title><style>${markdownCss}</style></head><body><main><h1>${escapeHtml(message.title)}</h1>${markdown.render(raw)}</main></body></html>`;
}

export async function renderDocument(
  message: any,
  imageLoader: ((address: string, budget: number, signal?: AbortSignal) => Promise<string>) | undefined = loadImage,
  signal?: AbortSignal,
): Promise<{ content: string }> {
  const html = buildRawHtml(message);
  const { document } = parseHTML(html);
  for (const el of document.querySelectorAll('script, iframe, object, embed, base, link[rel=stylesheet]')) {
    el.remove();
  }
  const imgs = [...document.querySelectorAll('img')];
  const maxBytes = 900_000;
  let currentBytes = Buffer.byteLength(document.toString(), 'utf8');
  const remoteImgs = imgs.filter((img) => {
    const src = img.getAttribute('src') || '';
    return /^https?:\/\//i.test(src);
  });
  for (let i = 0; i < remoteImgs.length; i++) {
    const img = remoteImgs[i];
    const remaining = remoteImgs.length - i;
    const budget = Math.floor((maxBytes - currentBytes) / remaining);
    if (budget < 12_000 || !imageLoader) {
      img.closest('figure')?.remove() ?? img.remove();
      continue;
    }
    try {
      const dataUri = await imageLoader(img.getAttribute('src'), Math.min(budget, 220_000), signal);
      img.setAttribute('src', dataUri);
      currentBytes += Buffer.byteLength(dataUri, 'utf8');
    } catch {
      signal?.throwIfAborted();
      img.closest('figure')?.remove() ?? img.remove();
    }
  }
  const content = document.toString();
  if (Buffer.byteLength(content, 'utf8') > 1_000_000) {
    throw new Error('渲染后的 HTML 超过 1 MB 上限');
  }
  return { content };
}
