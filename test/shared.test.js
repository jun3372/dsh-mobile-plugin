import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { EventEmitter } from 'node:events';
import { MobileService } from '../lib/service.js';
import { createIdentity, checkPassword, hashPassword } from '../lib/security.js';
import { initialSettings } from '../lib/settings.js';

class FakeTunnel extends EventEmitter {
  constructor(){super();this.state='stopped';this.error='';this.url='';this.launches=[];}
  async start(opts){this.launches.push(opts);this.state='online';this.url='https://test.trycloudflare.com';}
  stop(){this.state='stopped';this.url='';}
  snapshot(){return {state:this.state,error:this.error,url:this.url};}
}
async function fixture(t){
  const dir=await mkdtemp(join(tmpdir(),'dsh-shared-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const file=join(dir,'settings.json');const tunnel=new FakeTunnel();
  const s=new MobileService({file,tunnel,logger:{warn(){}}});await s.init();t.after(()=>s.stop());
  return {s,file,tunnel};
}
test('LAN and public use ONE TCP listener and tunnel origin matches LAN port',async t=>{
  const {s,tunnel}=await fixture(t);
  let st=await s.configure('lan',{enabled:true,port:0});
  const sharedPort=st.lan.port;
  assert.ok(sharedPort>0);assert.equal(st.public.port,sharedPort);
  st=await s.configure('public',{enabled:true});
  assert.equal(st.gateway.port,sharedPort);assert.equal(st.lan.port,st.public.port);
  assert.ok(tunnel.launches.length>=1);assert.equal(tunnel.launches.at(-1).originPort,sharedPort);
  assert.equal(st.public.url,'https://test.trycloudflare.com');
  assert.equal(s.gateway.server.address().port,sharedPort);
  assert.equal(s.gateway.requestMode({socket:{remoteAddress:'::ffff:127.0.0.1'},headers:{host:'192.168.1.4:1234'}}),'public');
  assert.equal(s.gateway.requestMode({socket:{remoteAddress:'192.168.1.80'},headers:{host:'evil.trycloudflare.com'}}),'lan');
  const publicPassword=st.public.visiblePassword;
  // Tests hitting 127.0.0.1 when public is on are classified as tunnel requests.
  const host=`http://127.0.0.1:${sharedPort}`;
  assert.equal((await fetch(host+'/_dsh_mobile/v1/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:st.lan.visiblePassword})})).status,401);
  assert.equal((await fetch(host+'/_dsh_mobile/v1/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:publicPassword})})).status,200);
  st=await s.configure('public',{enabled:false});
  assert.equal(st.lan.running,true);assert.equal(st.public.running,false);
  assert.equal((await fetch(host+'/_dsh_mobile/v1/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:st.lan.visiblePassword})})).status,200);
  assert.equal(st.gateway.port,sharedPort);
});
test('passwords survive save, public enable/disable and host restart, with explicit rotation only',async t=>{
  const {s,file}=await fixture(t);
  const first=await s.snapshot();
  await s.configure('lan',{enabled:true,port:0});
  await s.configure('public',{enabled:true});
  await s.configure('public',{enabled:false});
  let st=await s.snapshot();
  assert.equal(st.lan.visiblePassword,first.lan.visiblePassword);
  assert.equal(st.public.visiblePassword,first.public.visiblePassword);
  const fixed='12345abcde678';
  st=await s.configure('public',{passwordMode:'fixed',password:fixed});
  assert.equal(st.public.visiblePassword,fixed);
  await s.configure('public',{mode:'quick'});
  assert.equal((await s.snapshot()).public.visiblePassword,fixed);
  const onDisk=JSON.parse(await readFile(file,'utf8'));
  assert.ok(checkPassword(fixed,onDisk.public.hash));
  await s.stop();
  const next=new MobileService({file,tunnel:new FakeTunnel()});await next.init();t.after(()=>next.stop());
  assert.equal((await next.snapshot()).lan.visiblePassword,first.lan.visiblePassword);
  assert.equal((await next.snapshot()).public.visiblePassword,fixed);
  const before=(await next.snapshot()).lan.visiblePassword;
  st=await next.configure('lan',{rotatePassword:true});
  assert.notEqual(st.lan.visiblePassword,before);
  assert.equal((await next.configure('lan',{enabled:false})).lan.visiblePassword,st.lan.visiblePassword);
});
test('schema v1 migration rotates unverifiable random password once and preserves fixed hash',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'dsh-migrate-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const file=join(dir,'settings.json');const old=initialSettings();old.schema=1;delete old.gateway;
  old.lan.port=0;old.public.port=39082;
  old.lan.hash=hashPassword('old-random');old.public.passwordMode='fixed';old.public.hash=hashPassword('previous-fixed-password');
  delete old.lan.password;delete old.public.password;
  await writeFile(file,JSON.stringify(old));
  const s=new MobileService({file,tunnel:new FakeTunnel()});await s.init();t.after(()=>s.stop());
  let st=await s.snapshot();
  assert.equal(s.settings.gateway.port,0);
  assert.ok(st.gateway.port>0);
  assert.ok(st.lan.visiblePassword);assert.notEqual(st.lan.visiblePassword,'old-random');
  assert.equal(st.public.visiblePassword,null);assert.equal(st.public.passwordRecoveryRequired,true);
  assert.ok(checkPassword('previous-fixed-password',s.settings.public.hash));
  await s.configure('public',{password:'new-fixed-password'});
  st=await s.snapshot();assert.equal(st.public.visiblePassword,'new-fixed-password');
  assert.equal(st.public.passwordRecoveryRequired,false);
});

test('saving unchanged random password does not rehash or revoke existing sessions',async t=>{
  const {s}=await fixture(t);
  await s.configure('public',{enabled:false}); // loopback now uses LAN password
  let st=await s.configure('lan',{enabled:true,port:0});
  const oldHash=s.settings.lan.hash;
  const host=`http://127.0.0.1:${st.lan.port}`;
  const login=await fetch(host+'/_dsh_mobile/v1/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:st.lan.visiblePassword})});
  assert.equal(login.status,200);
  const token=(await login.json()).token;
  await s.configure('lan',{enabled:true,port:0,passwordMode:'random'});
  assert.equal(s.settings.lan.hash,oldHash);
  const response=await fetch(host+'/_dsh_mobile/v1/info',{headers:{Authorization:`Bearer ${token}`}});
  assert.equal(response.status,200);
  assert.equal(s.gateway.authorized({socket:{remoteAddress:'127.0.0.1'},headers:{authorization:`Bearer ${token}`}}),true);
});

test('restarting DSH restores enabled LAN/public connections; disabled networks stay disabled',async t=>{
  const {s,file}=await fixture(t);
  const first=await s.snapshot();
  assert.equal(first.lan.running,true);assert.equal(first.public.running,true);
  const password=first.public.visiblePassword;
  await s.stop();
  const tunnel2=new FakeTunnel();
  const restarted=new MobileService({file,tunnel:tunnel2,logger:{info(){},warn(){},error(){}}});
  await restarted.init();t.after(()=>restarted.stop());
  let status=await restarted.snapshot();
  assert.equal(status.lan.running,true);assert.equal(status.public.running,true);
  assert.equal(status.public.visiblePassword,password);
  assert.equal(tunnel2.launches.length,1);
  assert.equal(tunnel2.launches[0].originPort,status.gateway.port);
  await restarted.configure('public',{enabled:false});
  await restarted.stop();
  const tunnel3=new FakeTunnel();
  const disabled=new MobileService({file,tunnel:tunnel3,logger:{info(){},warn(){},error(){}}});
  await disabled.init();t.after(()=>disabled.stop());
  status=await disabled.snapshot();
  assert.equal(status.lan.running,true);assert.equal(status.public.running,false);
  assert.equal(tunnel3.launches.length,0);
});
