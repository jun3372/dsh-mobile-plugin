// Download only official Cloudflare release assets; verify pinned release digest.
// No dependency on npm install scripts or arbitrary shell commands.
import { access, chmod, mkdir, rename, writeFile, rm } from 'node:fs/promises';
import { constants } from 'node:fs';
import { homedir, platform, arch } from 'node:os';
import { delimiter, isAbsolute, join } from 'node:path';
import { createHash } from 'node:crypto';
import { gunzipSync } from 'node:zlib';
import { buildDownloadUrl, allowedDownloadUrl, downloadSourceLabel } from './download-source.js';

const VERSION='2026.10.2';
const ASSETS={
  'linux-x64':['cloudflared-linux-amd64','53b7a7a5420d188758d24341294acb0d1bca54296548ac05e38811a694ac6134'],
  'linux-arm64':['cloudflared-linux-arm64','98aca3173f73248fad6180fc75dade2d186a6e54fa807e088108cb4345de8efe'],
  'linux-ia32':['cloudflared-linux-386','e11f1a244567ff4d144f13533c6a0a29833f0d93e9a3586099e708f1028affb4'],
  'win32-x64':['cloudflared-windows-amd64.exe','547057326266f0e1c7d50d102dbd22ff283d740c055bd61e94f10e2c606f89af'],
  'win32-ia32':['cloudflared-windows-386.exe','e11ee417d5bab1918c3e257c2b1f9541d6febd545091ecf87e249c3cfb7880b0'],
  'darwin-x64':['cloudflared-darwin-amd64.tgz','b64efd5a2772fc124b855f60eb3d33ba1a4f2ba67b19ddc58d32b705d42b82c9'],
  'darwin-arm64':['cloudflared-darwin-arm64.tgz','529a07089ac2d46762578389230fa148e5cb6ce2689200fc006956864042d17a'],
};
const executableName=()=>platform()==='win32'?'cloudflared.exe':'cloudflared';
const pluginHome=()=>join(process.env.DSH_HOME||join(homedir(),'.dsh'),'dsh-mobile-plugin');
async function isExecutable(file){try{await access(file,platform()==='win32'?constants.F_OK:constants.X_OK);return true;}catch{return false;}}
function extractBinaryTGZ(tgz){
  const archive=gunzipSync(tgz);
  for(let off=0;off+512<=archive.length;){
    const header=archive.subarray(off,off+512);
    if(header.every(x=>x===0))break;
    const name=header.subarray(0,100).toString('utf8').replace(/\0.*$/,'');
    const sizeStr=header.subarray(124,136).toString('ascii').replace(/\0.*$/,'').trim();
    const size=parseInt(sizeStr,8);
    if(!Number.isSafeInteger(size)||size<0||off+512+size>archive.length)throw new Error('invalid cloudflared archive');
    const type=header[156];
    if((name==='cloudflared'||name.endsWith('/cloudflared'))&&(type===0||type===48))return archive.subarray(off+512,off+512+size);
    off+=512+Math.ceil(size/512)*512;
  }
  throw new Error('cloudflared executable not found in release archive');
}
async function downloadAsset(url,{fetchFn=fetch,downloadSource='official',downloadMirror=''}={}){
  let current=url;
  for(let attempt=0;attempt<6;attempt++){
    const u=new URL(current);
    if(!allowedDownloadUrl(current,downloadSource,downloadMirror))throw new Error('cloudflared download redirect blocked');
    const response=await fetchFn(current,{redirect:'manual',signal:AbortSignal.timeout(90_000)});
    if([301,302,303,307,308].includes(response.status)){
      const next=response.headers.get('location');if(!next)throw new Error('download redirect missing location');
      current=new URL(next,current).href;continue;
    }
    if(!response.ok)throw new Error(`cloudflared official download HTTP ${response.status}`);
    const parts=[];let size=0;
    for await(const part of response.body){size+=part.length;if(size>95_000_000)throw new Error('cloudflared asset exceeds size limit');parts.push(part);}
    return Buffer.concat(parts);
  }
  throw new Error('too many cloudflared download redirects');
}
export async function resolveCloudflared({explicit='',allowDownload=true,fetchFn=fetch,home=pluginHome(),systemPath=process.env.PATH||'',downloadSource='official',downloadMirror=''}={}) {
  const requested=explicit||process.env.DSH_MOBILE_CLOUDFLARED||'';
  if(requested){
    if(isAbsolute(requested) && await isExecutable(requested))return requested;
    if(requested.includes('/')||requested.includes('\\'))throw new Error(`cloudflared executable does not exist or is not executable: ${requested}`);
    const match=await findOnPath(requested,systemPath);if(match)return match;
    throw new Error(`cloudflared executable not found: ${requested}`);
  }
  const own=join(home,'bin',executableName());
  if(await isExecutable(own))return own;
  const found=await findOnPath(executableName(),systemPath);
  if(found)return found;
  if(!allowDownload)throw new Error('cloudflared not found: set the executable path or install cloudflared');
  const asset=ASSETS[`${platform()}-${arch()}`];
  if(!asset)throw new Error(`No automatic cloudflared binary for ${platform()}-${arch()}; please install manually and configure its executable path`);
  const [file,expectedHash]=asset;
  const url=buildDownloadUrl(`https://github.com/cloudflare/cloudflared/releases/download/${VERSION}/${file}`,downloadSource,downloadMirror);
  let downloaded;
  try {downloaded=await downloadAsset(url,{fetchFn,downloadSource,downloadMirror});}
  catch(err){throw new Error(`cloudflared not installed; ${downloadSourceLabel(downloadSource)} automatic download failed (${err.message}). Set the cloudflared executable path or install it manually.`);}
  if(createHash('sha256').update(downloaded).digest('hex')!==expectedHash)throw new Error('cloudflared download checksum mismatch; installation aborted');
  const binary=file.endsWith('.tgz')?extractBinaryTGZ(downloaded):downloaded;
  const folder=join(home,'bin');await mkdir(folder,{recursive:true,mode:0o700});
  const temp=`${own}.${process.pid}.tmp`;
  try {await writeFile(temp,binary,{mode:0o700,flag:'wx'});await chmod(temp,0o700);await rename(temp,own);}
  finally{await rm(temp,{force:true}).catch(()=>{});}
  return own;
}
async function findOnPath(file,systemPath){
  const candidates=platform()==='win32'&&!file.toLowerCase().endsWith('.exe')?[file+'.exe',file]:[file];
  for(const folder of systemPath.split(delimiter).filter(Boolean))for(const candidate of candidates){
    const full=join(folder,candidate);if(await isExecutable(full))return full;
  }
  return '';
}
