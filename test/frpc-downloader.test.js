import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { deflateRawSync, gzipSync } from 'node:zlib';
import { join } from 'node:path';
import {
  FRP_VERSION, resolveFrpc, fetchOfficialAsset, checksumForArchive,
  extractFrpcTarGz, extractFrpcZip,
} from '../lib/frpc-downloader.js';
const hash = buf => createHash('sha256').update(buf).digest('hex');
const testBinary = Buffer.concat([Buffer.from('frpc-binary-mock:'), Buffer.alloc(11984,0x53)]);
function makeTar(prefix) {
  const name = `${prefix}/frpc`;
  const h = Buffer.alloc(512);
  h.write(name,0,'utf8');
  h.write('0000755\0',100,'ascii');
  h.write(testBinary.length.toString(8).padStart(11,'0')+'\0',124,'ascii');
  h[156] = 48;
  return gzipSync(Buffer.concat([h,testBinary,Buffer.alloc((512-testBinary.length%512)%512),Buffer.alloc(1024)]));
}
function makeZip(prefix) {
  const filename = Buffer.from(`${prefix}/frpc.exe`);
  const packed = deflateRawSync(testBinary);
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50,0);local.writeUInt16LE(20,4);local.writeUInt16LE(8,8);
  local.writeUInt32LE(packed.length,18);local.writeUInt32LE(testBinary.length,22);local.writeUInt16LE(filename.length,26);
  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50,0);central.writeUInt16LE(20,4);
  central.writeUInt16LE(20,6);central.writeUInt16LE(8,10);
  central.writeUInt32LE(packed.length,20);central.writeUInt32LE(testBinary.length,24);
  central.writeUInt16LE(filename.length,28);
  const centralOffset = local.length + filename.length + packed.length;
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50,0);end.writeUInt16LE(1,8);end.writeUInt16LE(1,10);
  end.writeUInt32LE(central.length + filename.length,12);end.writeUInt32LE(centralOffset,16);
  return Buffer.concat([local,filename,packed,central,filename,end]);
}
function mockResponse(data, status=200, location='') {
  return { ok:status===200,status,headers:new Map(location?[['location',location]]:[]),
    body:(async function*(){yield data;})() };
}
function fakeGithub({archive,filename,checksum=hash(archive),failDownload=false}) {
  const requests=[];
  async function fetchFn(url, options) {
    requests.push({url,options});
    if(failDownload)throw new Error('network unavailable');
    if(url.endsWith('frp_sha256_checksums.txt')) return mockResponse(Buffer.from(`${checksum}  ${filename}\n`));
    if(url.endsWith(filename)) return mockResponse(archive);
    throw new Error(`unexpected URL ${url}`);
  }
  return {fetchFn,requests};
}
async function temp(t) {
  const dir = await mkdtemp(join(tmpdir(),'dsh-frpc-install-'));
  t.after(() => rm(dir,{recursive:true,force:true}));
  return dir;
}
test('official release archive selection and checksum format are stable', () => {
  assert.equal(FRP_VERSION,'0.71.1');
  assert.equal(checksumForArchive(`${'a'.repeat(64)}  frp_0.71.1_linux_amd64.tar.gz\n`,'frp_0.71.1_linux_amd64.tar.gz'),'a'.repeat(64));
  assert.throws(()=>checksumForArchive('', 'frp_0.71.1_linux_amd64.tar.gz'),/校验|SHA-256/);
  assert.throws(()=>checksumForArchive(`${'b'.repeat(64)}  x\n`,'frp_0.71.1_linux_amd64.tar.gz'),/校验|SHA-256/);
});
test('Linux archive auto-download, integrity verification and restart reuse', async t=>{
  const home = await temp(t);
  const filename='frp_0.71.1_linux_amd64.tar.gz', archive=makeTar('frp_0.71.1_linux_amd64');
  const {fetchFn,requests}=fakeGithub({archive,filename});
  const messages=[];
  const args={home,systemPath:'',osPlatform:'linux',cpuArch:'x64',fetchFn,onProgress:message=>messages.push(message)};
  const file=await resolveFrpc(args);
  assert.equal(file,join(home,'bin','frpc'));
  assert.deepEqual(await readFile(file),testBinary);
  assert.equal((await stat(file)).mode&0o777,0o700);
  assert.equal(requests.length,2);
  assert.ok(requests.every(x=>x.url.startsWith('https://github.com/fatedier/frp/releases/download/v0.71.1/')));
  assert.match(messages.join(' '),/GitHub.*下载/);
  assert.match(messages.join(' '),/校验.*SHA-256/);
  assert.match(messages.join(' '),/已自动安装/);
  const second=await resolveFrpc(args);
  assert.equal(second,file);assert.equal(requests.length,2,'restart must not redownload');
});
test('Windows ZIP auto-install extracts only frpc.exe',async t=>{
  const home=await temp(t);const filename='frp_0.71.1_windows_amd64.zip';
  const archive=makeZip('frp_0.71.1_windows_amd64');
  const {fetchFn}=fakeGithub({archive,filename});
  const file=await resolveFrpc({home,systemPath:'',osPlatform:'win32',cpuArch:'x64',fetchFn});
  assert.equal(file,join(home,'bin','frpc.exe'));
  assert.deepEqual(await readFile(file),testBinary);
});
test('macOS ARM64 release mapping extracts the frpc tar entry',async t=>{
  const home=await temp(t);const filename='frp_0.71.1_darwin_arm64.tar.gz';
  const {fetchFn}=fakeGithub({filename,archive:makeTar('frp_0.71.1_darwin_arm64')});
  const file=await resolveFrpc({home,systemPath:'',osPlatform:'darwin',cpuArch:'arm64',fetchFn});
  assert.deepEqual(await readFile(file),testBinary);
});
test('bad SHA-256 blocks installation, no executable saved',async t=>{
  const home=await temp(t),filename='frp_0.71.1_linux_amd64.tar.gz';
  const {fetchFn}=fakeGithub({filename,archive:makeTar('frp_0.71.1_linux_amd64'),checksum:'a'.repeat(64)});
  await assert.rejects(()=>resolveFrpc({home,systemPath:'',osPlatform:'linux',cpuArch:'x64',fetchFn}),/SHA-256 校验失败/);
  await assert.rejects(()=>stat(join(home,'bin','frpc')),{code:'ENOENT'});
});
test('offline GitHub reports Chinese helpful error; no spawn or invalid binary',async t=>{
  const home=await temp(t);const filename='frp_0.71.1_linux_amd64.tar.gz';
  const {fetchFn}=fakeGithub({filename,archive:Buffer.alloc(12000),failDownload:true});
  await assert.rejects(()=>resolveFrpc({home,systemPath:'',osPlatform:'linux',cpuArch:'x64',fetchFn}),/自动下载失败.*GitHub.*高级设置/);
});
test('explicit binary is used without network, bad explicit path does not silently download',async t=>{
  const home=await temp(t);const external=join(home,'frpc-custom');
  await writeFile(external,testBinary,{mode:0o700});
  const fetchFn=()=>{throw new Error('must not fetch');};
  assert.equal(await resolveFrpc({explicit:external,home,fetchFn,osPlatform:'linux'}),external);
  await assert.rejects(()=>resolveFrpc({explicit:join(home,'not-found'),home,fetchFn,osPlatform:'linux'}),/指定路径无效/);
});
test('unsupported architecture fails with manual installation hint',async t=>{
  const home=await temp(t);
  await assert.rejects(()=>resolveFrpc({home,systemPath:'',osPlatform:'aix',cpuArch:'s390x'}),/暂不支持.*手动配置/);
});
test('download rejects untrusted redirects and oversized assets',async()=>{
  await assert.rejects(()=>fetchOfficialAsset('https://evil.example/frp.tar.gz',{fetchFn:()=>{throw Error('should not fetch')}}),/阻止/);
  const first=async()=>mockResponse(Buffer.alloc(0),302,'http://malicious.example/frpc.exe');
  await assert.rejects(()=>fetchOfficialAsset('https://github.com/fatedier/frp/releases/download/v0.71.1/file',{fetchFn:first}),/阻止/);
  await assert.rejects(()=>fetchOfficialAsset('https://github.com/fatedier/frp/releases/download/v0.71.1/file',{
    fetchFn:async()=>mockResponse(Buffer.alloc(200)),maxBytes:100}),/大小限制/);
});
test('corrupt tar and zip entries are not installed',()=>{
  assert.throws(()=>extractFrpcTarGz(gzipSync(Buffer.alloc(1024)),'frp_0.71.1_linux_amd64'),/没有找到/);
  assert.throws(()=>extractFrpcZip(Buffer.alloc(256),'frp_0.71.1_windows_amd64'),/缺少目录/);
});
test('frpc mirror source rewrites both official release asset and checksum manifest, and validates checksum', async t=>{
  const home=await temp(t);const filename='frp_0.71.1_linux_amd64.tar.gz';
  const archive=makeTar('frp_0.71.1_linux_amd64');const {fetchFn,requests}=fakeGithub({archive,filename});
  await resolveFrpc({home,systemPath:'',osPlatform:'linux',cpuArch:'x64',fetchFn,downloadSource:'ghfast'});
  assert.ok(requests.every(x=>x.url.startsWith('https://ghfast.top/https://github.com/fatedier/frp/releases/download/v0.71.1/')));
});
test('frpc mirror with corrupted asset refuses to install',async t=>{
  const home=await temp(t);const filename='frp_0.71.1_linux_amd64.tar.gz';
  const archive=makeTar('frp_0.71.1_linux_amd64');const {fetchFn}=fakeGithub({archive,filename,checksum:'1'.repeat(64)});
  await assert.rejects(()=>resolveFrpc({home,systemPath:'',osPlatform:'linux',cpuArch:'x64',fetchFn,downloadSource:'ghproxy'}),/SHA-256 校验失败/);
});
