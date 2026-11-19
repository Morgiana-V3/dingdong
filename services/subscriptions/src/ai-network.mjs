import { ProxyAgent, fetch } from 'undici';

const proxy = process.env.X_PROXY || process.env.BROWSER_PROXY;
const dispatcher = proxy ? new ProxyAgent(proxy) : undefined;

export function aiFetch(address, options) {
  const hostname = new URL(address).hostname;
  const overseas = hostname === 'api.openai.com' || hostname === 'openrouter.ai';
  return fetch(address, { ...options, dispatcher: overseas ? dispatcher : undefined });
}
