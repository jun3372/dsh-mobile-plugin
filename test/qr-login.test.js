import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { MobileGateway } from '../lib/gateway.js';
import { createIdentity, identityFrom, hashPassword } from '../lib/security.js';

async function fixture(t,{mode='lan',password='My Pass&+?#2026'}={}) {
  const received=[];
  const upstream=http.createServer((req,res)=>{
    received.push(req.url);
    res.writeHead(200,{'Content-Type':'application/json'});
    res.end(JSON.stringify({url:req.url,cookie:req.headers.cookie||''}));
  });
  await new Promise(ok=>upstream.listen(0,'127.0.0.1',ok));
  t.after(()=>new Promise(ok=>upstream.close(ok)));
  const gateway=new MobileGateway({mode,upstream:`http://127.0.0.1:${upstream.address().port}`,
    instance:identityFrom(createIdentity().privateKey),passwordHash:hashPassword(password),port:0});
  await gateway.start();t.after(()=>gateway.stop());
  return {gateway,host:`http://127.0.0.1:${gateway.port}`,received,password};
}

test('QR URL exchanges a password for a cookie, then redirects to a clean URL without forwarding the secret',async t=>{
  const {host,received,password}=await fixture(t);
  const scanned=await fetch(host+'?token='+encodeURIComponent(password),{redirect:'manual'});
  assert.equal(scanned.status,303);
  assert.equal(scanned.headers.get('location'),'/');
  assert.equal(scanned.headers.get('cache-control'),'no-store');
  assert.equal(scanned.headers.get('referrer-policy'),'no-referrer');
  const cookie=scanned.headers.get('set-cookie');
  assert.match(cookie,/^dsh_mobile_session=[\w-]{43}; Path=\/; HttpOnly/);
  assert.deepEqual(received,[],'QR entry must not reach the upstream at all');
  const page=await fetch(host+'/',{headers:{Cookie:cookie.split(';')[0]}});
  assert.equal(page.status,200);
  assert.deepEqual((await page.json()).url,'/');
  assert.deepEqual(received,['/']);
});

test('QR password and session stay separate; native login API remains functional',async t=>{
  const {host,password}=await fixture(t);
  const r=await fetch(host+'/_dsh_mobile/v1/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password})});
  assert.equal(r.status,200);assert.equal((await r.json()).token.length,43);
  assert.equal((await fetch(host+'?token=WRONG-PASSWORD',{redirect:'manual'})).status,401);
  assert.equal((await fetch(host+'/')).status,401);
});

test('QR secrets are blocked on other routes while ordinary DSH token parameters are preserved',async t=>{
  const {host,password,received}=await fixture(t);
  const boot=await fetch(host+'?token='+encodeURIComponent(password),{redirect:'manual'});
  const cookie=boot.headers.get('set-cookie').split(';')[0];
  for (const path of ['/api/remote.mux?token='+encodeURIComponent(password), '/?token=x&token=y', '/?token=x&next=/api', '/_dsh_mobile/v1/info?token=bad']) {
    const res=await fetch(host+path,{headers:{Cookie:cookie}});
    assert.equal(res.status,400,path);
  }
  assert.equal((await fetch(host+'?token='+encodeURIComponent(password),{method:'HEAD'})).status,400);
  const native=await fetch(host+'/api/stream?token=DSH-ordinary-token&x=%2B&x=two',{headers:{Cookie:cookie}});
  assert.equal(native.status,200);
  assert.equal((await native.json()).url,'/api/stream?token=DSH-ordinary-token&x=%2B&x=two');
  assert.deepEqual(received,['/api/stream?token=DSH-ordinary-token&x=%2B&x=two'],
    'only non-password native tokens may reach DSH');
});

test('QR password failure counts towards the same rate limit as JSON login, and rotation invalidates the link',async t=>{
  const {host,gateway,password}=await fixture(t);
  let scan=await fetch(host+'?token='+encodeURIComponent(password),{redirect:'manual'});
  assert.equal(scan.status,303);
  const oldCookie=scan.headers.get('set-cookie').split(';')[0];
  gateway.setPasswordHash(hashPassword('NewPassword987654'));
  assert.equal((await fetch(host+'/',{headers:{Cookie:oldCookie}})).status,401);
  assert.equal((await fetch(host+'?token='+encodeURIComponent(password),{redirect:'manual'})).status,401);
  for(let i=0;i<7;i++)assert.equal((await fetch(host+'?token=wrong',{redirect:'manual'})).status,401);
  assert.equal((await fetch(host+'?token=wrong',{redirect:'manual'})).status,429);
});

test('public-mode QR cookie is Secure and no secret is proxied before redirect',async t=>{
  const {host,password,received}=await fixture(t,{mode:'public'});
  const res=await fetch(host+'?token='+encodeURIComponent(password),{redirect:'manual'});
  assert.equal(res.status,303);assert.match(res.headers.get('set-cookie'),/__Host-dsh_mobile_session=/);
  assert.match(res.headers.get('set-cookie'),/; Secure/);
  assert.deepEqual(received,[]);
});
