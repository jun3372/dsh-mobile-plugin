import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, readFile, writeFile } from 'node:fs/promises';
import { EventEmitter } from 'node:events';
import { initialSettings } from '../lib/settings.js';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { MobileService } from '../lib/service.js';

class FakeTunnel extends EventEmitter {
  constructor(){super();this.state='stopped';this.url='';this.error='';this.launches=[];}
  async start(opts){this.launches.push(opts);this.state='online';this.url='https://demo.trycloudflare.com';this.emit('change');}
  stop(){this.state='stopped';this.url='';this.emit('change');}
  snapshot(){return {state:this.state,url:this.url,error:this.error};}
}
async function fixture(t){
  const dir=await mkdtemp(join(tmpdir(),'dsh-mobile-test-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const file=join(dir,'settings.json');const initial=initialSettings();initial.gateway.port=0;
  await writeFile(file,JSON.stringify(initial));
  const tunnel=new FakeTunnel();const s=new MobileService({file,tunnel,logger:{info(){},warn(){},error(){}}});
  await s.init();t.after(()=>s.stop());return {s,file,tunnel};
}
test('fresh install automatically starts LAN and public; identity and password persist safely',async t=>{
  const {s,file}=await fixture(t);const snapshot=await s.snapshot();
  assert.equal(snapshot.lan.enabled,true);assert.equal(snapshot.public.enabled,true);
  assert.equal(snapshot.lan.running,true);assert.equal(snapshot.public.running,true);
  assert.equal(snapshot.lan.autoStart,true);assert.equal(snapshot.public.autoStart,true);
  assert.ok(snapshot.lan.visiblePassword.length>=8);assert.ok(snapshot.instanceId);
  const settings=JSON.parse(await readFile(file,'utf8'));assert.ok(settings.identity.privateKey);assert.ok(settings.lan.hash.startsWith('scrypt:'));
  assert.equal(settings.lan.password,snapshot.lan.visiblePassword);assert.equal(settings.schema,2);
});
test('LAN gateway is controllable; fixed password can be viewed locally',async t=>{
  const {s}=await fixture(t);
  let st=await s.configure('lan',{enabled:true,port:0});assert.equal(st.lan.running,true);
  st=await s.configure('lan',{passwordMode:'fixed',password:'Abcdefgh9876'});
  assert.equal(st.lan.passwordMode,'fixed');assert.equal(st.lan.visiblePassword,'Abcdefgh9876');
  const resp=await fetch(`http://127.0.0.1:${st.lan.port}/_dsh_mobile/v1/info`);assert.equal(resp.status,200);
  st=await s.configure('lan',{enabled:false});assert.equal(st.lan.running,false);
});
test('invalid field or named config rejected without changing running services',async t=>{
  const {s}=await fixture(t);
  await assert.rejects(()=>s.configure('lan',{foo:'bar'}));
  await assert.rejects(()=>s.configure('public',{enabled:true,mode:'named'}));
  assert.equal((await s.snapshot()).public.running,true);
});

test('startup and configuration generate Chinese runtime status logs without credentials',async t=>{
  const {s}=await fixture(t);
  await s.configure('public',{enabled:false});
  const status=await s.snapshot();
  const lines=status.recentLogs.map(x=>x.message).join('\n');
  assert.match(lines,/正在启动插件/);assert.match(lines,/启动状态：局域网=运行中/);
  assert.match(lines,/局域网服务已启动/);
  assert.match(lines,/公网配置已保存/);
  assert.ok(status.recentLogs.every(x=>x.time&&['info','warn','error'].includes(x.level)));
  assert.ok(!lines.includes(status.lan.visiblePassword));
  assert.ok(!lines.includes(status.public.visiblePassword));
});

test('gateway temporarily fails on DSH startup then automatically retries and highlights running state',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'dsh-retry-test-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const file=join(dir,'settings.json');const initial=initialSettings();initial.gateway.port=0;
  await writeFile(file,JSON.stringify(initial));
  let count=0;
  const gatewayFactory=()=>({port:31415,bindAddress:'0.0.0.0',async start(){if(++count===1)throw new Error('EADDRINUSE');},async stop(){},setMode(){}});
  const s=new MobileService({file,gatewayFactory,tunnel:new FakeTunnel(),logger:{info(){},warn(){},error(){}}});
  s.gatewayRetryDelay=20;
  await s.init();t.after(()=>s.stop());
  assert.equal((await s.snapshot()).gateway.running,false);
  await new Promise(r=>setTimeout(r,100));
  const status=await s.snapshot();
  assert.equal(count,2);assert.equal(status.gateway.running,true);
  assert.equal(status.lan.running,true);assert.equal(status.public.running,true);
  assert.match(status.recentLogs.map(x=>x.message).join('\n'),/共享代理网关将在.*重试/);
});

test('Cloudflare startup failure schedules retry, then reports online',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'dsh-public-retry-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const file=join(dir,'settings.json');const initial=initialSettings();initial.gateway.port=0;
  await writeFile(file,JSON.stringify(initial));
  class TransientTunnel extends FakeTunnel {
    async start(opts){
      if(this.launches.length===0){this.launches.push(opts);this.state='error';this.error='临时离线';this.emit('change');throw new Error('临时离线');}
      return super.start(opts);
    }
  }
  const tunnel=new TransientTunnel();const s=new MobileService({file,tunnel,logger:{info(){},warn(){},error(){}}});
  s.retryDelay=20;await s.init();t.after(()=>s.stop());
  assert.equal((await s.snapshot()).public.running,false);
  await new Promise(r=>setTimeout(r,100));
  const status=await s.snapshot();
  assert.equal(status.public.running,true);
  assert.equal(tunnel.launches.length,2);
  assert.match(status.recentLogs.map(x=>x.message).join('\n'),/公网 Cloudflare 已连接/);
});

test('multiple LAN addresses expose a single preferred QR, persist selection and reject unknown addresses', async t => {
  const dir=await mkdtemp(join(tmpdir(),'dsh-ip-selection-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const file=join(dir,'settings.json');const initial=initialSettings();initial.gateway.port=0;initial.public.enabled=false;
  await writeFile(file,JSON.stringify(initial));
  let nic=[{interface:'Wi-Fi',address:'192.168.4.23'},{interface:'Ethernet',address:'10.1.4.8'}];
  const opts={file,tunnel:new FakeTunnel(),logger:{info(){},warn(){},error(){}},addressProvider:()=>nic};
  const service=new MobileService(opts);await service.init();t.after(()=>service.stop());
  let state=await service.snapshot();
  assert.equal(state.lan.selectedAddress,'192.168.4.23');
  assert.equal(state.lan.urls.length,2);
  assert.equal(state.lan.url,`http://192.168.4.23:${state.lan.port}`);
  await assert.rejects(()=>service.configure('lan',{preferredAddress:'8.8.8.8'}),/IP 不可用/);
  assert.equal((await service.snapshot()).lan.selectedAddress,'192.168.4.23');
  state=await service.configure('lan',{preferredAddress:'10.1.4.8'});
  assert.equal(state.lan.selectedAddress,'10.1.4.8');
  assert.equal(state.lan.url,`http://10.1.4.8:${state.lan.port}`);
  assert.equal((await service.qr('lan',state.lan.url)).payload,state.lan.url+'?token='+encodeURIComponent(state.base.lanPassword));
  const saved=JSON.parse(await readFile(file,'utf8'));
  assert.equal(saved.lan.preferredAddress,'10.1.4.8');
  // A disabled interface must not expose a stale QR, but the preference remains on disk.
  nic=[{interface:'Wi-Fi',address:'192.168.4.23'}];
  state=await service.snapshot();
  assert.equal(state.lan.selectedAddress,'192.168.4.23');
  assert.equal(state.lan.preferredAddress,'10.1.4.8');
  assert.ok(!state.lan.url.includes('10.1.4.8'));
  nic.push({interface:'Ethernet',address:'10.1.4.8'});
  assert.equal((await service.snapshot()).lan.selectedAddress,'10.1.4.8');
  await service.stop();
  const restarted=new MobileService({...opts,tunnel:new FakeTunnel()});
  await restarted.init();t.after(()=>restarted.stop());
  assert.equal((await restarted.snapshot()).lan.selectedAddress,'10.1.4.8');
  assert.equal((await restarted.snapshot()).lan.visiblePassword,saved.lan.password);
});

test('dev.4 settings without preferredAddress upgrade safely without rotating passwords',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'dsh-ip-migrate-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const file=join(dir,'settings.json');const settings=initialSettings();settings.gateway.port=0;
  delete settings.lan.preferredAddress;
  await writeFile(file,JSON.stringify(settings));
  const service=new MobileService({file,tunnel:new FakeTunnel(),logger:{info(){},warn(){},error(){}}});
  await service.init();t.after(()=>service.stop());
  assert.equal((await service.snapshot()).lan.preferredAddress,'');
  assert.equal(JSON.parse(await readFile(file,'utf8')).lan.preferredAddress,'');
  const pass=(await service.snapshot()).lan.visiblePassword;
  await service.stop();
  const service2=new MobileService({file,tunnel:new FakeTunnel(),logger:{info(){},warn(){},error(){}}});
  await service2.init();t.after(()=>service2.stop());
  assert.equal((await service2.snapshot()).lan.visiblePassword,pass);
});
test('download source is saved for both tunnels, old passwords remain and bad source is rejected',async t=>{
  const {s,file,tunnel}=await fixture(t);const before=await s.snapshot();
  let stat=await s.configure('public',{downloadSource:'ghfast'});
  assert.equal(stat.public.downloadSource,'ghfast');
  assert.equal(tunnel.launches.at(-1).downloadSource,'ghfast');
  stat=await s.configure('frpc',{downloadSource:'custom',downloadMirror:'https://mirror.example.com/'});
  assert.equal(stat.frpc.downloadSource,'custom');assert.equal(stat.frpc.downloadMirror,'https://mirror.example.com/');
  assert.equal(stat.lan.visiblePassword,before.lan.visiblePassword);
  assert.equal(stat.public.visiblePassword,before.public.visiblePassword);
  await assert.rejects(()=>s.configure('public',{downloadSource:'custom',downloadMirror:'http://localhost/'}),/HTTPS|加速/);
  const saved=JSON.parse(await readFile(file,'utf8'));
  assert.equal(saved.public.downloadSource,'ghfast');assert.equal(saved.frpc.downloadSource,'custom');
});
test('single password field can update LAN and public credentials without selecting a mode',async t=>{
  const {s}=await fixture(t);
  let stat=await s.configure('lan',{passwordMode:'fixed',password:'newLanPassword2026'});
  assert.equal(stat.lan.visiblePassword,'newLanPassword2026');
  stat=await s.configure('public',{passwordMode:'fixed',password:'newPublicPassword2026'});
  assert.equal(stat.public.visiblePassword,'newPublicPassword2026');
  assert.equal(stat.frpc.visiblePassword,'newPublicPassword2026');
});

test('base settings save both passwords atomically without changing tunnel enable flags',async t=>{
  const {s,file}=await fixture(t);
  const original=await s.snapshot();
  const lanPassword='LanSecurePass2468';
  const publicPassword='PublicSecurePass8642';
  const updated=await s.configure('base',{lanPassword,publicPassword});
  assert.equal(updated.base.lanPassword,lanPassword);
  assert.equal(updated.base.publicPassword,publicPassword);
  assert.equal(updated.lan.visiblePassword,lanPassword);
  assert.equal(updated.public.visiblePassword,publicPassword);
  assert.equal(updated.frpc.visiblePassword,publicPassword);
  assert.equal(updated.lan.enabled,original.lan.enabled);
  assert.equal(updated.public.enabled,original.public.enabled);
  assert.equal(updated.frpc.enabled,original.frpc.enabled);
  assert.equal(updated.gateway.port,original.gateway.port);
  const saved=JSON.parse(await readFile(file,'utf8'));
  assert.equal(saved.gateway.port,0);
  assert.equal(saved.lan.password,lanPassword);
  assert.equal(saved.public.password,publicPassword);
  await assert.rejects(()=>s.configure('base',{lanPassword:'AnotherValidPass123',publicPassword:'short'}));
  await assert.rejects(()=>s.configure('base',{port:-2}));
  await assert.rejects(()=>s.configure('base',{port:0}));
  await assert.rejects(()=>s.configure('base',{enabled:false}));
  const unchanged=await s.snapshot();
  assert.equal(unchanged.base.lanPassword,lanPassword);
  assert.equal(unchanged.base.publicPassword,publicPassword);
  assert.equal(s.settings.lan.password,lanPassword);
  assert.equal(s.settings.public.password,publicPassword);
});

test('changing a password through base settings revokes existing gateway authorization',async t=>{
  const {s}=await fixture(t);
  let st=await s.snapshot();
  const url=`http://127.0.0.1:${st.gateway.port}`;
  const login=await fetch(url+'/_dsh_mobile/v1/login',{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:st.base.publicPassword})
  });
  assert.equal(login.status,200);
  const token=(await login.json()).token;
  const req={socket:{remoteAddress:'127.0.0.1'},headers:{authorization:`Bearer ${token}`}};
  assert.equal(s.gateway.authorized(req),true);
  st=await s.configure('base',{publicPassword:'NewPublicPass79124'});
  assert.equal(s.gateway.authorized(req),false);
  assert.equal((await fetch(url+'/_dsh_mobile/v1/login',{
    method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:st.base.publicPassword})
  })).status,200);
});

test('base port change restarts one shared gateway and keeps both tunnel passwords',async t=>{
  const {s,tunnel}=await fixture(t);
  const net=await import('node:net');
  const probe=net.createServer();
  await new Promise(resolve=>probe.listen(0,'127.0.0.1',resolve));
  const nextPort=probe.address().port;
  await new Promise(resolve=>probe.close(resolve));
  const before=await s.snapshot();
  const st=await s.configure('base',{port:nextPort});
  assert.equal(st.gateway.port,nextPort);
  assert.equal(st.base.port,nextPort);
  assert.equal(st.lan.port,nextPort);
  assert.equal(st.public.port,nextPort);
  assert.equal(st.lan.visiblePassword,before.lan.visiblePassword);
  assert.equal(st.public.visiblePassword,before.public.visiblePassword);
  assert.equal(st.frpc.visiblePassword,before.frpc.visiblePassword);
  assert.equal(st.lan.enabled,before.lan.enabled);
  assert.equal(st.public.enabled,before.public.enabled);
  assert.equal(tunnel.launches.at(-1).originPort,nextPort);
});
