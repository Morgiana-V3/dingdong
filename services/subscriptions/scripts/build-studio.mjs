import fs from 'node:fs';
import path from 'node:path';
import ts from 'typescript';
function build(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const file = path.join(directory, entry.name);
    if (entry.isDirectory()) build(file);
    else {
      const output = file.replace(/^vendor/, 'build').replace(/\.cts$/, '.cjs');
      fs.mkdirSync(path.dirname(output), { recursive: true });
      if (file.endsWith('.cts')) {
        const result = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
          fileName: file, compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.CommonJS, esModuleInterop: true },
        });
        fs.writeFileSync(output, result.outputText);
      } else fs.copyFileSync(file, output);
    }
  }
}
build('vendor/studio');
