import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { FrpcManager, frpcPublicUrl, renderFrpcConfig, resolveFrpc } from '../lib/frpc.js';

const config = {serverAddr:'frps.example.com',serverPort:7000,remotePort:39081,authToken:'secret-token',proxyName:'dsh_mobile',originPort:39081};

test('frpc configuration maps the EXISTING gateway port and escapes TOML strings',()=>{
  const output=renderFrpcConfig(config);
  assert.match(output,/serverAddr = "frps.example.com"/);
  assert.match(output,/localIP = "127.0.0.1"/);
  assert.match(output,/localPort = 39081/);
  assert.match(output,/remotePort = 39081/);
  assert.match(output,/transport\.tls\.enable = true/);
  assert.match(output,/auth\.token = "secret-token"/);
  assert.equal(frpcPublicUrl(config),'http://frps.example.com:39081');
  assert.equal(frpcPublicUrl({...config,publicUrl:'https://mobile.example.com'}),'https://mobile.example.com');
});

test('bad frpc config and user-controlled TOML injection are rejected',()=>{
  assert.throws(()=>renderFrpcConfig({...config,serverAddr:'evil.example.com\n[[proxies]]'}),/地址无效/);
  assert.throws(()=>renderFrpcConfig({...config,proxyName:'test\nserverPort=1'}),/映射名称/);
  assert.throws(()=>renderFrpcConfig({...config,remotePort:0}),/端口/);
  assert.throws(()=>frpcPublicUrl({...config,publicUrl:'https://admin:pass@example.org'}),/地址只能/);
  assert.throws(()=>frpcPublicUrl({...config,publicUrl:'javascript:alert(1)'}),/地址只能/);
});

test('frpc process persists restricted configuration and uses argument array, not shell',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'dsh-frpc-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const calls=[];let child;
  const mgr=new FrpcManager({file:join(dir,'frpc.toml'),resolver:async()=>'/mock/frpc',spawnFn:(exe,args,options)=>{
    calls.push({exe,args,options});child=new EventEmitter();child.stdout=new EventEmitter();child.stderr=new EventEmitter();child.kill=()=>{child.emit('exit',0)};return child;
  }});
  await mgr.start(config);
  assert.equal(mgr.state,'connecting');
  assert.deepEqual(calls[0].args,['-c',join(dir,'frpc.toml')]);
  assert.equal(calls[0].options.shell,undefined);
  const contents=await readFile(join(dir,'frpc.toml'),'utf8');assert.match(contents,/secret-token/);
  if(process.platform!=='win32')assert.equal((await stat(join(dir,'frpc.toml'))).mode&0o777,0o600);
  child.stdout.emit('data','[test] start proxy success');
  assert.equal(mgr.snapshot().state,'online');
  assert.equal(mgr.snapshot().url,'http://frps.example.com:39081');
  mgr.stop();assert.equal(mgr.snapshot().state,'stopped');
});

test('frpc missing executable reports actionable error without starting shell',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'dsh-frpc-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const mgr=new FrpcManager({file:join(dir,'frpc.toml'),resolver:async()=>{throw new Error('frpc not found');}});
  await assert.rejects(()=>mgr.start(config),/frpc not found/);
  assert.equal(mgr.snapshot().state,'error');
  assert.match(mgr.snapshot().error,/frpc not found/);
  mgr.stop();
});

test('frpc process unexpected exit is an error and emits lost',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'dsh-frpc-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  let child;const mgr=new FrpcManager({file:join(dir,'frpc.toml'),resolver:async()=>'/mock/frpc',spawnFn:()=>{
    child=new EventEmitter();child.stdout=new EventEmitter();child.stderr=new EventEmitter();child.kill=()=>{};return child;
  }});
  let lost=0;mgr.on('lost',()=>lost++);
  await mgr.start(config);child.emit('exit',1,null);
  assert.equal(mgr.snapshot().state,'error');assert.equal(lost,1);
});

test('frpc manager relays auto-install progress for DSH logs, without exposing frps token',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'dsh-frpc-install-log-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const messages=[];
  const manager=new FrpcManager({file:join(dir,'frpc.toml'),
    resolver:async({onProgress})=>{
      onProgress('正在从 GitHub 下载官方 frpc');
      onProgress('frpc SHA-256 校验通过，安装完成');
      return '/mock/frpc';
    },
    spawnFn:()=>{const child=new EventEmitter();child.stdout=new EventEmitter();child.stderr=new EventEmitter();child.kill=()=>{};return child;}
  });
  manager.on('install',message=>messages.push(message));
  await manager.start(config);
  assert.equal(messages.length,2);
  assert.match(messages.join(' '),/GitHub.*SHA-256/);
  assert.ok(!messages.join(' ').includes(config.authToken));
  manager.stop();
});
