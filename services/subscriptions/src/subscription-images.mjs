import sharp from 'sharp';
import { ProxyAgent, fetch as proxyFetch } from 'undici';
const proxy = process.env.X_PROXY || process.env.BROWSER_PROXY;
const dispatcher = proxy ? new ProxyAgent(proxy) : undefined;
export async function loadImage(address, budget, signal) {
  const url = new URL(address);
  const hosts = ['hdslb.com', 'bdimg.com', 'baidu.com', 'sinaimg.cn', 'twimg.com', 'xhscdn.com', 'xiaohongshu.com'];
  if (url.protocol !== 'https:' || url.username || url.password || !hosts.some(host => url.hostname === host || url.hostname.endsWith('.' + host))) throw new Error('配图地址不支持');
  const response = await proxyFetch(url, { redirect: 'error', signal: AbortSignal.any([AbortSignal.timeout(15000), ...(signal ? [signal] : [])]), dispatcher: url.hostname.endsWith('.twimg.com') ? dispatcher : undefined });
  if (!response.ok || !/^image\/(png|jpeg|webp|gif)(?:;|$)/i.test(response.headers.get('content-type') || '')) { await response.body?.cancel(); throw new Error('配图读取失败'); }
  let size = 0; const chunks = [];
  for await (const chunk of response.body) { size += chunk.length; if (size > 8000000) throw new Error('配图过大'); chunks.push(chunk); }
  const buffer = Buffer.concat(chunks);
  const mime = response.headers.get('content-type').split(';')[0];
  if (size <= budget) return `data:${mime};base64,${buffer.toString('base64')}`;
  for (const width of [1200, 960, 720, 480, 320, 160]) {
    signal?.throwIfAborted();
    const encoded = await sharp(buffer, { limitInputPixels: 40000000 }).resize({ width, height: 2400, fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 65 }).toBuffer();
    if (encoded.length <= budget) return 'data:image/jpeg;base64,' + encoded.toString('base64');
  }
  throw new Error('配图超过离线预算');
}
