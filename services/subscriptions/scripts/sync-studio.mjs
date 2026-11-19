import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
const service = fileURLToPath(new URL('../', import.meta.url));
const source = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.resolve(service, '../../../dingdong--studio');
const target = path.join(service, 'vendor/studio');
const files = [];
function copy(relative) {
  const from = path.join(source, relative);
  const to = path.join(target, relative);
  fs.mkdirSync(path.dirname(to), { recursive: true });
  fs.copyFileSync(from, to);
  files.push({ path: relative.replaceAll('\\', '/'), sha256: crypto.createHash('sha256').update(fs.readFileSync(from)).digest('hex') });
}
for (const file of fs.readdirSync(path.join(source, 'src'))) {
  if (file.endsWith('.cts') && !['main.cts', 'preload.cts', 'ipc.cts', 'mobile-control.cts'].includes(file)) copy('src/' + file);
}
for (const name of ['bilibili', 'tieba', 'x', 'xiaohongshu']) {
  for (const file of fs.readdirSync(path.join(source, 'examples', name))) copy(`examples/${name}/${file}`);
}
for (const file of ['push-markdown.css', 'push-content.css']) {
  if (fs.existsSync(path.join(source, 'src/ui/assets', file))) copy('src/ui/assets/' + file);
}
for (const name of ['bilibili.test.cts', 'tieba.test.cts', 'x.test.cts', 'xiaohongshu.test.cts', 'digest.test.cts', 'x-http.test.cts']) if (fs.existsSync(path.join(source, 'tests', name))) copy('tests/' + name);
for (const name of fs.readdirSync(path.join(source, 'tests/helpers'))) if (name.endsWith('.cts')) copy('tests/helpers/' + name);
copy('THIRD_PARTY_NOTICES.txt');
fs.writeFileSync(path.join(target, 'source-manifest.json'), JSON.stringify({ source: 'dingdong--studio', files }, null, 2) + '\n');
console.log(`Synced ${files.length} Studio source files`);
