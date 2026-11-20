import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const nodeModules = path.join(root, 'node_modules');
const pkgDir = path.join(nodeModules, 'dingdong-engine');

fs.mkdirSync(nodeModules, { recursive: true });
try {
  const stat = fs.lstatSync(pkgDir);
  if (stat.isSymbolicLink()) {
    fs.unlinkSync(pkgDir);
  }
} catch {
  // Does not exist yet
}

fs.mkdirSync(pkgDir, { recursive: true });
try {
  fs.rmSync(path.join(pkgDir, 'sdk.ts'), { force: true });
} catch {
  // Ignore
}
fs.writeFileSync(
  path.join(pkgDir, 'package.json'),
  JSON.stringify(
    {
      name: 'dingdong-engine',
      private: true,
      type: 'module',
      exports: {
        './sdk': {
          types: './sdk.d.ts',
          default: './sdk.js',
        },
      },
    },
    null,
    2,
  ) + '\n',
);
fs.writeFileSync(
  path.join(pkgDir, 'sdk.js'),
  "export * from '../../sdk/index.ts';\n",
);
fs.writeFileSync(
  path.join(pkgDir, 'sdk.d.ts'),
  "export * from '../../sdk/index.ts';\n",
);
