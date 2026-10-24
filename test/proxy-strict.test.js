import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {once} from 'node:events';
import {connect} from 'node:net';
import {MobileGateway} from '../lib/gateway.js';
import {createIdentity, identityFrom, hashPassword} from '../lib/security.js';

async function fixture(t) {
  const calls=[];
  const host=http.createServer((req,res)=>{
    calls.push(`${req.method} ${req.url}`);
    if(req.url==='/redirect-to-host') {
      res.writeHead(302,{Location:`http://127.0.0.1:${host.address().port}/api/safe`});res.end();return;
    }
    if(req.url==='/redirect-to-localhost') {
      res.writeHead(302,{Location:`http://localhost:${host.address().port}/api/safe`});res.end();return;
    }
    if(req.url==='/redirect-to-different-loopback') {
      res.writeHead(302,{Location:'http://127.0.0.1:3080/api/unsafe'});res.end();return;
    }
    if(req.url==='/redirect-to-external') {
      res.writeHead(302,{Location:'https://example.org/public'});res.end();return;
    }
    if(req.url==='/api/not-registered') {
      res.writeHead(404,{'Content-Type':'application/json'});res.end('{"code":"unknown_endpoint"}');return;
    }
    if(req.url==='/api/sse') {
      res.writeHead(200,{'Content-Type':'text/event-stream'});res.write('data: gateway-stream-ok\n\n');res.end();return;
    }
    if(req.url==='/api/binary') {
      res.writeHead(206,{'Content-Type':'application/octet-stream','Content-Range':'bytes 0-3/8'});
      res.end(Buffer.from([0,1,254,255]));return;
    }
    if(req.url==='/api/multipart') {
      res.writeHead(200,{'Content-Type':'multipart/mixed; boundary="test-boundary"'});
      res.end('--test-boundary\r\nContent-Type: application/json\r\n\r\n{"ok":true}\r\n--test-boundary--');return;
    }
    if(req.url==='/api/upload') {
      let data=Buffer.alloc(0);
      req.on('data',part=>data=Buffer.concat([data,part]));
      req.on('end',()=>{res.writeHead(201,{'Content-Type':'application/octet-stream'});res.end(data);});return;
    }
    res.writeHead(200,{'Content-Type':'application/json'});
    res.end(JSON.stringify({ok:true,path:req.url,method:req.method}));
  });
  host.on('upgrade',(req,socket)=>{
    calls.push(`WS ${req.url}`);
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: fake\r\n\r\n');
    setTimeout(()=>socket.end(),30);
  });
  await new Promise(ok=>host.listen(0,'127.0.0.1',ok));
  t.after(()=>new Promise(ok=>host.close(ok)));
  const id=identityFrom(createIdentity().privateKey);
  const gateway=new MobileGateway({mode:'lan',upstream:`http://127.0.0.1:${host.address().port}`,instance:id,passwordHash:hashPassword('secure-password'),port:0});
  await gateway.start();
  t.after(()=>gateway.stop());
  const url=`http://127.0.0.1:${gateway.port}`;
  const login=await fetch(`${url}/_dsh_mobile/v1/login`,{method:'POST',headers:{'content-type':'application/json'},body:'{"password":"secure-password"}'});
  assert.equal(login.status,200);
  const token=(await login.json()).token;
  const headers={authorization:`Bearer ${token}`};
  return {host,gateway,url,headers,calls,id};
}

function assertThroughGateway(response,url,id) {
  assert.equal(new URL(response.url).origin,url,'requested response must come from gateway origin');
  assert.equal(response.headers.get('x-dsh-mobile-gateway'),id.id,'gateway must stamp proxied responses');
}

test('strict proxy positive request matrix: GET, POST, PUT, PATCH, DELETE, OPTIONS, HEAD',async t=>{
  const f=await fixture(t);
  for(const method of ['GET','POST','PUT','PATCH','DELETE','OPTIONS','HEAD']) {
    const response=await fetch(`${f.url}/api/echo-${method.toLowerCase()}`,{
      method,headers:{...f.headers,...(['POST','PUT','PATCH'].includes(method)?{'content-type':'application/json'}:{})},
      ...(['POST','PUT','PATCH'].includes(method)?{body:JSON.stringify({operation:method})}:{}) ,redirect:'manual'
    });
    assert.equal(response.status,200,method);
    assertThroughGateway(response,f.url,f.id);
    if(method!=='HEAD')assert.equal((await response.json()).method,method);
  }
  assert.equal(f.calls.length,7,'all method requests must reach Host through plugin');
});

test('stream, exact binary bytes, multipart envelope and upload are proxied without direct Host fallback',async t=>{
  const f=await fixture(t);
  let res=await fetch(f.url+'/api/sse',{headers:f.headers,redirect:'manual'});
  assertThroughGateway(res,f.url,f.id);
  assert.match(res.headers.get('content-type'),/text\/event-stream/);
  assert.match(await res.text(),/gateway-stream-ok/);
  res=await fetch(f.url+'/api/binary',{headers:{...f.headers,range:'bytes=0-3'},redirect:'manual'});
  assertThroughGateway(res,f.url,f.id);
  assert.equal(res.status,206);
  assert.deepEqual(Buffer.from(await res.arrayBuffer()),Buffer.from([0,1,254,255]));
  res=await fetch(f.url+'/api/multipart',{headers:f.headers,redirect:'manual'});
  assertThroughGateway(res,f.url,f.id);
  assert.match(res.headers.get('content-type'),/multipart\/mixed/);
  assert.match(await res.text(),/test-boundary/);
  const upload=Buffer.from([0,255,100,16,3]);
  res=await fetch(f.url+'/api/upload',{method:'POST',headers:{...f.headers,'content-type':'application/octet-stream'},body:upload,redirect:'manual'});
  assertThroughGateway(res,f.url,f.id);
  assert.equal(res.status,201);
  assert.deepEqual(Buffer.from(await res.arrayBuffer()),upload);
});

test('upstream host redirects are rewritten to gateway or rejected, never sent to default 3080',async t=>{
  const f=await fixture(t);
  for(const path of ['/redirect-to-host','/redirect-to-localhost']) {
    const response=await fetch(f.url+path,{headers:f.headers,redirect:'manual'});
    assertThroughGateway(response,f.url,f.id);
    assert.equal(response.status,302);
    assert.equal(response.headers.get('location'),'/api/safe');
    // Even when a client follows the relative redirect, it stays on the gateway.
    const follow=await fetch(new URL(response.headers.get('location'),f.url),{headers:f.headers,redirect:'manual'});
    assertThroughGateway(follow,f.url,f.id);
    assert.equal(follow.status,200);
  }
  const blocked=await fetch(f.url+'/redirect-to-different-loopback',{headers:f.headers,redirect:'manual'});
  assert.equal(blocked.status,502);
  assertThroughGateway(blocked,f.url,f.id);
  assert.deepEqual(await blocked.json(),{error:'upstream_direct_redirect_blocked'});
  const external=await fetch(f.url+'/redirect-to-external',{headers:f.headers,redirect:'manual'});
  assert.equal(external.status,302);
  assertThroughGateway(external,f.url,f.id);
});

test('negative test: nonexistent DSH API 404 does not count as an API pass',async t=>{
  const f=await fixture(t);
  const result=await fetch(f.url+'/api/not-registered',{headers:f.headers,redirect:'manual'});
  assertThroughGateway(result,f.url,f.id);
  assert.equal(result.status,404);
  assert.equal((await result.json()).code,'unknown_endpoint');
  // Strict test runners MUST use a known-positive endpoint with verified semantics.
  assert.notEqual(result.status,200);
});

test('negative test: Host can work while gateway is stopped, but proxy assertions must fail',async t=>{
  const f=await fixture(t);
  const upstreamURL=`http://127.0.0.1:${f.host.address().port}/api/check`;
  const hostOK=await fetch(upstreamURL);
  assert.equal(hostOK.status,200,'control: direct Host is healthy');
  assert.equal(hostOK.headers.get('x-dsh-mobile-gateway'),null,'direct Host has no gateway proof');
  await f.gateway.stop();
  await assert.rejects(()=>fetch(f.url+'/api/check',{headers:f.headers,signal:AbortSignal.timeout(2000)}));
});

test('WebSocket handshake through gateway carries proof; raw Host 101 alone is not sufficient',async t=>{
  const f=await fixture(t);
  const sock=connect(f.gateway.port,'127.0.0.1');await once(sock,'connect');
  const response=new Promise((resolve,reject)=>{
    let data='';const timer=setTimeout(()=>reject(Error('WS response timed out')),1200);
    sock.on('data',b=>{data+=b.toString();if(data.includes('\r\n\r\n')){clearTimeout(timer);resolve(data);}});
    sock.on('error',reject);
  });
  sock.write(`GET /api/remote.mux HTTP/1.1\r\nHost: 127.0.0.1:${f.gateway.port}\r\nAuthorization: ${f.headers.authorization}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n`);
  const data=await response;sock.destroy();
  assert.match(data,/^HTTP\/1\.1 101 Switching Protocols/);
  assert.match(data,new RegExp(`x-dsh-mobile-gateway: ${f.id.id}`,'i'));
  assert.ok(f.calls.includes('WS /api/remote.mux'));
});
