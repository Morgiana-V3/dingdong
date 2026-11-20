import sharp from 'sharp';
import { ProxyAgent, fetch as undiciFetch } from 'undici';
import { isPrivateHost } from './http.ts';

const proxyUrl = process.env.HTTPS_PROXY || process.env.HTTP_PROXY || process.env.ENGINE_PROXY || '';
const dispatcher = proxyUrl ? new ProxyAgent(proxyUrl) : undefined;

export async function loadImage(address: string, budget: number, signal?: AbortSignal): Promise<string> {
  const url = new URL(address);
  if (url.protocol !== 'https:' || url.username || url.password || isPrivateHost(url.hostname)) {
    throw new Error('配图地址不支持或为私有地址');
  }
  const response = await undiciFetch(url, {
    redirect: 'follow',
    signal: AbortSignal.any([AbortSignal.timeout(15000), ...(signal ? [signal] : [])]),
    dispatcher,
  });
  if (!response.ok || !/^image\/(png|jpeg|webp|gif)(?:;|$)/i.test(response.headers.get('content-type') || '')) {
    await response.body?.cancel();
    throw new Error('配图读取失败');
  }
  let size = 0;
  const chunks = [];
  for await (const chunk of response.body) {
    size += chunk.length;
    if (size > 8_000_000) {
      throw new Error('配图过大');
    }
    chunks.push(chunk);
  }
  const buffer = Buffer.concat(chunks);
  const mime = response.headers.get('content-type').split(';')[0];
  if (size <= budget) {
    return `data:${mime};base64,${buffer.toString('base64')}`;
  }
  for (const width of [1200, 960, 720, 480, 320, 160]) {
    signal?.throwIfAborted();
    const encoded = await sharp(buffer, { limitInputPixels: 40_000_000 })
      .resize({ width, height: 2400, fit: 'inside', withoutEnlargement: true })
      .jpeg({ quality: 65 })
      .toBuffer();
    if (encoded.length <= budget) {
      return 'data:image/jpeg;base64,' + encoded.toString('base64');
    }
  }
  throw new Error('配图超过离线预算');
}
