import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import { parseHTML } from 'linkedom';

/**
 * Compile a `template.html + style.css + render.js` template directory into
 * self-contained, script-free static HTML using linkedom + node:vm (zero Chromium).
 *
 * Developers can open `template.html` directly in any browser / Live Server to
 * live-edit HTML & CSS with `testData`, while the engine executes `render(data)`
 * server-side, inlines local stylesheets, and strips all `<script>` tags.
 */
export function renderHtmlTemplate(
  templateLocation: string | URL,
  data: Record<string, unknown> = {},
): string {
  const resolved =
    templateLocation instanceof URL ? fileURLToPath(templateLocation) : path.resolve(templateLocation);
  const isFile = fs.existsSync(resolved) && fs.statSync(resolved).isFile();
  const baseDir = isFile ? path.dirname(resolved) : resolved;
  const htmlPath = isFile ? resolved : path.join(baseDir, 'template.html');

  if (!fs.existsSync(htmlPath)) {
    throw new Error(`找不到 HTML 模板文件: ${htmlPath}`);
  }

  const rawHtml = fs.readFileSync(htmlPath, 'utf8');
  const { document } = parseHTML(rawHtml);

  // 1. Inline local <link rel="stylesheet" href="./..."> into <style>
  for (const link of [...document.querySelectorAll('link[rel="stylesheet"]')]) {
    const href = (link.getAttribute('href') || '').trim();
    if (!href || /^https?:\/\//i.test(href)) {
      link.remove();
      continue;
    }
    const cssPath = path.resolve(baseDir, href);
    if (!cssPath.startsWith(path.resolve(baseDir)) || !fs.existsSync(cssPath)) {
      link.remove();
      continue;
    }
    const style = document.createElement('style');
    style.textContent = fs.readFileSync(cssPath, 'utf8');
    link.replaceWith(style);
  }

  // 2. Collect local <script src="./..."> and inline scripts, run in isolated VM
  const scripts: string[] = [];
  for (const script of [...document.querySelectorAll('script')]) {
    const src = (script.getAttribute('src') || '').trim();
    if (src) {
      if (!/^https?:\/\//i.test(src)) {
        const jsPath = path.resolve(baseDir, src);
        if (jsPath.startsWith(path.resolve(baseDir)) && fs.existsSync(jsPath)) {
          scripts.push(fs.readFileSync(jsPath, 'utf8'));
        }
      }
    } else if (script.textContent?.trim()) {
      scripts.push(script.textContent);
    }
    script.remove();
  }

  if (scripts.length) {
    const windowObj: Record<string, unknown> = {
      __DINGDONG_SERVER__: true,
      document,
    };
    const sandbox: Record<string, unknown> = {
      window: windowObj,
      globalThis: windowObj,
      document,
      console,
      URL,
      Intl,
      Date,
      Math,
      JSON,
      Array,
      Object,
      String,
      Number,
      Boolean,
      RegExp,
      Map,
      Set,
    };
    const context = vm.createContext(sandbox);
    for (const code of scripts) {
      vm.runInContext(code, context, { timeout: 2000 });
    }
    const renderFn =
      typeof sandbox.render === 'function'
        ? (sandbox.render as (d: unknown) => void)
        : typeof windowObj.render === 'function'
          ? (windowObj.render as (d: unknown) => void)
          : null;
    if (!renderFn) {
      throw new Error(`模板脚本未定义 render(data) 函数: ${htmlPath}`);
    }
    renderFn(structuredClone(data));
  }

  // 3. Inline local relative asset images (e.g. <img src="./assets/icon.svg">) as data URIs
  const mimeByExt: Record<string, string> = {
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.webp': 'image/webp',
    '.gif': 'image/gif',
  };
  for (const img of [...document.querySelectorAll('img')]) {
    const src = (img.getAttribute('src') || '').trim();
    if (!src || /^https?:\/\//i.test(src) || /^data:/i.test(src)) continue;
    const assetPath = path.resolve(baseDir, src);
    const ext = path.extname(assetPath).toLowerCase();
    const mime = mimeByExt[ext];
    if (!mime || !assetPath.startsWith(path.resolve(baseDir)) || !fs.existsSync(assetPath)) continue;
    const raw = fs.readFileSync(assetPath);
    img.setAttribute('src', `data:${mime};base64,${raw.toString('base64')}`);
  }

  return document.toString();
}
