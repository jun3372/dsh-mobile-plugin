import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { resolveCloudflared } from '../lib/cloudflared.js';

test('explicit cloudflared executable works without network and bad paths have clear errors',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'dsh-binary-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const file=join(dir,process.platform==='win32'?'cloudflared.exe':'cloudflared');
  await writeFile(file,'mock binary',{mode:0o700});
  assert.equal(await resolveCloudflared({explicit:file,allowDownload:false}),file);
  await assert.rejects(()=>resolveCloudflared({explicit:join(dir,'missing'),allowDownload:false}),/cloudflared executable does not exist/);
});
test('missing cloudflared fails with actionable manual path hint when automatic download unavailable',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'dsh-binary-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const old=process.env.DSH_MOBILE_CLOUDFLARED;delete process.env.DSH_MOBILE_CLOUDFLARED;
  try {
    await assert.rejects(()=>resolveCloudflared({home:dir,systemPath:'',fetchFn:async()=>{throw new Error('network offline');}}),/install|download failed|automatic cloudflared/);
  } finally {if(old===undefined)delete process.env.DSH_MOBILE_CLOUDFLARED;else process.env.DSH_MOBILE_CLOUDFLARED=old;}
});
test('cloudflared download can select a mirror but never runs a binary with wrong pinned SHA-256',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'dsh-cloudflare-mirror-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const requests=[];const fetchFn=async url=>{
    requests.push(url);
    return {ok:true,status:200,headers:new Map(),body:(async function*(){yield Buffer.from('fake binary from mirror');})()};
  };
  await assert.rejects(()=>resolveCloudflared({home:dir,systemPath:'',fetchFn,downloadSource:'ghfast'}),/checksum mismatch|download checksum/);
  assert.equal(requests.length,1);
  assert.ok(requests[0].startsWith('https://ghfast.top/https://github.com/cloudflare/cloudflared/releases/download/'));
});
