import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawn} from 'node:child_process';
import {MobileGateway} from '../lib/gateway.js';
import {createIdentity, identityFrom, hashPassword} from '../lib/security.js';

const script=new URL('../scripts/audit-gateway-only.mjs',import.meta.url).pathname;
async function fixture(t) {
  const host=http.createServer((req,res)=>{
    if(req.url==='/api/valid'){res.writeHead(200,{'content-type':'application/json'});res.end('{"real":true,"source":"host"}');}
    else if(req.url==='/api/missing'){res.writeHead(404,{'content-type':'application/json'});res.end('{"error":"not_found"}');}
    else {res.writeHead(200,{'content-type':'text/html'});res.end('<html>SPA shell</html>');}
  });
  await new Promise(ok=>host.listen(0,'127.0.0.1',ok));
  t.after(()=>new Promise(ok=>host.close(ok)));
  const gateway=new MobileGateway({mode:'lan',upstream:`http://127.0.0.1:${host.address().port}`,instance:identityFrom(createIdentity().privateKey),passwordHash:hashPassword('secure-password'),port:0});
  await gateway.start();t.after(()=>gateway.stop());
  const dir=await mkdtemp(join(tmpdir(),'dsh-mobile-audit-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  return {gateway,host,dir};
}
async function execute(f,interfaces,extras={}) {
  const manifest=join(f.dir,'manifest.json');
  await writeFile(manifest,JSON.stringify({sourceRevision:'synthetic-test',declaredCount:interfaces.length,interfaces,...extras}));
  const env={...process.env,DSH_MOBILE_GATEWAY_URL:`http://127.0.0.1:${f.gateway.port}`,DSH_MOBILE_TEST_PASSWORD:'secure-password'};
  return new Promise((resolve,reject)=>{
    const child=spawn(process.execPath,[script,manifest,join(f.dir,'report.json')],{env});
    let output=''; child.stdout.on('data',b=>output+=b); child.stderr.on('data',b=>output+=b);
    child.once('error',reject);child.once('close',code=>resolve({code,output}));
  });
}
test('full manifest-only audit passes for positive semantic API via gateway',async t=>{
  const f=await fixture(t);
  const res=await execute(f,[{id:'real',kind:'http',method:'GET',path:'/api/valid',expect:{status:200,contentType:'application/json',bodyContains:'"real":true'}}]);
  assert.equal(res.code,0,res.output);
  assert.match(res.output,/"passedCount": 1/);
});
test('full manifest-only audit rejects nonexistent 404 endpoint even though Host is alive',async t=>{
  const f=await fixture(t);
  assert.equal((await fetch(`http://127.0.0.1:${f.host.address().port}/api/valid`)).status,200,'Host itself works');
  const res=await execute(f,[{id:'not-real',kind:'http',method:'GET',path:'/api/missing',expect:{status:200,contentType:'application/json'}}]);
  assert.equal(res.code,1,res.output);
  assert.match(res.output,/预期 HTTP 200，实际 404/);
});
test('full manifest-only audit refuses 200 HTML SPA fallback as successful API',async t=>{
  const f=await fixture(t);
  const res=await execute(f,[{id:'fake',kind:'http',method:'GET',path:'/api/shell',expect:{status:200,minimumBytes:1}}]);
  assert.equal(res.code,1,res.output);
  assert.match(res.output,/API 返回了 HTML/);
});
test('full manifest-only audit fails closed on incomplete manifest',async t=>{
  const f=await fixture(t);
  const res=await execute(f,[{id:'real',kind:'http',path:'/api/valid',expect:{status:200,contentType:'application/json'}}],{declaredCount:2});
  assert.notEqual(res.code,0,res.output);
  assert.match(res.output,/接口清单不完整/);
});
