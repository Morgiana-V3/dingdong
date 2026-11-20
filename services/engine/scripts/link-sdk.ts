import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const nodeModules = path.join(root, 'node_modules');
const linkPath = path.join(nodeModules, 'dingdong-engine');

fs.mkdirSync(nodeModules, { recursive: true });
try {
  const stat = fs.lstatSync(linkPath);
  if (stat.isSymbolicLink()) {
    fs.unlinkSync(linkPath);
  }
} catch {
  // Does not exist yet
}

if (!fs.existsSync(linkPath)) {
  fs.symlinkSync(root, linkPath, process.platform === 'win32' ? 'junction' : 'dir');
}
