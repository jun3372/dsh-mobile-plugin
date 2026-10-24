import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { initialSettings } from '../lib/settings.js';
import { MobileService } from '../lib/service.js';
class FakeTunnel extends EventEmitter {
  constructor(){super();this.state='stopped';this.url='';this.error='';}
  async start(){this.state='online';this.url='https://test.trycloudflare.com';this.emit('change');}
  stop(){this.state='stopped';this.url='';this.emit('change');}
  snapshot(){return {state:this.state,url:this.url,error:this.error};}
}
class FakeFrpc extends EventEmitter {
  constructor(){super();this.state='stopped';this.url='';this.error='';this.launches=[];}
  async start(opts){this.launches.push(opts);this.state='online';this.url=`https://mobile.example.com`;this.emit('change');}
  stop(){this.state='stopped';this.url='';this.emit('change');}
  snapshot(){return {state:this.state,url:this.url,error:this.error};}
}
async function fixture(t,change=()=>{}){
  const dir=await mkdtemp(join(tmpdir(),'dsh-frpc-service-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const file=join(dir,'settings.json');const initial=initialSettings();initial.gateway.port=0;change(initial);
  await writeFile(file,JSON.stringify(initial));
  const frpc=new FakeFrpc();const tunnel=new FakeTunnel();
  const service=new MobileService({file,frpc,tunnel,logger:{info(){},warn(){},error(){}}});
  await service.init();t.after(()=>service.stop());return {service,frpc,tunnel,file};
}
test('frpc defaults OFF; upgrading older dev.9 settings preserves all existing passwords and identity',async t=>{
  const {service,file}=await fixture(t,s=>delete s.frpc);
  const status=await service.snapshot();assert.equal(status.frpc.enabled,false);
  assert.ok(status.lan.visiblePassword);assert.ok(status.public.visiblePassword);
  assert.equal(JSON.parse(await readFile(file,'utf8')).frpc.enabled,false);
});
test('frpc starts on same local gateway port and reuses public password independently of Cloudflare enable flag',async t=>{
  const {service,frpc,tunnel,file}=await fixture(t);
  await service.configure('public',{enabled:false});
  let s=await service.configure('frpc',{enabled:true,serverAddr:'frps.example.com',serverPort:7000,remotePort:40443,authToken:'my-frps-secret',proxyName:'dsh_mobile',publicUrl:'https://mobile.example.com'});
  assert.equal(s.frpc.running,true);assert.equal(s.public.running,false);
  assert.equal(frpc.launches.length,1);assert.equal(frpc.launches[0].originPort,s.gateway.port);
  assert.equal(frpc.launches[0].authToken,'my-frps-secret');assert.equal(s.frpc.visiblePassword,s.public.visiblePassword);
  assert.equal(s.frpc.hasToken,true);
  assert.ok(s.frpc.url.startsWith('https://'));
  const qr=(await service.qr('frpc',s.frpc.url)).payload;
  assert.equal(qr,s.frpc.url+'?token='+encodeURIComponent(s.public.visiblePassword));
  assert.equal(new URL(qr).searchParams.get('token'),s.public.visiblePassword);
  assert.ok(!JSON.stringify(s).includes('my-frps-secret'));
  assert.ok(!(s.recentLogs.map(v=>v.message).join('')).includes('my-frps-secret'));
  const login=await fetch(`http://127.0.0.1:${s.gateway.port}/_dsh_mobile/v1/login`,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({password:s.public.visiblePassword})});
  assert.equal(login.status,200);
  await service.configure('frpc',{enabled:false});
  s=await service.snapshot();assert.equal(s.frpc.running,false);assert.equal(s.lan.running,true);
  assert.equal(tunnel.state,'stopped');
  assert.equal(JSON.parse(await readFile(file,'utf8')).frpc.enabled,false);
});
test('frpc status and address restored after DSH restart, existing public password stays same',async t=>{
  const {service,file}=await fixture(t,s=>{s.public.enabled=false;s.frpc={enabled:true,serverAddr:'frps.example.com',serverPort:7000,remotePort:39081,authToken:'secret',proxyName:'dsh-mobile',publicUrl:'https://mobile.example.com',binaryPath:''}});
  const first=await service.snapshot();assert.equal(first.frpc.running,true);
  await service.stop();
  const second=new MobileService({file,frpc:new FakeFrpc(),tunnel:new FakeTunnel(),logger:{info(){},warn(){},error(){}}});
  await second.init();t.after(()=>second.stop());
  const restarted=await second.snapshot();assert.equal(restarted.frpc.running,true);
  assert.equal(restarted.frpc.visiblePassword,first.frpc.visiblePassword);
  assert.equal(restarted.frpc.url,first.frpc.url);
});
test('frpc invalid settings reject without changing persisted configuration',async t=>{
  const {service,file}=await fixture(t);
  await assert.rejects(()=>service.configure('frpc',{enabled:true,serverAddr:'bad host',remotePort:39081}),/frps 地址/);
  await assert.rejects(()=>service.configure('frpc',{enabled:true,serverAddr:'frps.example.com',remotePort:70000}),/frpc 端口/);
  await assert.rejects(()=>service.configure('frpc',{publicUrl:'javascript:alert(1)'}),/frpc 手机连接地址/);
  assert.equal((await service.snapshot()).frpc.enabled,false);
  assert.equal(JSON.parse(await readFile(file,'utf8')).frpc.enabled,false);
});

test('frpc downloader progress is forwarded to plugin runtime log in Chinese', async t => {
  const {service,frpc}=await fixture(t);
  frpc.emit('install','本机未发现 frpc，正在从 GitHub 官方 Release 下载');
  frpc.emit('install','frpc 下载完成，正在校验官方 SHA-256');
  const s=await service.snapshot();
  const messages=s.recentLogs.map(entry=>entry.message).join(' | ');
  assert.match(messages,/GitHub 官方 Release 下载/);
  assert.match(messages,/校验官方 SHA-256/);
});
test('frpc password field updates shared public password, with previous LAN password unchanged',async t=>{
  const {service}=await fixture(t);const before=await service.snapshot();
  const after=await service.configure('frpc',{password:'sharedPassword2026'});
  assert.equal(after.frpc.visiblePassword,'sharedPassword2026');
  assert.equal(after.public.visiblePassword,'sharedPassword2026');
  assert.equal(after.lan.visiblePassword,before.lan.visiblePassword);
});
