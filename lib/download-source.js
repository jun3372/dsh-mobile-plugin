/** GitHub release download routing. Third-party mirrors are opt-in. */
const SOURCES=Object.freeze({
  official:'',
  ghfast:'https://ghfast.top/',
  ghproxy:'https://ghproxy.net/',
  custom:null,
});
const OFFICIAL_HOSTS=new Set(['github.com','release-assets.githubusercontent.com','objects.githubusercontent.com']);
export const DOWNLOAD_SOURCES=Object.freeze(['official','ghfast','ghproxy','custom']);
export function validateDownloadSource(source='official',mirror=''){
  if(!Object.hasOwn(SOURCES,source))throw new Error('下载来源无效');
  if(source!=='custom')return {source,mirror:''};
  if(typeof mirror!=='string'||mirror.length>512)throw new Error('自定义加速地址无效');
  let u;try{u=new URL(mirror);}catch{throw new Error('自定义加速地址必须是 HTTPS 前缀');}
  if(u.protocol!=='https:'||u.username||u.password||u.port||u.search||u.hash||!u.hostname||u.hostname==='localhost'||u.hostname.endsWith('.localhost')||/^(?:\d{1,3}\.){3}\d{1,3}$/.test(u.hostname)||u.hostname.includes(':'))throw new Error('加速地址必须是公开域名 HTTPS 地址（禁止本地地址、端口和凭据）');
  if(u.pathname!=='/' && u.pathname!=='')throw new Error('加速地址仅支持 https://域名/ 前缀');
  return {source,mirror:u.origin+'/'};
}
export function buildDownloadUrl(original,source='official',mirror=''){
  const config=validateDownloadSource(source,mirror);
  const u=new URL(original);
  if(u.protocol!=='https:'||u.hostname!=='github.com'||!u.pathname.includes('/releases/download/'))throw new Error('仅允许 GitHub 官方 Release 资源');
  if(source==='official')return original;
  return (SOURCES[source]??config.mirror)+original;
}
export function allowedDownloadUrl(url,source='official',mirror=''){
  const cfg=validateDownloadSource(source,mirror);
  let u;try{u=new URL(url);}catch{return false;}
  if(u.protocol!=='https:'||u.username||u.password||u.port)return false;
  if(OFFICIAL_HOSTS.has(u.hostname))return true;
  const prefix=SOURCES[cfg.source]??cfg.mirror;
  if(!prefix)return false;
  const mirrorUrl=new URL(prefix);
  return u.origin===mirrorUrl.origin && u.pathname.startsWith('/https://github.com/');
}
export function downloadSourceLabel(source){return ({official:'GitHub 官方',ghfast:'ghfast.top 加速',ghproxy:'ghproxy.net 加速',custom:'自定义加速源'})[source]||'未知来源';}
