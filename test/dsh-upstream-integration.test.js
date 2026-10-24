import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {connect} from 'node:net';
import {once} from 'node:events';
import {createIdentity,identityFrom,hashPassword} from '../lib/security.js';
import {MobileGateway} from '../lib/gateway.js';
import {UpstreamBrowserSession} from '../lib/upstream-auth.js';

async function fakeDSH(t) {
  let activeCookie = 'dsh-auth-test=v1.authenticated';
  let bootstrapCount=0, requestCount=0, wsCount=0;
  const server=http.createServer((req,res)=>{
    if(req.url==='/?token=local-bootstrap' && req.method==='GET') {
      bootstrapCount++;
      res.writeHead(303,{'Location':'/','Set-Cookie':`${activeCookie}; Path=/; HttpOnly; SameSite=Strict; Max-Age=2592000`});return res.end();
    }
    if(req.url.startsWith('/api/') && !String(req.headers.cookie||'').split(';').some(x=>x.trim()===activeCookie)) {
      res.writeHead(401);return res.end('DSH browser session required');
    }
    requestCount++;
    if(req.url==='/api/file/download') {
      res.writeHead(206,{'Content-Type':'application/octet-stream','Content-Range':'bytes 0-4/100'});return res.end(Buffer.from([0,1,2,3,4]));
    }
    let body='';req.on('data',chunk=>body+=chunk.toString());req.on('end',()=>{
      res.writeHead(200,{'Content-Type':'application/json'});
      res.end(JSON.stringify({method:req.method,body,host:req.headers.host,cookie:req.headers.cookie,origin:req.headers.origin,path:req.url}));
    });
  });
  server.on('upgrade',(req,socket)=>{
    if (!String(req.headers.cookie||'').split(';').some(x=>x.trim()===activeCookie)) {socket.end('HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n');return;}
    wsCount++;
    socket.end('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: example\r\n\r\n');
  });
  await new Promise(ok=>server.listen(0,'127.0.0.1',ok));
  t.after(()=>new Promise(ok=>server.closeAllConnections?.() || server.close(ok)));
  return {server,origin:`http://127.0.0.1:${server.address().port}`,get activeCookie(){return activeCookie;},get bootstraps(){return bootstrapCount;},get requests(){return requestCount;},get upgrades(){return wsCount;},rotate(){activeCookie='dsh-auth-test=v1.updated';}};
}
async function testGateway(t,host) {
  const upstreamSession=new UpstreamBrowserSession({upstream:host.origin,authenticatedUrl:base=>`${base}?token=local-bootstrap`});
  const gateway=new MobileGateway({upstream:host.origin,upstreamSession,instance:identityFrom(createIdentity().privateKey),passwordHashes:{lan:hashPassword('lan-secret-2026'),public:hashPassword('public-secret-2026')},enabledModes:{lan:true,public:true},port:0});
  await gateway.start();t.after(()=>gateway.stop());
  const base=`http://127.0.0.1:${gateway.port}`;
  const login=await fetch(`${base}/_dsh_mobile/v1/login`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:'public-secret-2026'})});
  assert.equal(login.status,200);
  return {gateway,base,token:(await login.json()).token,session:upstreamSession};
}
test('DSH upstream rejects mobile password alone but accepts in-process browser session bootstrap',async t=>{
  const dsh=await fakeDSH(t);
  const unauthorized=await fetch(`${dsh.origin}/api/remote/foo`,{method:'POST',body:'{}'});
  assert.equal(unauthorized.status,401,'DSH Host itself requires the second auth layer');
  const {base,token}=await testGateway(t,dsh);
  const resp=await fetch(`${base}/api/remote/foo`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:'{"args":{"message":"hello"}}'});
  assert.equal(resp.status,200);
  const json=await resp.json();
  assert.equal(json.body,'{"args":{"message":"hello"}}');
  assert.match(json.cookie,/dsh-auth-test=v1.authenticated/);
  assert.equal(dsh.bootstraps,1);
  const second=await fetch(`${base}/api/remote/bar`,{headers:{Authorization:`Bearer ${token}`}});
  assert.equal(second.status,200);
  assert.equal(dsh.bootstraps,1,'reuse cookie, no token generation for each request');
});
test('binary downloads and authenticated WebSocket upgrades pass through',async t=>{
  const dsh=await fakeDSH(t);
  const {base,token,gateway}=await testGateway(t,dsh);
  const file=await fetch(`${base}/api/file/download`,{headers:{Authorization:`Bearer ${token}`,Range:'bytes=0-4'}});
  assert.equal(file.status,206);assert.equal(file.headers.get('content-range'),'bytes 0-4/100');
  assert.deepEqual(Buffer.from(await file.arrayBuffer()),Buffer.from([0,1,2,3,4]));
  const socket=connect(gateway.port,'127.0.0.1');await once(socket,'connect');
  const received=new Promise((resolve,reject)=>{let text='';socket.on('data',d=>text+=d.toString());socket.once('end',()=>resolve(text));socket.once('error',reject);});
  socket.write(`GET /api/remote.mux HTTP/1.1\r\nHost: 127.0.0.1:${gateway.port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nAuthorization: Bearer ${token}\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n`);
  assert.match(await received,/^HTTP\/1\.1 101 Switching Protocols/);
  assert.equal(dsh.upgrades,1);
});
test('DSH Host 401 invalidates cached cookie; next request bootstraps an updated session',async t=>{
  const dsh=await fakeDSH(t);
  const {base,token}=await testGateway(t,dsh);
  const url=`${base}/api/session/list`,headers={Authorization:`Bearer ${token}`};
  assert.equal((await fetch(url,{headers})).status,200);
  dsh.rotate();
  assert.equal((await fetch(url,{headers})).status,401);
  assert.equal((await fetch(url,{headers})).status,200);
  assert.equal(dsh.bootstraps,2);
});
test('never follow authentication bootstrap redirects to external domains',async t=>{
  const dsh=await fakeDSH(t);
  const session=new UpstreamBrowserSession({upstream:dsh.origin,authenticatedUrl:()=>`https://evil.example/?token=stolen`});
  await assert.rejects(()=>session.getCookie(),/invalid local authentication URL/);
  assert.equal(dsh.bootstraps,0);
});
test('when upstream session cannot be established, gateway fails closed without exposing DSH APIs',async t=>{
  const dsh=await fakeDSH(t);
  const session={async getCookie(){throw new Error('bootstrap offline');}};
  const gateway=new MobileGateway({mode:'lan',upstream:dsh.origin,upstreamSession:session,instance:identityFrom(createIdentity().privateKey),passwordHash:hashPassword('secure-password'),port:0});
  await gateway.start();t.after(()=>gateway.stop());
  const base=`http://127.0.0.1:${gateway.port}`;
  const auth=await fetch(`${base}/_dsh_mobile/v1/login`,{method:'POST',headers:{'Content-Type':'application/json'},body:'{"password":"secure-password"}'});
  const token=(await auth.json()).token;
  const res=await fetch(`${base}/api/foo`,{headers:{Authorization:`Bearer ${token}`}});
  assert.equal(res.status,502);assert.deepEqual(await res.json(),{error:'dsh_upstream_auth_unavailable'});
  assert.equal(dsh.requests,0);
});
test('gateway does not expose DSH browser-auth cookie in Set-Cookie responses',async t=>{
  const server=http.createServer((req,res)=>{
    if(req.url.startsWith('/?token=')){
      res.writeHead(303,{'Set-Cookie':'dsh-auth-test=signed; Path=/; HttpOnly; Max-Age=900'});return res.end();
    }
    res.writeHead(200,{'Set-Cookie':['dsh-auth-test=secret; Path=/; HttpOnly','theme=dark; Path=/']});res.end('ok');
  });
  await new Promise(ok=>server.listen(0,'127.0.0.1',ok));t.after(()=>new Promise(ok=>server.close(ok)));
  const origin=`http://127.0.0.1:${server.address().port}`;
  const upstreamSession=new UpstreamBrowserSession({upstream:origin,authenticatedUrl:base=>base+'?token=a'});
  const gateway=new MobileGateway({mode:'lan',upstream:origin,upstreamSession,instance:identityFrom(createIdentity().privateKey),passwordHash:hashPassword('secure-password'),port:0});
  await gateway.start();t.after(()=>gateway.stop());
  const base=`http://127.0.0.1:${gateway.port}`;
  const login=await fetch(base+'/_dsh_mobile/v1/login',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"password":"secure-password"}'});
  const token=(await login.json()).token;
  const response=await fetch(base+'/api/cookie',{headers:{Authorization:`Bearer ${token}`}});
  assert.equal(response.status,200);
  const cookies=response.headers.get('set-cookie')||'';
  assert.match(cookies,/theme=dark/);
  assert.doesNotMatch(cookies,/dsh-auth-/);
});
test('DSH session bootstrap is de-duplicated under concurrent gateway requests',async t=>{
  const dsh=await fakeDSH(t);const {base,token}=await testGateway(t,dsh);
  const responses=await Promise.all(Array.from({length:12},(_,i)=>fetch(`${base}/api/remote/${i}`,{headers:{Authorization:`Bearer ${token}`}})));
  assert.ok(responses.every(res=>res.status===200));
  assert.equal(dsh.bootstraps,1);
});
test('logging out revokes already-open DSH WebSocket streams',async t=>{
  const host=http.createServer((req,res)=>{
    if(req.url.startsWith('/?token=')) {res.writeHead(303,{'Set-Cookie':'dsh-auth-test=ok; Max-Age=3600'});return res.end();}
    res.end('ok');
  });
  const upstreamClosed={value:false};
  let upstreamSocket;
  host.on('upgrade',(_req,socket)=>{
    upstreamSocket=socket;
    socket.on('close',()=>{upstreamClosed.value=true;});
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: example\r\n\r\n');
  });
  await new Promise(ok=>host.listen(0,'127.0.0.1',ok));
  t.after(()=>{upstreamSocket?.destroy();host.closeAllConnections?.();host.close();});
  const origin=`http://127.0.0.1:${host.address().port}`;
  const session=new UpstreamBrowserSession({upstream:origin,authenticatedUrl:base=>base+'?token=hidden'});
  const gateway=new MobileGateway({mode:'lan',upstream:origin,upstreamSession:session,instance:identityFrom(createIdentity().privateKey),passwordHash:hashPassword('secure-password'),port:0});
  await gateway.start();t.after(()=>gateway.stop());
  const base=`http://127.0.0.1:${gateway.port}`;
  const login=await fetch(base+'/_dsh_mobile/v1/login',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"password":"secure-password"}'});
  const token=(await login.json()).token;
  const socket=connect(gateway.port,'127.0.0.1');await once(socket,'connect');
  socket.write(`GET /api/remote.mux HTTP/1.1\r\nHost: 127.0.0.1:${gateway.port}\r\nAuthorization: Bearer ${token}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n`);
  const handshake=await new Promise((resolve,reject)=>{
    let result='';socket.on('data',buf=>{result+=buf.toString();if(result.includes('\r\n\r\n'))resolve(result);});socket.once('error',reject);
  });
  assert.match(handshake,/^HTTP\/1\.1 101/);
  const closed=once(socket,'close');
  const logout=await fetch(base+'/_dsh_mobile/v1/logout',{method:'POST',headers:{Authorization:`Bearer ${token}`}});
  assert.equal(logout.status,200);
  await Promise.race([closed,new Promise((_resolve,reject)=>setTimeout(()=>reject(new Error('WebSocket did not close on logout')),1200))]);
  assert.equal(gateway.socketSessions.has(token),false);
  assert.equal(gateway.sessions.has(token),false);
});
