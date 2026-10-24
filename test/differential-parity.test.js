import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import net from 'node:net';
import {createHash, randomBytes} from 'node:crypto';
import {mkdtemp, writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {MobileGateway} from '../lib/gateway.js';
import {createIdentity, identityFrom, hashPassword} from '../lib/security.js';

function readBody(req) {return new Promise((resolve,reject)=>{const chunks=[];req.on('data',c=>chunks.push(c));req.on('end',()=>resolve(Buffer.concat(chunks)));req.on('error',reject);});}

async function fixture(t){
  const requests=[];
  const liveSockets=new Set();
  const host=http.createServer(async(req,res)=>{
    const body=await readBody(req);
    requests.push({url:req.url,method:req.method,body,headers:req.headers});
    if(!req.headers.cookie?.includes('dsh-auth-live=host-cookie')){res.writeHead(401,{'Content-Type':'application/json'});res.end('{"error":"host_auth_required"}');return;}
    const url=new URL(req.url,'http://host.test');
    if(url.pathname==='/redirect'){res.writeHead(307,{Location:`http://127.0.0.1:${host.address().port}/api/destination?key=%2B`});res.end('move');return;}
    if(url.pathname==='/api/stream'){
      res.writeHead(200,{'Content-Type':'text/event-stream','Cache-Control':'no-cache','X-Request-Check':'stream'});
      res.write('event: status\ndata: {"ok":1}\n\n');
      setTimeout(()=>res.end('event: done\ndata: {"ok":2}\n\n'),10);return;
    }
    if(url.pathname==='/api/bytes'){
      res.writeHead(206,{'Content-Type':'application/octet-stream','Content-Range':'bytes 3-8/11','ETag':'"test-tag"'});
      res.end(Buffer.from([0,255,10,13,42,127]));return;
    }
    if(url.pathname==='/api/error'){
      res.writeHead(422,{'Content-Type':'application/json','X-Request-Check':'error'});
      res.end('{"code":"INVALID_INPUT","meta":{"a":2}}');return;
    }
    if(url.pathname==='/api/not-found'){
      res.writeHead(404,{'Content-Type':'application/json'});res.end('{"error":"not_found"}');return;
    }
    if(url.pathname==='/api/none'){
      res.writeHead(204,{'X-Request-Check':'none'});res.end();return;
    }
    res.writeHead(req.method==='POST'?201:200,{'Content-Type':'application/json','X-Request-Check':'echo'});
    res.end(JSON.stringify({url:req.url,method:req.method,body:body.toString('base64'),mime:req.headers['content-type']||'',custom:req.headers['x-custom']||''}));
  });
  host.on('connection',socket=>{liveSockets.add(socket);socket.once('close',()=>liveSockets.delete(socket));});
  host.on('upgrade',(req,socket)=>{
    if(req.url.startsWith('/api/ws-deny')){
      const body='{"type":"websocket_denied","retry":false}';
      socket.end(`HTTP/1.1 403 Forbidden\r\nContent-Type: application/json\r\nContent-Length: ${Buffer.byteLength(body)}\r\nX-WS-Error: denied\r\nConnection: close\r\n\r\n${body}`);return;
    }
    if(!req.headers.cookie?.includes('dsh-auth-live=host-cookie')){socket.end('HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n');return;}
    const accept=createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\nX-WS-Transport: dsh\r\n\r\n`);
    socket.on('data',data=>{
      if(data.length<6)return;
      // Decode one masked, short text frame and reply with an unmasked echo.
      const n=data[1]&0x7f;const mask=data.subarray(2,6);const payload=data.subarray(6,6+n);
      const decoded=Buffer.from(payload.map((byte,i)=>byte^mask[i%4]));
      socket.write(Buffer.concat([Buffer.from([0x81,decoded.length]),decoded]));
    });
  });
  await new Promise(ok=>host.listen(0,'127.0.0.1',ok));t.after(async()=>{for(const sock of liveSockets)sock.destroy();await new Promise(ok=>host.close(ok));});
  const upstream=`http://127.0.0.1:${host.address().port}`;
  const gateway=new MobileGateway({mode:'lan',upstream,instance:identityFrom(createIdentity().privateKey),passwordHash:hashPassword('parity-password'),upstreamSession:{getCookie:async()=> 'dsh-auth-live=host-cookie',invalidate:()=>{}},port:0});
  await gateway.start();t.after(()=>gateway.stop());
  const proxy=`http://127.0.0.1:${gateway.port}`;
  const auth=await fetch(proxy+'/_dsh_mobile/v1/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:'parity-password'})});
  assert.equal(auth.status,200);
  const token=(await auth.json()).token;
  return {upstream,proxy,token,requests};
}

async function snapshot(url,{method='GET',body,headers={}}={}){
  const response=await fetch(url,{method,headers,body,redirect:'manual'});
  return {status:response.status,headers:response.headers,body:Buffer.from(await response.arrayBuffer())};
}

function wsRaw(url,path,headers={}){
  return new Promise((resolve,reject)=>{
    const target=new URL(url);const sock=net.connect(Number(target.port),'127.0.0.1');let data=Buffer.alloc(0),done=false;
    const timer=setTimeout(()=>fail(new Error('WebSocket parity timeout')),2500);
    function fail(e){if(done)return;done=true;clearTimeout(timer);sock.destroy();reject(e);}
    sock.on('error',fail);
    sock.on('data',chunk=>{
      data=Buffer.concat([data,chunk]);const end=data.indexOf('\r\n\r\n');if(end<0)return;
      const head=data.subarray(0,end).toString('latin1');const status=Number(/^HTTP\/1\.1 (\d+)/.exec(head)?.[1]);
      if(status!==101){
        const len=Number(/content-length:\s*(\d+)/i.exec(head)?.[1]||0);
        if(data.length<end+4+len)return;
        if(done)return;done=true;clearTimeout(timer);sock.destroy();
        resolve({status,headers:head.toLowerCase(),body:data.subarray(end+4,end+4+len)});return;
      }
      if(!sock.sent){
        sock.sent=true;const payload=Buffer.from('native-dsh-frame'),mask=randomBytes(4);
        const frame=Buffer.concat([Buffer.from([0x81,0x80|payload.length]),mask,Buffer.from(payload.map((x,i)=>x^mask[i%4]))]);
        sock.write(frame);
      }
      if(data.length>=end+4+2+Buffer.byteLength('native-dsh-frame')){
        const frame=data.subarray(end+4);
        if(done)return;done=true;clearTimeout(timer);sock.destroy();
        resolve({status,headers:head.toLowerCase(),body:frame.subarray(2,2+frame[1])});
      }
    });
    sock.on('connect',()=>{
      const key=randomBytes(16).toString('base64');
      sock.write(`GET ${path} HTTP/1.1\r\nHost: ${target.host}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Key: ${key}\r\nSec-WebSocket-Version: 13\r\n${Object.entries(headers).map(([k,v])=>`${k}: ${v}\r\n`).join('')}\r\n`);
    });
  });
}

test('DSH direct vs gateway parity: status, query, methods, request body, response bytes and semantic headers',async t=>{
  const {upstream,proxy,token,requests}=await fixture(t);
  const cases=[
    {path:'/api/remote/echo?token=native-api-token&value=%2B&value=%20'},
    {path:'/api/remote/echo?encoded=%E6%B5%8B%E8%AF%95&empty=&n=1',method:'POST',body:JSON.stringify({rpcId:5,method:'abc',payload:{x:2}}),headers:{'Content-Type':'application/json','X-Custom':'rpc'}},
    {path:'/api/upload?filename=foo%20bar',method:'PUT',body:Buffer.from([0,1,2,255,128,13]),headers:{'Content-Type':'application/octet-stream','X-Custom':'file'}},
    {path:'/api/remote/patch?version=3',method:'PATCH',body:'{"patch":true}',headers:{'Content-Type':'application/json'}},
    {path:'/api/delete?id=12',method:'DELETE'},
    {path:'/api/none'},
    {path:'/api/error'},
    {path:'/api/not-found'},
    {path:'/api/bytes',headers:{Range:'bytes=3-8'}},
    {path:'/api/stream'},
    {path:'/redirect'}
  ];
  for(const item of cases){
    const direct=await snapshot(upstream+item.path,{method:item.method,body:item.body,headers:{Cookie:'dsh-auth-live=host-cookie',...item.headers}});
    const via=await snapshot(proxy+item.path,{method:item.method,body:item.body,headers:{Authorization:`Bearer ${token}`,...item.headers}});
    assert.equal(via.status,direct.status,item.path+' status');
    assert.deepEqual(via.body,direct.body,item.path+' body bytes');
    for(const header of ['content-type','content-range','etag','cache-control','x-request-check']){
      assert.equal(via.headers.get(header),direct.headers.get(header),item.path+' header '+header);
    }
    assert.equal(via.headers.get('x-dsh-mobile-gateway')?.length,32,item.path+' proof');
    if(item.path==='/redirect'){
      assert.equal(via.headers.get('location'),'/api/destination?key=%2B','redirect remains on gateway');
      assert.equal(direct.headers.get('location'),upstream+'/api/destination?key=%2B');
    }else assert.equal(via.headers.get('location'),direct.headers.get('location'));
    const lastTwo=requests.slice(-2);
    assert.equal(lastTwo.length,2);
    assert.equal(lastTwo[0].url,lastTwo[1].url,'host receives identical raw URL');
    assert.equal(lastTwo[0].method,lastTwo[1].method,'host receives identical method');
    assert.deepEqual(lastTwo[0].body,lastTwo[1].body,'host receives identical request body');
    assert.equal(lastTwo[0].headers['content-type'],lastTwo[1].headers['content-type']);
    assert.equal(lastTwo[0].headers['x-custom'],lastTwo[1].headers['x-custom']);
  }
});

test('WebSocket direct vs gateway parity: successful duplex frame and rejected handshake body',async t=>{
  const {upstream,proxy,token}=await fixture(t);
  const direct=await wsRaw(upstream,'/api/remote.mux',{Cookie:'dsh-auth-live=host-cookie'});
  const via=await wsRaw(proxy,'/api/remote.mux',{Authorization:`Bearer ${token}`});
  assert.equal(via.status,direct.status);
  assert.deepEqual(via.body,direct.body);
  assert.match(via.headers,/x-dsh-mobile-gateway: [a-f0-9]{32}/);
  assert.match(via.headers,/x-ws-transport: dsh/);
  const deniedHost=await wsRaw(upstream,'/api/ws-deny',{Cookie:'dsh-auth-live=host-cookie'});
  const deniedProxy=await wsRaw(proxy,'/api/ws-deny',{Authorization:`Bearer ${token}`});
  assert.equal(deniedProxy.status,403);
  assert.equal(deniedProxy.status,deniedHost.status);
  assert.deepEqual(deniedProxy.body,deniedHost.body);
  assert.match(deniedProxy.headers,/x-ws-error: denied/);
});


test('real endpoint differential auditor compares both ports, checks frames, and rejects false positives',async t=>{
  const {upstream,proxy}=await fixture(t);
  const temp=await mkdtemp(join(tmpdir(),'dsh-parity-'));
  t.after(()=>rm(temp,{recursive:true,force:true}));
  const manifestFile=join(temp,'manifest.json'),report=join(temp,'report.json');
  const base={sourceRevision:'fake-host-test-commit',declaredCount:3,interfaces:[
    {id:'echo',kind:'http',path:'/api/echo?token=DSH-API-TOKEN&value=%2B',expectStatus:200},
    {id:'binary',kind:'http',path:'/api/bytes',expectStatus:206},
    {id:'ws-stream',kind:'websocket',path:'/api/remote.mux',expectStatus:101,exchange:{payloadBase64:Buffer.from('native-dsh-frame').toString('base64'),expectFrames:1}}
  ]};
  const run=()=>promisify(execFile)(process.execPath,['scripts/compare-direct-proxy.mjs',manifestFile,report],{
    cwd:new URL('..',import.meta.url).pathname,
    env:{...process.env,DSH_DIRECT_URL:upstream,DSH_MOBILE_GATEWAY_URL:proxy,DSH_DIRECT_COOKIE:'dsh-auth-live=host-cookie',DSH_MOBILE_TEST_PASSWORD:'parity-password'},
    timeout:9000,encoding:'utf8'
  });
  await writeFile(manifestFile,JSON.stringify(base));
  assert.match((await run()).stdout,/3\/3/);
  const result=JSON.parse(await readFile(report,'utf8'));
  assert.equal(result.passedCount,3);assert.equal(result.realInterfaceInventoryVerified,false);
  base.interfaces[0].path='/api/not-found';
  await writeFile(manifestFile,JSON.stringify(base));
  await assert.rejects(run(),'a matching 404 must not be mistaken for successful native API');
  const fail=JSON.parse(await readFile(report,'utf8'));
  assert.equal(fail.failedCount,1);
});
