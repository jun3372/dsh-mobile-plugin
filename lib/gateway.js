import http from 'node:http';
import { isIP } from 'node:net';
import { checkPassword, filterMobileCookies, localCookieName, cookieName, originAllowed, passwordCookie, randomToken, tokenFrom, isLoopback } from './security.js';

const MAX_LOGIN = 4096;
const TOKEN_TTL = 12 * 60 * 60 * 1000;
const RETRY_WINDOW = 10 * 60 * 1000;
const MAX_FAILURES = 8;
const ALLOWED_METHODS = new Set(['GET', 'HEAD', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']);
const GATEWAY_PROOF_HEADER = 'X-DSH-Mobile-Gateway';

// Redirects must not silently lead the mobile client to the Host's private
// web listener. Reject unexpected loopback targets and normalize the actual
// Host origin to a relative path that remains on this gateway.
function safeRedirect(location, upstream) {
  if (typeof location !== 'string') return location;
  let target;
  try { target = new URL(location, upstream); } catch { return null; }
  if (target.origin === upstream.origin) return target.pathname + target.search + target.hash;
  const host = target.hostname.replace(/^\[|\]$/g, '').toLowerCase();
  const loopback = host === 'localhost' || host === '::1' || (isIP(host) === 4 && host.startsWith('127.'));
  // DSH may use localhost while our upstream socket connects to 127.0.0.1.
  // Same listener port + canonical loopback aliases are safe to rebase.
  if (loopback && target.port === upstream.port &&
      ['localhost','127.0.0.1','::1'].includes(host) &&
      ['localhost','127.0.0.1','[::1]'].includes(upstream.hostname))
    return target.pathname + target.search + target.hash;
  if (loopback) return null;
  return location;
}

function responseHeaders(responseHeaders, upstream, instanceId) {
  const headers={...responseHeaders};
  if (typeof headers.location === 'string') {
    const location = safeRedirect(headers.location, upstream);
    if (location === null) return null;
    headers.location=location;
  }
  // DSH session cookies belong to the loopback Host and must never leave it.
  if(headers['set-cookie']) {
    const safe=[].concat(headers['set-cookie']).filter(row=>!/^dsh-auth-[^=]+=/i.test(row));
    if(safe.length)headers['set-cookie']=safe;else delete headers['set-cookie'];
  }
  // This is a routing assertion for integration tests, not an auth mechanism.
  headers[GATEWAY_PROOF_HEADER]=instanceId;
  return headers;
}

function json(res, code, data, extra = {}) {
  const body = Buffer.from(JSON.stringify(data));
  res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Content-Length': body.length, ...extra });
  res.end(body);
}
async function readJson(req, max = MAX_LOGIN) {
  if (!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type'] || '')) throw new Error('Expected JSON');
  const chunks=[]; let size=0;
  for await (const chunk of req) { size+=chunk.length; if(size>max) throw new Error('Body too large'); chunks.push(chunk); }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}
function restrictedPath(rawUrl) {
  let path;
  try { path = decodeURIComponent(new URL(rawUrl, 'http://placeholder.local').pathname).replace(/\/{2,}/g, '/').toLowerCase(); }
  catch { return true; }
  return path === '/dsh-mobile/admin' || path.startsWith('/dsh-mobile/admin/') || path === '/_dsh_mobile' || path.startsWith('/_dsh_mobile/');
}
function stripCookies(req) {
  const cookie = filterMobileCookies(req.headers.cookie).split(';').map(x=>x.trim()).filter(x=>x && !/^dsh-auth-[^=]*=/i.test(x)).join('; ');
  if (cookie) return cookie;
  return undefined;
}

export class MobileGateway {
  constructor({ mode='lan', upstream, instance, passwordHash, passwordHashes, enabledModes, bindAddress, port = 0, logger = console, upstreamSession = null }) {
    if (!['lan','public'].includes(mode)) throw new Error('invalid gateway mode');
    this.mode=mode; this.shared=!!passwordHashes; this.upstream=new URL(upstream); this.instance=instance;
    this.passwordHashes=passwordHashes||{[mode]:passwordHash};this.enabledModes=enabledModes||{[mode]:true};
    this.bindAddress=bindAddress || (this.shared || mode==='lan' ? '0.0.0.0' : '127.0.0.1'); this.requestedPort=port; this.port=0;
    this.logger=logger;this.upstreamSession=upstreamSession; this.sessions=new Map(); this.failures=new Map(); this.server=null; this.upgradedSockets=new Set();this.socketSessions=new Map();
  }
  async start() {
    if(this.server) return this.port;
    const server=http.createServer((req,res)=>{ this.handle(req,res).catch(()=>{if(!res.headersSent)json(res,500,{error:'internal_error'});else res.destroy();}); });
    server.on('upgrade', (req,socket,head)=>{this.upgrade(req,socket,head).catch(()=>socket.destroy());});
    server.headersTimeout=30_000;
    await new Promise((resolve,reject)=>{
      server.once('error',reject); server.listen(this.requestedPort, this.bindAddress, ()=>{ server.removeListener('error',reject); resolve(); });
    });
    this.server=server; this.port=server.address().port;
    return this.port;
  }
  async stop() {
    this.sessions.clear(); this.failures.clear();
    for(const socket of this.upgradedSockets) socket.destroy(); this.upgradedSockets.clear();this.socketSessions.clear();
    const server=this.server; this.server=null; this.port=0;
    if(server){ server.closeAllConnections?.(); await new Promise(resolve=>server.close(()=>resolve())); }
  }
  revokeSession(token) {
    this.sessions.delete(token);
    for(const socket of this.socketSessions.get(token)||[]) socket.destroy();
    this.socketSessions.delete(token);
  }
  setPasswordHash(hash) { this.setMode(this.mode,true,hash); }
  setMode(mode,enabled,hash) {
    if(!['lan','public'].includes(mode))throw new Error('invalid gateway mode');
    const changed=this.enabledModes[mode]!==enabled || this.passwordHashes[mode]!==hash;
    this.enabledModes[mode]=enabled; this.passwordHashes[mode]=hash;
    if(changed){
      for(const [token,record] of this.sessions)if(record.mode===mode)this.revokeSession(token);
      this.failures.clear();
      // Existing upgraded sockets may have belonged to this mode; close on
      // any authorization change rather than risk retaining revoked access.
      for(const socket of this.upgradedSockets)socket.destroy();this.upgradedSockets.clear();
    }
  }
  requestMode(req) {
    if(!this.shared)return this.enabledModes[this.mode]?this.mode:null;
    // Tunnel always connects from 127.0.0.1. Do NOT trust Host or forwarded
    // headers: remote callers can spoof them to downgrade public auth to LAN.
    const loopback=isLoopback(req.socket.remoteAddress);
    if(loopback && this.enabledModes.public)return 'public';
    if(this.enabledModes.lan)return 'lan';
    return null;
  }
  authorized(req,mode=this.requestMode(req)) {
    const token = tokenFrom(req); if (!token || !/^[\w-]{43}$/.test(token)) return false;
    const record=this.sessions.get(token);
    if(!record || record.expires < Date.now()){ this.revokeSession(token); return false; }
    if(record.mode!==mode) return false;
    return true;
  }
  info(mode=this.mode) {
    const data={ protocol:'dsh-mobile/1', instanceId:this.instance.id, publicKey:this.instance.publicKey, mode, capabilities:['http-proxy','websocket-proxy'], requiresPassword:true };
    return { ...data, signature:this.instance.sign(data) };
  }
  // This QR bootstrap is restricted to GET /?token=<password>. Never forward
  // a URL password to DSH's native HTTP/Remote interfaces.
  async qrLogin(req,res,mode,password) {
    return this.authenticatePassword(req,res,mode,password,true);
  }
  async login(req,res,mode=this.requestMode(req)) {
    let payload;
    try {payload=await readJson(req);} catch{return json(res,400,{error:'invalid_json'});}
    return this.authenticatePassword(req,res,mode,payload?.password,false);
  }
  authenticatePassword(req,res,mode,password,fromQr=false) {
    const extra=fromQr?{'Cache-Control':'no-store','Referrer-Policy':'no-referrer'}:{};
    const fail=(status,data,more={})=>json(res,status,data,{...extra,...more});
    const key=req.socket.remoteAddress || 'unknown';
    const attempts=this.failures.get(key);
    if(attempts && attempts.until>Date.now() && attempts.count>=MAX_FAILURES) return fail(429,{error:'too_many_attempts'}, {'Retry-After': '600'});
    const valid=checkPassword(password,this.passwordHashes[mode]);
    if(!valid) {
      const now=Date.now();
      const record=attempts && attempts.until>now ? attempts : {count:0,until:now+RETRY_WINDOW};
      record.count++; this.failures.set(key,record);
      return fail(401,{error:'invalid_password'});
    }
    this.failures.delete(key);
    const token=randomToken(); this.sessions.set(token,{expires:Date.now()+TOKEN_TTL,mode});
    if(this.sessions.size>1000){for (const [k,exp] of this.sessions) if(exp.expires<Date.now()) this.sessions.delete(k); while(this.sessions.size>1000) this.sessions.delete(this.sessions.keys().next().value);}
    // The bearer token is consumed by native Flutter, the cookie by browser fetch/WS.
    const secure=mode==='public';
    if(fromQr) {
      // Browser receives a session cookie and immediately leaves the URL that
      // contains the password. There is no upstream request in this step.
      res.writeHead(303,{'Location':'/','Set-Cookie':passwordCookie(token,secure),'Cache-Control':'no-store','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff'});
      res.end();return;
    }
    return json(res,200,{ protocol:'dsh-mobile/1', instanceId:this.instance.id, token, expiresIn:TOKEN_TTL/1000 }, {'Set-Cookie': passwordCookie(token,secure)});
  }
  async handle(req,res) {
    const parsedUrl=new URL(req.url,'http://placeholder.local');
    const path=parsedUrl.pathname;
    const mode=this.requestMode(req);
    if(!mode)return json(res,403,{error:'network_disabled'});
    if(!ALLOWED_METHODS.has(req.method)) return json(res,405,{error:'method_not_allowed'});
    if (!originAllowed(req)) return json(res,403,{error:'origin_rejected'});
    // Reserve ONLY GET /?token=<mobile-password> for the QR bootstrap.
    // DSH itself is allowed to use a query parameter named "token" on other
    // application routes. Blocking it globally changed native API semantics.
    if(parsedUrl.searchParams.has('token')) {
      if(path==='/' || path.startsWith('/_dsh_mobile/')) {
        if(req.method!=='GET' || parsedUrl.searchParams.getAll('token').length!==1 || [...parsedUrl.searchParams.keys()].some(k=>k!=='token'))
          return json(res,400,{error:'invalid_qr_url'},{'Referrer-Policy':'no-referrer'});
        if(path!=='/')return json(res,400,{error:'invalid_qr_url'},{'Referrer-Policy':'no-referrer'});
        return this.qrLogin(req,res,mode,parsedUrl.searchParams.get('token'));
      }
      // Do not accidentally leak the actual mobile password to the Host if a
      // caller pastes the QR token onto an arbitrary non-root URL.
      if(parsedUrl.searchParams.getAll('token').some(value=>checkPassword(value,this.passwordHashes[mode])))
        return json(res,400,{error:'mobile_password_in_upstream_query'},{'Referrer-Policy':'no-referrer'});
    }
    if(path==='/_dsh_mobile/v1/info' && req.method==='GET') return json(res,200,this.info(mode));
    if(path==='/_dsh_mobile/v1/login' && req.method==='POST') return this.login(req,res,mode);
    if(path==='/_dsh_mobile/v1/logout' && req.method==='POST') {
      if(this.authorized(req,mode))this.revokeSession(tokenFrom(req));
      return json(res,200,{ok:true},{'Set-Cookie':`${mode==='public'?cookieName:localCookieName}=; Path=/; HttpOnly; SameSite=Strict; Max-Age=0${mode==='public'?'; Secure':''}`});
    }
    if(path.startsWith('/_dsh_mobile/')) return json(res,404,{error:'not_found'});
    if(!this.authorized(req,mode)) return json(res,401,{error:'authentication_required'});
    // Remote mobile clients must never reach the plugin's privileged local-admin API
    // by relaying back through the upstream DSH host.
    if(restrictedPath(req.url)) return json(res,403,{error:'restricted_path'});
    return this.proxy(req,res);
  }
  upstreamHeaders(req, hostCookie=''){
    const h={...req.headers};
    h.host=this.upstream.host;
    h.origin=this.upstream.origin;
    delete h['proxy-authorization']; delete h['proxy-connection'];
    delete h['x-forwarded-for']; delete h['x-forwarded-host']; delete h['x-forwarded-proto']; delete h['cf-connecting-ip'];
    // Never forward the bearer used to log into DSH Mobile to the DSH host.
    if(typeof h.authorization==='string' && h.authorization.startsWith('Bearer ')) delete h.authorization;
    const cookie=stripCookies(req);
    if(cookie || hostCookie) h.cookie=[cookie,hostCookie].filter(Boolean).join('; '); else delete h.cookie;
    return h;
  }
  async proxy(req,res){
    let hostCookie='';
    if (this.upstreamSession) {
      try { hostCookie=await this.upstreamSession.getCookie(); }
      catch { return json(res,502,{error:'dsh_upstream_auth_unavailable'}); }
    }
    return new Promise(resolve=>{
      const upstream=http.request({hostname:this.upstream.hostname, port:this.upstream.port, method:req.method, path:req.url, headers:this.upstreamHeaders(req,hostCookie), timeout:120_000 }, response=>{
        if (response.statusCode === 401) this.upstreamSession?.invalidate();
        const headers=responseHeaders(response.headers,this.upstream,this.instance.id);
        if(!headers) {
          response.resume();
          json(res,502,{error:'upstream_direct_redirect_blocked'}, {[GATEWAY_PROOF_HEADER]:this.instance.id});
          resolve(); return;
        }
        res.writeHead(response.statusCode||502,headers); response.pipe(res); response.once('end',resolve);response.once('error',()=>{res.destroy();resolve();});
      });
      upstream.on('timeout',()=>upstream.destroy(new Error('upstream timeout')));
      upstream.on('error',()=>{if(!res.headersSent) json(res,502,{error:'upstream_unavailable'}); else res.destroy(); resolve();});
      req.on('aborted',()=>upstream.destroy());
      // Long-lived DSH streams (SSE/download) must be cancelled when the mobile
      // client disconnects; the request body may have finished long ago.
      res.on('close',()=>{if(!res.writableEnded)upstream.destroy();resolve();});
      req.pipe(upstream);
    });
  }
  async upgrade(req,socket,head){
    const path=new URL(req.url,'http://placeholder.local').pathname;
    if(!this.requestMode(req) || restrictedPath(req.url) || !this.authorized(req) || !originAllowed(req)) {
      socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\nContent-Length: 0\r\n\r\n'); return;
    }
    if(req.headers.upgrade?.toLowerCase()!=='websocket') {socket.destroy();return;}
    let hostCookie='';
    if (this.upstreamSession) {
      try { hostCookie=await this.upstreamSession.getCookie(); }
      catch { socket.end('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');return; }
    }
    if (socket.destroyed) return;
    const up=http.request({hostname:this.upstream.hostname,port:this.upstream.port,method:'GET',path:req.url,headers:this.upstreamHeaders(req,hostCookie),timeout:30_000});
    let completed=false;
    up.on('upgrade',(response,upstreamSocket,upstreamHead)=>{
      completed=true;
      const headers=responseHeaders(response.headers,this.upstream,this.instance.id);
      if(!headers) {socket.destroy();upstreamSocket.destroy();return;}
      socket.write(`HTTP/1.1 ${response.statusCode} ${response.statusMessage}\r\n`);
      for(const [name,val] of Object.entries(headers)) {
        if (val !== undefined) socket.write(`${name}: ${Array.isArray(val)?val.join(', '):val}\r\n`);
      }
      socket.write('\r\n');
      if(upstreamHead.length) socket.write(upstreamHead);
      if(head.length) upstreamSocket.write(head);
      this.upgradedSockets.add(socket); this.upgradedSockets.add(upstreamSocket);
      // Keep active WS streams attached to the mobile access token so logout
      // and token expiry revoke the open channel, not just future requests.
      const mobileToken=tokenFrom(req);
      const expiry=this.sessions.get(mobileToken)?.expires??Date.now();
      const pair=new Set([socket,upstreamSocket]);
      this.socketSessions.set(mobileToken,new Set([...(this.socketSessions.get(mobileToken)||[]),...pair]));
      const lifetime=setTimeout(()=>this.revokeSession(mobileToken),Math.max(1,expiry-Date.now()));
      lifetime.unref?.();
      let cleaned=false;
      const cleanup=()=>{
        if(cleaned)return;cleaned=true;clearTimeout(lifetime);
        for(const s of pair)this.upgradedSockets.delete(s);
        const active=this.socketSessions.get(mobileToken);
        if(active){for(const s of pair)active.delete(s);if(active.size===0)this.socketSessions.delete(mobileToken);}
        for(const s of pair)if(!s.destroyed)s.destroy();
      };
      socket.once('close',cleanup);upstreamSocket.once('close',cleanup);
      upstreamSocket.on('error',()=>socket.destroy()); socket.on('error',()=>upstreamSocket.destroy());
      upstreamSocket.pipe(socket); socket.pipe(upstreamSocket);
    });
    up.on('response',(r)=>{
      if(r.statusCode===401)this.upstreamSession?.invalidate();
      if(completed){r.resume();return;}
      completed=true;
      // A rejected WebSocket upgrade is still a real DSH HTTP response:
      // preserve its status, relevant headers and body instead of replacing
      // every non-101 response with an empty payload.
      const headers=responseHeaders(r.headers,this.upstream,this.instance.id);
      if(!headers){r.resume();socket.end('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');return;}
      socket.write(`HTTP/1.1 ${r.statusCode} ${r.statusMessage}\r\n`);
      for(const [name,values] of Object.entries(headers)){
        for(const value of Array.isArray(values)?values:[values]){
          if(value!==undefined)socket.write(`${name}: ${value}\r\n`);
        }
      }
      socket.write('\r\n');
      r.on('error',()=>socket.destroy());
      r.pipe(socket);
    });
    up.on('error',()=>{
      if(!completed && !socket.destroyed)socket.end('HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
      else socket.destroy();
    });
    up.on('timeout',()=>up.destroy()); up.end();
  }
}
