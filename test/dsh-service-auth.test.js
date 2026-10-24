import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { EventEmitter } from 'node:events';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { MobileService } from '../lib/service.js';
import { initialSettings } from '../lib/settings.js';

class IdleTunnel extends EventEmitter {
  snapshot(){return {state:'stopped',url:'',error:''};}
  stop(){}
}
test('MobileService discovers the actual DSH web port and establishes upstream Host session', async t => {
  const dsh=http.createServer((req,res)=>{
    if(req.url.startsWith('/?token=')){
      res.writeHead(303,{'Set-Cookie':'dsh-auth-local=trusted; Path=/; Max-Age=86400',Location:'/'});return res.end();
    }
    if(req.url.startsWith('/api/') && !String(req.headers.cookie||'').includes('dsh-auth-local=trusted')){
      res.writeHead(401);return res.end('unauthorized');
    }
    res.writeHead(200,{'Content-Type':'application/json'});res.end('{"dsh":true}');
  });
  await new Promise(ok=>dsh.listen(0,'127.0.0.1',ok));
  t.after(()=>new Promise(ok=>dsh.close(ok)));
  const dir=await mkdtemp(join(tmpdir(),'dsh-mobile-real-auth-'));
  t.after(()=>rm(dir,{force:true,recursive:true}));
  const settings=initialSettings();settings.gateway.port=0;settings.public.enabled=false;settings.frpc.enabled=false;
  const file=join(dir,'settings.json');await writeFile(file,JSON.stringify(settings));
  const service=new MobileService({file,authenticatedUrl:base=>base+'?token=internal-only',
    upstreamResolver:()=>`http://127.0.0.1:${dsh.address().port}`,tunnel:new IdleTunnel(),logger:{info(){},warn(){},error(){}}});
  await service.init();t.after(()=>service.stop());
  const status=await service.snapshot();
  assert.equal(status.gateway.upstreamAuthenticated,true);
  assert.equal(status.gateway.running,true);
  const origin=`http://127.0.0.1:${status.gateway.port}`;
  const login=await fetch(origin+'/_dsh_mobile/v1/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:status.lan.visiblePassword})});
  assert.equal(login.status,200);
  const {token}=await login.json();
  const api=await fetch(origin+'/api/remote/basic',{headers:{Authorization:'Bearer '+token}});
  assert.equal(api.status,200);
  assert.deepEqual(await api.json(),{dsh:true});
  assert.equal(service.settings.upstream,`http://127.0.0.1:${dsh.address().port}`);
});
