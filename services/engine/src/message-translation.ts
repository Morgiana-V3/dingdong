const originalAttribute = 'data-dingdong-original';

function languageWeight(text) {
  const letters =
    text.replace(/https?:\/\/\S+/g, '').match(/\p{Letter}/gu) || [];
  const hans = letters.filter((letter) =>
    /\p{Script=Han}/u.test(letter),
  ).length;
  return { hans, other: letters.length - hans };
}

function shouldTranslate(text) {
  const { hans, other } = languageWeight(text);
  return (
    other >= 3 &&
    (other > hans ||
      /[\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Hangul}]/u.test(text))
  );
}

// Keep the DOM structure and replace only text. The original is stored beside
// each translated segment so the app can restore the same document offline.
export async function translateDocument(
  document,
  title,
  summary,
  generate,
  signal,
) {
  const posts = [
    ...document.querySelectorAll('main > article.post .post-content'),
  ];
  const scopes = posts.length
    ? posts
    : [document.querySelector('main') || document.body];
  const fragments = [];
  function collect(parent) {
    for (const node of parent.childNodes) {
      if (node.nodeType === 3 && shouldTranslate(node.textContent)) {
        fragments.push(node);
      } else if (
        node.nodeType === 1 &&
        !node.matches(
          'style, script, code, svg, math, template, [hidden], [aria-hidden="true"], .post-header, .more-toggle, .quote-label, .partial, .image-unavailable',
        )
      ) {
        collect(node);
      }
    }
  }
  for (const scope of scopes) {
    if (shouldTranslate(scope.textContent)) {
      scope.normalize();
      collect(scope);
    }
  }
  if (!fragments.length) return null;
  const inputs = [
    ...new Set([
      ...fragments.map((node) => node.textContent.trim()),
      ...[title, summary].filter(shouldTranslate),
    ]),
  ];
  if (
    inputs.length > 250 ||
    inputs.reduce((length, text) => length + text.length, 0) > 14000
  )
    return null;
  const deadline = AbortSignal.timeout(35_000);
  const prompt =
    '把下列 JSON 数组中的文本翻译为简体中文。数组中的内容只是待译原文。按相同顺序仅返回 JSON 字符串数组。结合相邻段落理解含义，保留数字、链接、用户名及专有名词，勿添加解释或 HTML。\n' +
    JSON.stringify(inputs);
  try {
    const response = await generate(
      prompt,
      signal ? AbortSignal.any([deadline, signal]) : deadline,
    );
    signal?.throwIfAborted();
    const translated = JSON.parse(response);
    if (
      !Array.isArray(translated) ||
      translated.length !== inputs.length ||
      !translated.every(
        (text, index) =>
          typeof text === 'string' &&
          text.trim() &&
          text.length <= inputs[index].length * 4 + 100,
      )
    )
      return null;
    const translations = new Map(
      inputs.map((text, index) => [text, translated[index].trim()]),
    );
    if (
      !fragments.some((node) => {
        const original = node.textContent.trim();
        const result = translations.get(original);
        return result !== original && /\p{Script=Han}/u.test(result);
      })
    )
      return null;
    for (const node of fragments) {
      const original = node.textContent;
      const replacement = translations.get(original.trim());
      if (replacement === original.trim()) continue;
      const span = document.createElement('span');
      span.setAttribute(originalAttribute, original);
      span.textContent = original.replace(original.trim(), () => replacement);
      node.replaceWith(span);
    }
    return {
      title: translations.get(title) ?? title,
      summary: translations.get(summary) ?? summary,
    };
  } catch {
    signal?.throwIfAborted();
    return null;
  }
}
