import { createHash, createPrivateKey, createPublicKey, generateKeyPairSync, randomBytes, scryptSync, timingSafeEqual, sign } from 'node:crypto';
import { isIP } from 'node:net';

export const MODE_NAMES = ['lan', 'public'];
export const cookieName = '__Host-dsh_mobile_session';
export const localCookieName = 'dsh_mobile_session'; // non-HTTPS LAN cannot use __Host prefix
export const randomPassword = () => randomBytes(12).toString('base64url');
export const randomToken = () => randomBytes(32).toString('base64url');
export const hashPassword = password => {
  const salt = randomBytes(16);
  return `scrypt:${salt.toString('hex')}:${scryptSync(password, salt, 32).toString('hex')}`;
};
export function checkPassword(password, record) {
  if (typeof password !== 'string' || password.length > 128 || typeof record !== 'string') return false;
  const parts = record.split(':');
  if (parts.length !== 3 || parts[0] !== 'scrypt' || !/^[0-9a-f]{32}$/.test(parts[1]) || !/^[0-9a-f]{64}$/.test(parts[2])) return false;
  const got = scryptSync(password, Buffer.from(parts[1], 'hex'), 32);
  return timingSafeEqual(got, Buffer.from(parts[2], 'hex'));
}
export function safePassword(value) { return typeof value === 'string' && value.length >= 8 && value.length <= 64; }
export function isLoopback(address) {
  if (typeof address !== 'string') return false;
  const normalized = address.startsWith('::ffff:') ? address.substring(7) : address;
  return normalized === '127.0.0.1' || normalized.startsWith('127.') || normalized === '::1';
}
export function safeUpstream(url) {
  const u = new URL(url);
  if (u.protocol !== 'http:' || u.username || u.password || u.hash || u.search || u.pathname !== '/') throw new Error('upstream must be a loopback HTTP origin');
  if (!['localhost', '127.0.0.1', '[::1]'].includes(u.hostname)) throw new Error('upstream must be loopback');
  if (!u.port || !/^\d{2,5}$/.test(u.port)) throw new Error('upstream port required');
  return u;
}
export function createIdentity() {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  return { privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }), publicKey: publicKey.export({ type: 'spki', format: 'der' }).toString('base64url') };
}
export function identityFrom(privatePem) {
  const priv = createPrivateKey(privatePem);
  const pub = createPublicKey(priv).export({ format: 'der', type: 'spki' }).toString('base64url');
  const id = createHash('sha256').update(Buffer.from(pub, 'base64url')).digest('hex').substring(0,32);
  return { id, publicKey: pub, sign: payload => sign(null, Buffer.from(JSON.stringify(payload)), priv).toString('base64url') };
}
export function originAllowed(req) {
  const origin = req.headers.origin;
  if (!origin) return true; // native clients frequently have no Origin
  try {
    const originUrl = new URL(origin);
    return originUrl.host === req.headers.host && ['http:', 'https:'].includes(originUrl.protocol);
  } catch { return false; }
}
export function passwordCookie(value, secure = false) {
  return `${secure ? cookieName : localCookieName}=${value}; Path=/; HttpOnly; SameSite=Strict; Max-Age=43200${secure ? '; Secure' : ''}`;
}
export function parseCookies(header) {
  const result = {};
  for (const chunk of String(header || '').split(';')) {
    const i = chunk.indexOf('=');
    if (i > 0) result[chunk.slice(0, i).trim()] = chunk.slice(i + 1).trim();
  }
  return result;
}
export function tokenFrom(req) {
  const header = req.headers.authorization;
  if (typeof header === 'string' && /^Bearer [\w-]{30,200}$/.test(header)) return header.slice(7);
  const cookies = parseCookies(req.headers.cookie);
  return cookies[cookieName] || cookies[localCookieName] || '';
}
export function filterMobileCookies(header) {
  return String(header || '').split(';').map(x => x.trim()).filter(x => x && !x.startsWith(`${cookieName}=`) && !x.startsWith(`${localCookieName}=`)).join('; ');
}
