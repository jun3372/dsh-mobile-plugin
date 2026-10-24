#!/usr/bin/env node
/** Strict DSH direct-host vs gateway differential audit.
 * Direct DSH is used ONLY as an independent baseline, NEVER a proxy fallback.
 * In particular, status 401/404 at either endpoint does not indicate success.
 */
import {readFile,writeFile} from 'node:fs/promises';
import {createHash,randomBytes} from 'node:crypto';
import {connect} from 'node:net';
import {connect as tlsConnect} from 'node:tls';

const manifestFile=process.argv[2], reportFile=process.argv[3];
const hostText=process.env.DSH_DIRECT_URL, proxyText=process.env.DSH_MOBILE_GATEWAY_URL;
const hostCookie=process.env.DSH_DIRECT_COOKIE, password=process.env.DSH_MOBILE_TEST_PASSWORD;
if(!manifestFile || !hostText || !proxyText || !hostCookie || !password){
  console.error('用法：DSH_DIRECT_URL=http://127.0.0.1:3080 DSH_DIRECT_COOKIE="dsh-auth-xxx=..." DSH_MOBILE_GATEWAY_URL=http://127.0.0.1:39081 DSH_MOBILE_TEST_PASSWORD=... node scripts/compare-direct-proxy.mjs <manifest.json> [report.json]');
  process.exit(2);
}
const direct=new URL(hostText), gateway=new URL(proxyText);
for(const url of [direct,gateway]){
  if(!['http:','https:'].includes(url.protocol) || url.pathname!=='/' || url.search || url.hash || url.username || url.password)
    throw Error('对照 URL 必须是 HTTP(S) 根地址');
}
if(direct.origin===gateway.origin)throw Error('原生 DSH 与网关不得使用相同的目标地址');
if(/^(?:localhost|127\.\d+\.\d+\.\d+|\[::1\])$/.test(gateway.hostname) && gateway.port==='3080')
  throw Error('网关地址不得错误指向 DSH 默认 3080 端口');
const manifest=JSON.parse(await readFile(manifestFile,'utf8'));
if(!manifest.sourceRevision?.trim() || !Array.isArray(manifest.interfaces) || !manifest.interfaces.length ||
  !Number.isInteger(manifest.declaredCount) || manifest.declaredCount!==manifest.interfaces.length)throw Error('必须提供完整声明的 DSH 接口清单、sourceRevision 和 declaredCount');
const ids=new Set();
for(const item of manifest.interfaces){
  if(!item.id || ids.has(item.id))throw Error('接口 ID 缺失或重复');ids.add(item.id);
  if(!['http','websocket'].includes(item.kind)||!item.path?.startsWith('/')||item.path.startsWith('//'))throw Error(item.id+' 路径无效');
  if(new URL(item.path,direct).origin!==direct.origin||new URL(item.path,gateway).origin!==gateway.origin)throw Error(item.id+' 非法跨域路径');
  if(!Number.isInteger(item.expectStatus) || (item.kind==='websocket' ? item.expectStatus!==101 : (item.expectStatus<200||item.expectStatus>=300)))
    throw Error(item.id+' 必须声明成功 HTTP 2xx / WebSocket 101 预期状态，不能将拒绝状态伪装成通过');
  if(item.kind==='websocket' && (!item.exchange || !Number.isInteger(item.exchange.expectFrames) || item.exchange.expectFrames<1 || !item.exchange.payloadBase64))
    throw Error(item.id+' WebSocket 必须提供真实帧请求及至少一个应答帧，不能仅检查 101');
}
const discovery=await fetch(new URL('/_dsh_mobile/v1/info',gateway),{redirect:'manual',signal:AbortSignal.timeout(12000)});
if(discovery.status!==200)throw Error('网关发现失败：HTTP '+discovery.status);
const info=await discovery.json();
if(info.protocol!=='dsh-mobile/1'||!info.instanceId)throw Error('网关实例标识不正确');
const auth=await fetch(new URL('/_dsh_mobile/v1/login',gateway),{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({password}),redirect:'manual',signal:AbortSignal.timeout(12000)});
if(auth.status!==200)throw Error('网关认证失败：HTTP '+auth.status);
const token=(await auth.json()).token;
if(!/^[\w-]{43}$/.test(token||''))throw Error('登录令牌无效');
const SHA=data=>createHash('sha256').update(data).digest('hex');
const TEST_HEADERS=['content-type','content-encoding','content-range','accept-ranges','etag','cache-control','content-disposition','last-modified','vary'];
function bodyFrom(item){
  if(typeof item.bodyBase64==='string')return Buffer.from(item.bodyBase64,'base64');
  if(item.body!==undefined)return typeof item.body==='string'?Buffer.from(item.body):Buffer.from(JSON.stringify(item.body));
  return undefined;
}
async function compareHttp(item){
  const body=bodyFrom(item);
  const base={method:item.method||'GET',headers:item.headers||{},body,redirect:'manual',signal:AbortSignal.timeout(item.timeoutMs||25000)};
  const one=await fetch(new URL(item.path,direct),{...base,headers:{...base.headers,Cookie:hostCookie}});
  const two=await fetch(new URL(item.path,gateway),{...base,headers:{...base.headers,Authorization:'Bearer '+token}});
  if(new URL(two.url).origin!==gateway.origin || two.headers.get('x-dsh-mobile-gateway')!==info.instanceId)
    throw Error('响应未能证明来自插件网关');
  const a=Buffer.from(await one.arrayBuffer()), b=Buffer.from(await two.arrayBuffer());
  if(one.status!==item.expectStatus)throw Error(`原生 DSH 未成功完成前置测试: ${one.status}，预期 ${item.expectStatus}`);
  if(two.status!==one.status)throw Error(`状态码不一致: DSH ${one.status} / 网关 ${two.status}`);
  if(!a.equals(b))throw Error(`响应内容不一致: DSH ${SHA(a)} / 网关 ${SHA(b)}`);
  for(const h of TEST_HEADERS){
    if(one.headers.get(h)!==two.headers.get(h))throw Error(`响应头 ${h} 不一致: DSH=${one.headers.get(h)} / 网关=${two.headers.get(h)}`);
  }
  if(one.status>=300&&one.status<400)throw Error('存在尚未单独审计的重定向：不能当作业务接口通过');
  return {status:two.status,bytes:b.length,sha256:SHA(b)};
}
function wsFrame(payload){
  if(payload.length>65535)throw Error('当前审计帧大小限制 65535 字节');
  const mask=randomBytes(4),prefix=payload.length<126?Buffer.from([0x82,0x80|payload.length]):Buffer.from([0x82,0xfe,payload.length>>8,payload.length&255]);
  return Buffer.concat([prefix,mask,Buffer.from(payload.map((x,i)=>x^mask[i%4]))]);
}
async function wsExchange(base,item,authHeaders){
  const url=new URL(item.path,base),secure=url.protocol==='https:';
  const sock=secure?tlsConnect({host:url.hostname,port:Number(url.port||443),servername:url.hostname}):connect(Number(url.port||80),url.hostname);
  const wsKey=randomBytes(16).toString('base64'),accept=createHash('sha1').update(wsKey+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  return new Promise((resolve,reject)=>{
    let buf=Buffer.alloc(0),headerDone=false,header='',finished=false;
    const frames=[];
    const timer=setTimeout(()=>end(Error('WebSocket 帧响应超时')),item.timeoutMs||12000);
    function end(e,answer){if(finished)return;finished=true;clearTimeout(timer);sock.destroy();e?reject(e):resolve(answer);}
    sock.on('error',end);
    sock.once(secure?'secureConnect':'connect',()=>sock.write(`GET ${url.pathname}${url.search} HTTP/1.1\r\nHost: ${url.host}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: ${wsKey}\r\n${Object.entries(authHeaders).map(([k,v])=>`${k}: ${v}\r\n`).join('')}\r\n`));
    sock.on('data',part=>{
      buf=Buffer.concat([buf,part]);
      if(!headerDone){
        const pos=buf.indexOf('\r\n\r\n');if(pos<0){if(buf.length>32768)end(Error('握手响应过大'));return;}
        header=buf.subarray(0,pos).toString('latin1');buf=buf.subarray(pos+4);headerDone=true;
        if(Number(/^HTTP\/1\.1 (\d+)/.exec(header)?.[1])!==101)return end(Error('WebSocket 升级失败：'+header.split('\r\n')[0]));
        if(!header.toLowerCase().includes('sec-websocket-accept: '+accept.toLowerCase()))return end(Error('握手校验错误'));
        sock.write(wsFrame(Buffer.from(item.exchange.payloadBase64,'base64')));
      }
      while(buf.length>=2){
        const op=buf[0]&0xf,len7=buf[1]&127,masked=Boolean(buf[1]&128);
        let offset=2,len=len7;
        if(len7===126){if(buf.length<4)break;len=buf.readUInt16BE(2);offset=4;}
        if(len7===127) return end(Error('WebSocket 响应帧过大，需扩展审计器'));
        if(masked)return end(Error('服务端错误地使用掩码'));
        if(buf.length<offset+len)break;
        const payload=buf.subarray(offset,offset+len);buf=buf.subarray(offset+len);
        if(op===8)return end(Error('业务帧数量不足，连接提前关闭'));
        if(op===9){sock.write(Buffer.from([0x8a,0x80,0,0,0,0]));continue;}
        if(op===1||op===2)frames.push({op,hex:payload.toString('hex')});
        if(frames.length===item.exchange.expectFrames)return end(null,{status:101,frames,header});
      }
    });
    sock.on('close',()=>{if(!finished)end(Error('连接提前断开'));});
  });
}
async function compareWebsocket(item){
  const a=await wsExchange(direct,item,{Cookie:hostCookie});
  const b=await wsExchange(gateway,item,{Authorization:'Bearer '+token});
  if(!b.header.toLowerCase().includes('x-dsh-mobile-gateway: '+info.instanceId.toLowerCase()))throw Error('WebSocket 未经插件网关');
  if(JSON.stringify(a.frames)!==JSON.stringify(b.frames))throw Error('DSH 与网关 WebSocket 数据帧不一致');
  return {status:101,frameCount:b.frames.length};
}
const results=[];
for(const item of manifest.interfaces){
  try{
    const detail=item.kind==='websocket'?await compareWebsocket(item):await compareHttp(item);
    results.push({id:item.id,kind:item.kind,ok:true,...detail});console.log('[通过]',item.id);
  }catch(error){results.push({id:item.id,kind:item.kind,ok:false,error:error.message});console.error('[失败]',item.id,error.message);}
}
const passed=results.filter(r=>r.ok).length;
const report={sourceRevision:manifest.sourceRevision,declaredCount:manifest.declaredCount,testedCount:results.length,passedCount:passed,failedCount:results.length-passed,realInterfaceInventoryVerified:false,info:'两端请求单独发送，不以直连成功代替代理成功。声明清单覆盖是否等于 DSH 全部接口须另行从实际版本源码核对。DSH Host 会话 Cookie、网关登录和网关标记被视为必要差异。',results};
if(reportFile)await writeFile(reportFile,JSON.stringify(report,null,2));
console.log(`对照完成：${passed}/${results.length}（仅覆盖声明清单；不得直接声称覆盖全部 DSH 接口）`);
if(passed!==results.length)process.exitCode=1;
