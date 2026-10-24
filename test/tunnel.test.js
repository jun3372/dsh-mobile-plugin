import test from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { TunnelManager } from '../lib/tunnel.js';
import { PassThrough } from 'node:stream';
function fakeProcess(){const proc=new EventEmitter();proc.stdout=new PassThrough();proc.stderr=new PassThrough();proc.kill=()=>proc.emit('exit',0,'SIGTERM');return proc;}
test('quick tunnel uses local origin, parses real public URL and stops',async()=>{
  let args;const child=fakeProcess();const tm=new TunnelManager({spawnFn:(cmd,a,opts)=>{args=a;return child;}});
  await tm.start({mode:'quick',originPort:39082});
  assert.equal(tm.state,'connecting');assert.deepEqual(args,['tunnel','--no-autoupdate','--url','http://127.0.0.1:39082']);
  child.stderr.write('2026 INFO Your quick Tunnel has been created! https://one-test.trycloudflare.com');
  assert.equal(tm.state,'online');assert.equal(tm.url,'https://one-test.trycloudflare.com');
  tm.stop();assert.equal(tm.state,'stopped');assert.equal(tm.url,'');
});
test('named tunnel uses TUNNEL_TOKEN environment and never puts it in argv',async()=>{
  let args,env;const child=fakeProcess();const tm=new TunnelManager({spawnFn:(cmd,a,opts)=>{args=a;env=opts.env;return child;}});
  await tm.start({mode:'named',originPort:39082,hostname:'https://host.example',token:'secret-token'});
  assert.equal(args.includes('secret-token'),false);assert.equal(env.TUNNEL_TOKEN,'secret-token');
  child.stderr.write('INF Registered tunnel connection');assert.equal(tm.state,'online');
  tm.stop();
});
test('missing cloudflared triggers lost event and error status',async()=>{
  const child=fakeProcess();const tm=new TunnelManager({spawnFn:()=>child});
  let losses=0;tm.on('lost',()=>losses++);
  await tm.start({mode:'quick',originPort:39082});
  child.emit('error',new Error('ENOENT'));
  assert.equal(losses,1);assert.equal(tm.state,'error');assert.equal(tm.error,'ENOENT');
});
