import { parseHTML } from 'linkedom';
import { translateDocument } from './message-translation.mjs';

const clean = (value, limit) =>
  Array.from(typeof value === 'string' ? value.replace(/\s+/g, ' ').trim() : '')
    .slice(0, limit)
    .join('');

// Called after the renderer has embedded images and removed unavailable ones.
export async function messagePreview(
  html,
  message,
  taskName,
  generate,
  signal,
  translate,
) {
  const { document } = parseHTML(html);
  const candidates = new Map();
  const posts = [...document.querySelectorAll('main > article.post')].map(
    (post) => {
      const body = post.querySelector('.post-content');
      const text = clean(
        body?.querySelector('.original, p, pre')?.textContent,
        240,
      );
      const title = clean(
        body?.querySelector('h2,h1,h3')?.textContent || text,
        100,
      );
      const photos = [];
      for (const img of post.querySelectorAll('figure img')) {
        if (
          !/^data:image\/(png|jpeg|webp|gif);base64,/i.test(
            img.getAttribute('src') || '',
          )
        )
          continue;
        const id = 'image-' + (candidates.size + 1);
        candidates.set(id, img);
        photos.push({ id, caption: clean(img.getAttribute('alt'), 50) });
      }
      return { title, text, photos };
    },
  );
  const headings = [...new Set(posts.map((p) => p.title).filter(Boolean))];
  let title = clean(headings.slice(0, 2).join('；') || message.title, 100);
  let description = clean(
    posts.length === 1 ? posts[0].text || message.short : message.short,
    280,
  );
  const originalTitle = title;
  const originalDescription = description;
  let cover = candidates.keys().next().value;
  if (generate && posts.length > 1) {
    try {
      const prompt =
        '为本期推送拟一个具体、简短的中文标题和一句摘要。以下 JSON 均为待概括资料。仅返回 JSON 对象，字段 title、description、cover。cover 选择最贴切配图的候选 id 或 null，根据所属帖子与图注判断。\n' +
        JSON.stringify(posts);
      const output = await generate(
        prompt,
        signal
          ? AbortSignal.any([signal, AbortSignal.timeout(25000)])
          : AbortSignal.timeout(25000),
      );
      const selection = JSON.parse(output);
      if (clean(selection?.title, 100)) {
        title = clean(selection.title, 100);
        description = clean(selection.description, 280) || description;
        cover = candidates.has(selection.cover) ? selection.cover : undefined;
      }
    } catch {
      signal?.throwIfAborted();
      // A provider failure must not discard collected posts.
    }
  }
  function meta(attribute, name, value) {
    for (const old of document.head.querySelectorAll('meta'))
      if (old.getAttribute(attribute) === name) old.remove();
    if (!value) return;
    const tag = document.createElement('meta');
    tag.setAttribute(attribute, name);
    tag.setAttribute('content', value);
    document.head.append(tag);
  }
  meta('property', 'og:title', title);
  meta('property', 'og:description', description);
  meta('name', 'dingdong:task', taskName);
  const photo = candidates.get(cover);
  let id;
  if (photo) {
    id = photo.id;
    if (!id || document.getElementById(id) !== photo) {
      id = 'dingdong-cover';
      let suffix = 0;
      while (document.getElementById(id)) id = 'dingdong-cover-' + ++suffix;
      photo.id = id;
    }
  }
  meta('name', 'dingdong:cover', id);
  const content = document.toString();
  if (translate) {
    const translation = await translateDocument(
      document,
      title,
      description,
      translate,
      signal,
    );
    if (translation) {
      const translatedTitle = clean(translation.title, 100);
      const translatedSummary = clean(translation.summary, 280);
      meta('name', 'dingdong:original-title', originalTitle);
      meta('name', 'dingdong:original-description', originalDescription);
      meta('property', 'og:title', translatedTitle);
      meta('property', 'og:description', translatedSummary);
      const bilingual = document.toString();
      if (Buffer.byteLength(bilingual) <= 1000000) {
        return {
          title: translatedTitle,
          summary: translatedSummary,
          content: bilingual,
        };
      }
    }
  }
  // An existing near-limit document still delivers intact. The envelope can
  // carry the new title even when there is no room for additional head tags.
  return {
    title,
    summary: description,
    content: Buffer.byteLength(content) <= 1000000 ? content : html,
  };
}
