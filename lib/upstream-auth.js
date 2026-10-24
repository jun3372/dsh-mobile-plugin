import http from 'node:http';
import { safeUpstream } from './security.js';

// The DSH Host uses a separate, authority-bound browser session for all APIs.
// Only the in-process, trusted DSH Connection is allowed to mint its bootstrap
// URL. Its launch token and cookie NEVER leave this server or enter QR payloads.
export class UpstreamBrowserSession {
  constructor({ upstream, authenticatedUrl, refreshBeforeMs = 60_000 }) {
    this.origin = safeUpstream(upstream).origin;
    if (typeof authenticatedUrl !== 'function') throw new Error('DSH authenticatedUrl is unavailable');
    this.authenticatedUrl = authenticatedUrl;
    this.refreshBeforeMs = refreshBeforeMs;
    this.cookie = '';
    this.expiresAt = 0;
    this.pending = null;
  }
  invalidate() { this.cookie = ''; this.expiresAt = 0; }
  async getCookie() {
    if (this.cookie && this.expiresAt - Date.now() > this.refreshBeforeMs) return this.cookie;
    if (!this.pending) {
      this.pending = this.bootstrap().finally(() => { this.pending = null; });
    }
    return this.pending;
  }
  async bootstrap() {
    const advertised = this.authenticatedUrl(`${this.origin}/`);
    const url = new URL(advertised);
    if (url.origin !== this.origin || url.pathname !== '/' || !url.searchParams.has('token') || url.username || url.password || url.hash)
      throw new Error('DSH returned an invalid local authentication URL');
    // No redirect following, so the launch token can never leave loopback.
    const headers = await new Promise((resolve, reject) => {
      const request = http.get(url, {timeout: 8_000, headers: {accept: 'text/html'}}, response => {
        const headers = response.headers;
        const status = response.statusCode;
        response.resume();
        if (status !== 303 && status !== 302) reject(new Error(`DSH session bootstrap returned HTTP ${status}`));
        else resolve(headers);
      });
      request.on('timeout', () => request.destroy(new Error('DSH authentication bootstrap timed out')));
      request.on('error', reject);
    });
    const cookies = headers['set-cookie'] || [];
    const row = cookies.find(s => /^dsh-auth-[a-zA-Z0-9_-]+=/i.test(s));
    if (!row) throw new Error('DSH did not issue a browser authentication cookie');
    const match = /^(dsh-auth-[a-zA-Z0-9_-]+)=([^;\r\n]+)/i.exec(row);
    if (!match) throw new Error('DSH returned malformed session cookie');
    const ttl = /(?:^|;)\s*Max-Age=(\d+)/i.exec(row);
    // Do not cache indefinitely if Max-Age is absent: refresh proactively.
    const lifetime = ttl ? Math.min(Number(ttl[1]) * 1000, 24 * 3600_000) : 3600_000;
    this.cookie = `${match[1]}=${match[2]}`;
    this.expiresAt = Date.now() + lifetime;
    return this.cookie;
  }
}
