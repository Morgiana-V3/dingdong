const { EventEmitter } = require('node:events');
const port = new EventEmitter();
port.postMessage = value => { if (process.connected) process.send(value); };
process.on('message', data => port.emit('message', { data }));
process.on('disconnect', () => process.exit(0));
process.parentPort = port;
