import test from 'node:test';
import assert from 'node:assert/strict';
import { inflateSync } from 'node:zlib';
import { qrPngDataUrl } from '../lib/qr.js';
import { MobileService } from '../lib/service.js';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { initialSettings } from '../lib/settings.js';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

test('bundled QR encoder produces a valid PNG without npm qrcode dependency', () => {
  const url = qrPngDataUrl(JSON.stringify({protocol:'dsh-mobile/1',instanceId:'hello',mode:'lan',url:'http://192.168.1.2:39081'}));
  assert.match(url, /^data:image\/png;base64,/);
  const png=Buffer.from(url.slice('data:image/png;base64,'.length),'base64');
  assert.equal(png.subarray(0,8).toString('hex'),'89504e470d0a1a0a');
  assert.equal(png.toString('ascii',12,16),'IHDR');
  const width=png.readUInt32BE(16);const height=png.readUInt32BE(20);
  assert.equal(width,height);assert.ok(width>=280);
  const chunks=[];let offset=8;
  while(offset<png.length){
    const len=png.readUInt32BE(offset),kind=png.toString('ascii',offset+4,offset+8);
    if(kind==='IDAT') chunks.push(png.subarray(offset+8,offset+8+len));
    offset+=12+len;
  }
  const pixels=inflateSync(Buffer.concat(chunks));
  assert.equal(pixels.length,height*(width+1));
  assert.equal(pixels[1],255); // quiet zone starts white
  assert.ok(pixels.includes(0)); // finder/data pattern present
});

test('LAN QR service generates a scan-ready PNG and matches the actual pairing payload', async (t) => {
  const dir=await mkdtemp(join(tmpdir(),'dsh-mobile-qr-'));
  t.after(()=>rm(dir,{recursive:true,force:true}));
  const initial=initialSettings();initial.gateway.port=0;initial.public.enabled=false;
  await writeFile(join(dir,'settings.json'),JSON.stringify(initial));
  const s=new MobileService({file:join(dir,'settings.json'),logger:{info(){},warn(){},error(){}}});
  await s.init();t.after(()=>s.stop());
  // Fake public cloud not needed; LAN gateway binds to ephemeral local port.
  const result=await s.configure('lan',{enabled:true,port:0});
  if(result.lan.urls.length===0){t.skip('no externally-visible IPv4 network interface');return;}
  const url=result.lan.urls[0];
  const qr=await s.qr('lan',url);
  assert.equal(qr.payload,url+'?token='+encodeURIComponent(result.base.lanPassword));
  assert.equal(new URL(qr.payload).searchParams.get('token'),result.base.lanPassword);
  assert.equal(new URL(qr.payload).pathname,'/');
  assert.ok(!qr.payload.includes('instanceId')); 
  assert.match(qr.dataUrl,/^data:image\/png;base64,/);
  await assert.rejects(()=>s.qr('lan','http://example.com'),/URL not active/);
});

test('QR links use one password query value, URL-encode it, and reject unknown urls',async t=>{
  const dir=await mkdtemp(join(tmpdir(),'dsh-mobile-qr-short-'));t.after(()=>rm(dir,{recursive:true,force:true}));
  const file=join(dir,'settings.json'); const config=initialSettings();config.gateway.port=0;config.public.enabled=false;
  await writeFile(file,JSON.stringify(config));
  const svc=new MobileService({file,logger:{info(){},warn(){},error(){}}});await svc.init();t.after(()=>svc.stop());
  const lan='My Pass&+?#2026';await svc.configure('base',{lanPassword:lan});
  let state=await svc.snapshot();
  const url=state.lan.url;
  if(!url){t.skip('no LAN address');return;}
  assert.equal((await svc.qr('lan',url)).payload,url+'?token='+encodeURIComponent(lan));
  const oldRevision=state.lan.qrRevision;
  await svc.configure('base',{lanPassword:'DifferentNewPassword987'});
  state=await svc.snapshot();assert.notEqual(oldRevision,state.lan.qrRevision);
  assert.equal((await svc.qr('lan',url)).payload,url+'?token=DifferentNewPassword987');
  assert.equal(state.public.qrRevision,state.frpc.qrRevision);
  assert.ok(!(await svc.qr('lan',url)).payload.includes('%7B'));
});
