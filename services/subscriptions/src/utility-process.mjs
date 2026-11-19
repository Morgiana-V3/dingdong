import { fork } from 'node:child_process';
import { fileURLToPath } from 'node:url';
// Studio's plugin protocol is retained; only Electron's transport is replaced.
export const utilityProcess = {
  fork(filename, args, options) {
    const child = fork(filename, args, {
      ...options, stdio: ['ignore', 'ignore', 'ignore', 'ipc'],
      execArgv: ['--require', fileURLToPath(new URL('./worker-preload.cjs', import.meta.url))],
    });
    child.postMessage = value => { if (child.connected) child.send(value); };
    return child;
  },
};
