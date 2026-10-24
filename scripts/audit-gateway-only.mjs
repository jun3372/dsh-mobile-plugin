#!/usr/bin/env node
/** Strict, manifest-driven gateway-only DSH API audit.
 * NEVER opens the DSH Host listener. A known-good Host on :3080 is not proof.
 * For complete DSH coverage, manifest entries must be enumerated from the
 * installed DSH's generated Remote descriptors and exact Fetch/WS routes.
 */
import {readFile,writeFile} from 'node:fs/promises';
import {connect} from 'node:net';
import {connect as tlsConnect} from 'node:tls';
import {createHash,randomBytes} from 'node:crypto';

const [manifestFile,reportFile] = process.argv.slice(2);
const gatewayAddress=process.env.DSH_MOBILE_GATEWAY_URL;
const password=process.env.DSH_MOBILE_TEST_PASSWORD;
if(!manifestFile || !gatewayAddress || !password) {
  console.error('用法: DSH_MOBILE_GATEWAY_URL=http://127.0.0.1:39081 DSH_MOBILE_TEST_PASSWORD=... node scripts/audit-gateway-only.mjs <完整接口清单.json> [结果.json]');
  process.exit(2);
}
const gateway=new URL(gatewayAddress);
if(!['http:','https:'].includes(gateway.protocol) || gateway.pathname!=='/' || gateway.search || gateway.hash || gateway.username || gateway.password)throw Error('必须提供插件网关根地址');
const raw=JSON.parse(await readFile(manifestFile,'utf8'));
const interfaces=raw.interfaces;
if(!Array.isArray(interfaces) || !interfaces.length || !Number.isInteger(raw.declaredCount) || raw.declaredCount!==interfaces.length || typeof raw.sourceRevision!=='string' || !raw.sourceRevision.trim())
  throw Error('接口清单不完整：必须明确 sourceRevision、declaredCount 和非空 interfaces，且数量一致');
const keys=new Set();
for(const item of interfaces) {
  if(!item || typeof item.id!=='string'||!item.id.trim()||keys.has(item.id))throw Error('接口 ID 缺失或重复');
  keys.add(item.id);
  if(!['http','websocket'].includes(item.kind)||typeof item.path!=='string'||!item.path.startsWith('/')||item.path.startsWith('//')||item.path.includes('#'))throw Error(`${item.id}: 接口种类或路径错误`);
  if(!item.expect || !Number.isInteger(item.expect.status) ||
     (item.kind==='websocket' && item.expect.status!==101) ||
     (item.kind==='http' && (item.expect.status<200||item.expect.status>=300)))
    throw Error(`${item.id}: 必须明确成功状态码（HTTP 2xx / WebSocket 101），不能把 301/401/404/502 当作通过`);
  if(item.kind==='http' && !item.expect.contentType && item.expect.bodyContains===undefined && !item.expect.sha256 && item.expect.minimumBytes===undefined)
    throw Error(`${item.id}: HTTP 测试必须至少断言 Content-Type、响应内容、长度或 SHA-256，不能只检查状态码`);
}

function verifyResponse(response,id,instanceId) {
  if(new URL(response.url).origin!==gateway.origin)throw Error(`${id}: 请求离开插件网关`);
  if(response.headers.get('x-dsh-mobile-gateway')!==instanceId)throw Error(`${id}: 缺少插件代理标识（可能绕过网关）`);
  if(response.status>=300 && response.status<400) {
    const value=response.headers.get('location');
    if(value && new URL(value,gateway).origin!==gateway.origin)throw Error(`${id}: 响应重定向离开插件网关：${value}`);
  }
}

async function auditWebSocket(item,token,instanceId) {
  const target=new URL(item.path,gateway);
  if(target.origin!==gateway.origin)throw Error(`${item.id}: 非网关地址`);
  const secure=gateway.protocol==='https:';
  const port=Number(gateway.port||(secure?443:80));
  const socket=secure?tlsConnect({host:gateway.hostname,port,servername:gateway.hostname}):connect(port,gateway.hostname);
  const wsKey=randomBytes(16).toString('base64');
  const accept=createHash('sha1').update(wsKey+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  try {
    const text=await new Promise((resolve,reject)=>{
      let buffer=Buffer.alloc(0);
      const timer=setTimeout(()=>{socket.destroy();reject(Error('WebSocket 握手超时'));},8000);
      const finish=(err,data)=>{clearTimeout(timer);err?reject(err):resolve(data);};
      socket.once('error',finish);socket.once('close',()=>{if(!buffer.includes(Buffer.from('\r\n\r\n')))finish(Error('连接提前关闭'));});
      socket.on('data',part=>{
        buffer=Buffer.concat([buffer,part]);
        if(buffer.length>32768){socket.destroy();finish(Error('握手头过大'));return;}
        if(buffer.includes(Buffer.from('\r\n\r\n')))finish(null,buffer.toString('latin1'));
      });
      socket.once(secure?'secureConnect':'connect',()=>{
        socket.write(`GET ${target.pathname}${target.search} HTTP/1.1\r\nHost: ${gateway.host}\r\nAuthorization: Bearer ${token}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\nSec-WebSocket-Key: ${wsKey}\r\nSec-WebSocket-Version: 13\r\n\r\n`);
      });
    });
    const [head]=text.split('\r\n\r\n');
    const match=/^HTTP\/1\.1 (\d+)/.exec(head);
    if(Number(match?.[1])!==101)throw Error(`WebSocket 预期 101，实际 ${match?.[1]??'无响应'}`);
    if(!head.toLowerCase().includes(`x-dsh-mobile-gateway: ${instanceId}`.toLowerCase()))throw Error('WebSocket 未经过网关');
    if(!/\r\nupgrade: websocket/i.test('\r\n'+head))throw Error('WebSocket 未完成 Upgrade');
    const matchAccept=/^sec-websocket-accept:\s*(.+)\s*$/im.exec(head);
    if(matchAccept?.[1]?.trim()!==accept)throw Error('WebSocket 握手的 Sec-WebSocket-Accept 不合法');
    return {status:101,bytes:0};
  }finally{socket.destroy();}
}

const results=[];
const record=(id,ok,details)=>{results.push({id,ok,...details});console.log(`${ok?'[通过]':'[失败]'} ${id}: ${details.message||''}`);};
const discovery=await fetch(new URL('/_dsh_mobile/v1/info',gateway),{redirect:'manual',signal:AbortSignal.timeout(10000)});
if(discovery.status!==200)throw Error(`插件网关发现失败: ${discovery.status}`);
const info=await discovery.json();
if(info.protocol!=='dsh-mobile/1'||typeof info.instanceId!=='string')throw Error('网关发现响应无效');
const auth=await fetch(new URL('/_dsh_mobile/v1/login',gateway),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password}),redirect:'manual',signal:AbortSignal.timeout(15000)});
if(auth.status!==200)throw Error(`网关密码认证失败: HTTP ${auth.status}`);
const data=await auth.json();
if(!data.token||data.instanceId!==info.instanceId)throw Error('插件登录身份不匹配');
for(const item of interfaces) {
  try {
    if(item.kind==='websocket'){
      const result=await auditWebSocket(item,data.token,info.instanceId);
      record(item.id,true,{status:result.status,message:'网关 WebSocket 升级成功（仅传输层；帧级语义未覆盖）'});
      continue;
    }
    const target=new URL(item.path,gateway);
    if(target.origin!==gateway.origin)throw Error('目标地址不在网关');
    const headers={...item.headers,Authorization:`Bearer ${data.token}`};
    const init={method:item.method||'GET',headers,redirect:'manual',signal:AbortSignal.timeout(item.timeoutMs||20000)};
    if(item.body!==undefined)init.body=typeof item.body==='string'?item.body:JSON.stringify(item.body);
    const response=await fetch(target,init);
    verifyResponse(response,item.id,info.instanceId);
    if(response.status!==item.expect.status)throw Error(`预期 HTTP ${item.expect.status}，实际 ${response.status}`);
    const ct=response.headers.get('content-type')||'';
    if(target.pathname.startsWith('/api/') && /text\/html/i.test(ct))throw Error('API 返回了 HTML（可能误入 SPA 回退页）');
    if(item.expect.contentType && !ct.includes(item.expect.contentType))throw Error(`Content-Type 不匹配：${ct}`);
    const body=Buffer.from(await response.arrayBuffer());
    if(item.expect.minimumBytes!==undefined && body.length<item.expect.minimumBytes)throw Error(`响应长度过短：${body.length}`);
    if(item.expect.bodyContains!==undefined && !body.toString('utf8').includes(item.expect.bodyContains))throw Error('响应内容缺少预期字段');
    if(item.expect.sha256 && createHash('sha256').update(body).digest('hex')!==item.expect.sha256)throw Error('响应字节 SHA-256 不匹配');
    record(item.id,true,{status:response.status,bytes:body.length});
  }catch(e){record(item.id,false,{message:e.message});}
}
const failed=results.filter(x=>!x.ok).length;
const report={checkedAt:new Date().toISOString(),gateway:gateway.origin,instanceId:info.instanceId,sourceRevision:raw.sourceRevision,declaredCount:raw.declaredCount,testedCount:results.length,passedCount:results.length-failed,failedCount:failed,completeForDeclaredManifest:failed===0&&results.length===raw.declaredCount,warning:'仅表示提供的清单通过插件代理。是否覆盖 DSH 的全部接口，需与相同版本 DSH 生成的 Remote 描述符及确切 Fetch/WebSocket 路由逐项核对。',results};
if(reportFile)await writeFile(reportFile,JSON.stringify(report,null,2));
console.log(JSON.stringify({gateway:report.gateway,declaredCount:report.declaredCount,passedCount:report.passedCount,failedCount:report.failedCount},null,2));
if(failed>0 || results.length!==raw.declaredCount)process.exitCode=1;
