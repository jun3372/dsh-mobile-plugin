import { mkdir, readFile, rename, writeFile, chmod } from 'node:fs/promises';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { createIdentity, hashPassword, randomPassword, safePassword } from './security.js';

const home = () => process.env.DSH_HOME || join(homedir(), '.dsh');
export const settingsFile = () => join(home(), 'dsh-mobile-plugin', 'settings.json');
export function initialSettings() {
  return { schema: 2, identity: createIdentity(), gateway: {port:39081},
    // 按用户要求：首次安装即启动局域网与公网，后续跟随开关配置自动恢复。
    lan: {enabled:true, preferredAddress:'', passwordMode:'random', password:'', hash:''},
    public: {enabled:true, mode:'quick', hostname:'', token:'', downloadSource:'official', downloadMirror:'', passwordMode:'random',password:'',hash:''},
    frpc: {enabled:false, serverAddr:'', serverPort:7000, remotePort:0, authToken:'', proxyName:'dsh-mobile', publicUrl:'', binaryPath:'', downloadSource:'official',downloadMirror:''},
    upstream:process.env.DSH_MOBILE_UPSTREAM || 'http://127.0.0.1:3080' };
}
export async function loadSettings(file=settingsFile()) {
  let settings;
  try { settings=JSON.parse(await readFile(file,'utf8')); }
  catch (err) { if(err.code!=='ENOENT')throw err; settings=initialSettings(); }
  if (settings.schema === 1 && settings.identity?.privateKey && settings.lan && settings.public) {
    // The old random password existed only in memory. Rotate ONCE on upgrade.
    // An old fixed password is hashed and cannot be recovered: preserve its hash
    // and ask the user to re-enter it if they want it displayed.
    settings.gateway={port:Number.isInteger(settings.lan.port)?settings.lan.port:39081};
    delete settings.lan.port; delete settings.public.port;
    for(const mode of ['lan','public'])settings[mode].password='';
    settings.schema=2;
  }
  if(settings.schema!==2 || !settings.identity?.privateKey || !settings.gateway || !settings.lan || !settings.public) throw new Error('Unsupported DSH Mobile settings format');
  // 向后兼容：旧配置仅增加 frpc（默认关闭），不改变已有密码、端口、实例身份。
  if(!settings.frpc) settings.frpc=initialSettings().frpc;
  // 兼容 dev.4 及更早配置：新增首选 IP，不改变已有密码与实例身份。
  if (typeof settings.lan.preferredAddress !== 'string') settings.lan.preferredAddress = '';
  for(const mode of ['public','frpc']){
    if(!settings[mode].downloadSource)settings[mode].downloadSource='official';
    if(typeof settings[mode].downloadMirror!=='string')settings[mode].downloadMirror='';
  }
  preparePasswords(settings);
  await saveSettings(settings,file);
  return settings;
}
export async function saveSettings(settings,file=settingsFile()) {
  await mkdir(dirname(file),{recursive:true,mode:0o700});
  const tmp=`${file}.${process.pid}.tmp`;
  await writeFile(tmp,JSON.stringify(settings,null,2)+'\n',{mode:0o600,flag:'w'});
  await chmod(tmp,0o600); await rename(tmp,file); await chmod(file,0o600);
}
export function preparePasswords(settings) {
  for(const mode of ['lan','public']) {
    const entry=settings[mode];
    if(entry.passwordMode==='random' && !entry.password) {
      entry.password=randomPassword(); entry.hash=hashPassword(entry.password);
    } else if(entry.password && (!entry.hash || !entry.hash.startsWith('scrypt:'))) {
      entry.hash=hashPassword(entry.password);
    }
    if(entry.password && !safePassword(entry.password)) throw new Error('invalid saved password');
    if(!entry.hash) throw new Error(`Missing ${mode} password`);
  }
}
export function setPassword(settings,mode,kind,password,{rotate=false}={}) {
  if(!['lan','public'].includes(mode))throw new Error('invalid mode');
  if(!['random','fixed'].includes(kind))throw new Error('invalid password mode');
  const entry=settings[mode];
  const oldPassword=entry.password;const oldMode=entry.passwordMode;
  if(kind==='fixed') {
    if(typeof password!=='string' || !safePassword(password))throw new Error('fixed password must be 8–64 characters');
    entry.password=password;
  } else if(kind!==entry.passwordMode || rotate || !entry.password) entry.password=randomPassword();
  entry.passwordMode=kind;
  if(entry.password && (entry.password!==oldPassword || oldMode!==kind || !entry.hash))entry.hash=hashPassword(entry.password);
  return entry.password || null;
}
