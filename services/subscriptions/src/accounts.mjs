import crypto from 'node:crypto';

/** Native account API: relay credential grants management; a short-lived code only grants import. */
export function accountRoutes({ credential, login, serial, body, send, platform = 'bilibili', followings }) {
  let pairing;
  const matches = (a, b) => crypto.timingSafeEqual(
    crypto.createHash('sha256').update(a).digest(),
    crypto.createHash('sha256').update(b).digest(),
  );
  return async (req, res, pathname) => {
    if (pathname !== `/v1/accounts/${platform}` && !pathname.startsWith(`/v1/accounts/${platform}/`)) return false;
    if (!credential || credential.length < 32) {
      send(res, 503, { error: '服务器尚未启用平台账号管理' });
      return true;
    }
    const token = (req.headers.authorization || '').replace(/^Bearer /, '');
    if (pathname === `/v1/accounts/${platform}/import` && req.method === 'POST') {
      if (!pairing || pairing.expires < Date.now() || !matches(token, pairing.code)) {
        send(res, 401, { error: '本次授权已失效，请返回账号页重新登录' });
        return true;
      }
      pairing = undefined;
      const input = await body(req);
      const status = await serial(() => login.importPhone(input.cookie));
      send(res, 200, { state: status.state, account: status.account, itemCount: status.itemCount, message: status.message });
      return true;
    }
    if (!matches(token, credential)) {
      send(res, 401, { error: '接收密钥无效，请检查服务器设置' });
      return true;
    }
    if (pathname === `/v1/accounts/${platform}` && req.method === 'GET') {
      const { state, account, checkedAt, itemCount, message } = login.status;
      send(res, 200, { platform, state, account, checkedAt, itemCount, message, location: 'server' });
    } else if (pathname === `/v1/accounts/${platform}/pair` && req.method === 'POST') {
      pairing = { code: crypto.randomBytes(12).toString('hex'), expires: Date.now() + 10 * 60000 };
      send(res, 200, pairing);
    } else if (pathname === `/v1/accounts/${platform}/verify` && req.method === 'POST') {
      const status = await serial(() => login.verify('saved'));
      send(res, 200, { state: status.state, account: status.account, itemCount: status.itemCount, message: status.message });
    } else if (pathname === `/v1/accounts/${platform}/logout` && req.method === 'POST') {
      pairing = undefined;
      await serial(() => login.logout());
      send(res, 200, { ok: true });
    } else if (pathname === `/v1/accounts/${platform}/followings` && req.method === 'POST' && followings) {
      const input = await body(req);
      send(res, 200, await serial(() => followings(input)));
    } else {
      send(res, 404, { error: '账号接口不存在' });
    }
    return true;
  };
}
