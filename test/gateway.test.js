import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { once } from 'node:events';
import { connect } from 'node:net';
import { MobileGateway } from '../lib/gateway.js';
import { createIdentity, hashPassword, identityFrom } from '../lib/security.js';

async function upstream() {
  const server=http.createServer((req,res)=>{
    if(req.url==='/api/echo'){
      let text='';req.on('data',x=>text+=x);req.on('end',()=>{
        res.writeHead(200,{'Content-Type':'application/json'});
        res.end(JSON.stringify({method:req.method,host:req.headers.host,origin:req.headers.origin,cookie:req.headers.cookie||'',auth:req.headers.authorization||'',data:text}));
      });
    }else{res.end('DSH page');}
  });
  server.on('upgrade',(req,sock)=>{sock.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: test\r\n\r\n');sock.end();});
  await new Promise(ok=>server.listen(0,'127.0.0.1',ok));
  return {server,port:server.address().port};
}
async function fixture(t,mode='lan') {
  const u=await upstream();t.after(()=>new Promise(r=>u.server.close(r)));
  const key=identityFrom(createIdentity().privateKey);
  const gateway=new MobileGateway({mode,upstream:`http://127.0.0.1:${u.port}`,instance:key,passwordHash:hashPassword('secure-password'),port:0});
  await gateway.start();t.after(()=>gateway.stop());
  return {gateway,host:`http://127.0.0.1:${gateway.port}`, upstreamPort:u.port};
}
async function login(host,password='secure-password'){
  return fetch(host+'/_dsh_mobile/v1/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password})});
}
test('unauthenticated API denied, info signed, password login works',async t=>{
  const {host}=await fixture(t);
  let res=await fetch(host+'/api/echo');assert.equal(res.status,401);
  res=await fetch(host+'/_dsh_mobile/v1/info');const info=await res.json();
  assert.equal(info.protocol,'dsh-mobile/1');assert.ok(info.signature);assert.ok(info.publicKey);
  res=await login(host,'wrong');assert.equal(res.status,401);
  res=await login(host);assert.equal(res.status,200);
  const user=await res.json();assert.ok(user.token.length>=40);
  assert.match(res.headers.get('set-cookie'),/HttpOnly/);
  res=await fetch(host+'/api/echo',{headers:{Authorization:`Bearer ${user.token}`}});
  const echoed=await res.json();assert.equal(res.status,200);assert.equal(echoed.auth,'');
});
test('authenticated POST is transparently proxied with rewritten headers',async t=>{
  const {host,upstreamPort}=await fixture(t);
  const token=(await (await login(host)).json()).token;
  const res=await fetch(host+'/api/echo',{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'text/plain',Cookie:'dsh_mobile_session=x; dsh_user=ok','Origin':host},body:'hello DSH'});
  assert.equal(res.status,200);
  const data=await res.json();
  assert.equal(data.data,'hello DSH');assert.equal(data.cookie,'dsh_user=ok');
  assert.equal(data.host,`127.0.0.1:${upstreamPort}`);assert.equal(data.origin,`http://127.0.0.1:${upstreamPort}`);
});
test('origin mismatch, bad password attempt limit, disabled routes',async t=>{
  const {host}=await fixture(t);
  const res=await fetch(host+'/_dsh_mobile/v1/login',{method:'POST',headers:{Origin:'https://evil.example','Content-Type':'application/json'},body:'{"password":"secure-password"}'});
  assert.equal(res.status,403);
  for(let i=0;i<8;i++)assert.equal((await login(host,'incorrect')).status,401);
  assert.equal((await login(host,'incorrect')).status,429);
  assert.equal((await fetch(host+'/_dsh_mobile/v1/unknown')).status,404);
});
test('password rotation invalidates old sessions',async t=>{
  const {gateway,host}=await fixture(t);
  const token=(await (await login(host)).json()).token;
  assert.equal((await fetch(host+'/api/echo',{headers:{Authorization:`Bearer ${token}`}})).status,200);
  gateway.setPasswordHash(hashPassword('new-password'));
  assert.equal((await fetch(host+'/api/echo',{headers:{Authorization:`Bearer ${token}`}})).status,401);
  assert.equal((await login(host,'secure-password')).status,401);
  assert.equal((await login(host,'new-password')).status,200);
});
test('websocket upgrade requires a valid mobile session',async t=>{
  const {host,gateway}=await fixture(t);
  const token=(await (await login(host)).json()).token;
  async function raw(cookie){
    const sock=connect(gateway.port,'127.0.0.1');await once(sock,'connect');
    const output=new Promise(resolve=>{let result='';sock.on('data',d=>result+=d.toString());sock.once('end',()=>resolve(result));sock.on('error',()=>resolve(result));});
    sock.write(`GET /api/remote.mux HTTP/1.1\r\nHost: 127.0.0.1:${gateway.port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n${cookie?`Cookie: dsh_mobile_session=${token}\r\n`:''}\r\n`);
    return output;
  }
  assert.match(await raw(false),/^HTTP\/1.1 401/);
  assert.match(await raw(true),/^HTTP\/1.1 101/);
});

test('authenticated mobile gateway cannot forward internal DSH Mobile admin paths',async t=>{
  const {host}=await fixture(t);
  const token=(await (await login(host)).json()).token;
  for(const path of ['/dsh-mobile/admin/status','/%64sh-mobile/admin/status','/dsh-mobile/admin/configure']){
    const res=await fetch(host+path,{headers:{Authorization:`Bearer ${token}`}});
    assert.equal(res.status,403,path);
  }
});
