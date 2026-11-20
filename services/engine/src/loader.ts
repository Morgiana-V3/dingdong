import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export async function loadDirectoryPlugins(ctx, directories, registry) {
  const dirs = Array.isArray(directories) ? directories : [directories];
  const loaded = [];
  for (const dir of dirs) {
    if (!dir || !fs.existsSync(dir)) continue;
    const entries = fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name));
    for (const entry of entries) {
      if (entry.name.startsWith('.') || entry.name === 'node_modules') continue;
      let entryFile;
      if (entry.isDirectory()) {
        const pkgPath = path.join(dir, entry.name, 'package.json');
        if (fs.existsSync(pkgPath)) {
          try {
            const pkg = JSON.parse(fs.readFileSync(pkgPath, 'utf8'));
            if (typeof pkg.main === 'string') {
              const candidate = path.resolve(dir, entry.name, pkg.main);
              if (candidate.startsWith(path.resolve(dir, entry.name)) && fs.existsSync(candidate)) {
                entryFile = candidate;
              }
            }
          } catch {
            // Fall through to conventional entry lookup
          }
        }
        if (!entryFile) {
          for (const candidateName of ['src/index.ts', 'index.ts', 'index.mts', 'index.mjs', 'index.js']) {
            const candidate = path.join(dir, entry.name, candidateName);
            if (fs.existsSync(candidate)) {
              entryFile = candidate;
              break;
            }
          }
        }
      } else if (entry.isFile() && /\.(?:ts|mts|mjs|js)$/.test(entry.name) && !entry.name.endsWith('.d.ts')) {
        entryFile = path.join(dir, entry.name);
      }
      if (!entryFile) continue;
      try {
        const mod = await import(pathToFileURL(entryFile).href);
        const plugin = mod.default && typeof mod.default.apply === 'function' ? mod.default : mod;
        if (typeof plugin.apply !== 'function') {
          throw new Error('插件必须导出 apply(ctx) 函数');
        }
        const safePlugin = {
          ...plugin,
          name: plugin.name || entry.name,
          apply(innerCtx, config) {
            try {
              const result = plugin.apply(innerCtx, config);
              if (result && typeof result.catch === 'function') {
                return result.catch((err) => registry?.recordLoadError(entry.name, err));
              }
              return result;
            } catch (err) {
              registry?.recordLoadError(entry.name, err);
            }
          },
        };
        ctx.plugin(safePlugin);
        loaded.push({ name: safePlugin.name, path: entryFile });
      } catch (error) {
        registry?.recordLoadError(entry.name, error);
      }
    }
  }
  return loaded;
}
