import {readFile} from 'node:fs/promises';
import {connect} from 'node:net';
import assert from 'node:assert/strict';

const [port,file]=process.argv.slice(2);
if(!port||!file)throw Error('Usage: node live-dsh-proxy-smoke.mjs <gateway-port> <settings.json>');
const settings=JSON.parse(await readFile(file,'utf8'));
const url=`http://127.0.0.1:${port}`;
function throughGateway(res,name) {
  assert.equal(new URL(res.url).origin,url,`${name} 不得绕过插件网关`);
  assert.equal(res.headers.get('x-dsh-mobile-gateway'),identity.instanceId,`${name} 必须有网关转发标识`);
  assert.ok(res.status>=200 && res.status<300,`${name} 必须真实成功，不能以 404/401/502 替代`);
}

const info=await fetch(`${url}/_dsh_mobile/v1/info`,{redirect:'manual'});
assert.equal(info.status,200,'服务发现必须返回 200');
const identity=await info.json();assert.equal(identity.protocol,'dsh-mobile/1');
const noSession=await fetch(`${url}/api/__dsh_mobile_smoke__`,{redirect:'manual'});
assert.equal(noSession.status,401,'没有 Mobile 凭证应拒绝');
const login=await fetch(`${url}/_dsh_mobile/v1/login`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({password:settings.lan.password}),redirect:'manual'});
assert.equal(login.status,200,'使用配置的局域网访问密码登录应成功');
const {token}=await login.json();
const auth={Authorization:`Bearer ${token}`};
const page=await fetch(`${url}/`,{headers:auth,redirect:'manual'});
throughGateway(page,'DSH 首页');
assert.match(page.headers.get('content-type')||'',/text\/html/i,'首页必须是 HTML 响应');
// A fake/nonexistent API returning 404 must NEVER count as proof that
// DSH business Remote APIs work. This is a negative control only.
const nonexistent=await fetch(`${url}/api/__dsh_mobile_smoke__`,{headers:auth,redirect:'manual'});
assert.equal(new URL(nonexistent.url).origin,url,'404 负向测试必须留在网关');
assert.equal(nonexistent.headers.get('x-dsh-mobile-gateway'),identity.instanceId,'404 必须由网关代理');
assert.equal(nonexistent.status,404,'不存在的 API 应由真实 Host 返回 404；不计入通过的业务接口');
console.log('严格网关验证：发现、登录和首页通过；不存在接口的 404 作为负向对照，不计入 API 覆盖。');

const wsResult=await new Promise((resolve,reject)=>{
  const socket=connect(Number(port),'127.0.0.1');
  let received='';const timeout=setTimeout(()=>{socket.destroy();reject(new Error('WebSocket 连接超时'));},7000);
  socket.on('error',e=>{clearTimeout(timeout);reject(e);});
  socket.on('connect',()=>socket.write(`GET /api/remote.mux HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nAuthorization: Bearer ${token}\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n`));
  socket.on('data',buf=>{received+=buf.toString();if(received.includes('\r\n\r\n')){clearTimeout(timeout);socket.destroy();resolve(received);}});
  socket.on('close',()=>{if(!received.includes('\r\n\r\n')){clearTimeout(timeout);reject(new Error('WebSocket 在响应头前关闭'));}});
});
assert.match(wsResult,/^HTTP\/1\.1 101 Switching Protocols/, 'DSH 原生 WebSocket 升级必须返回 101');
assert.match(wsResult,new RegExp(`x-dsh-mobile-gateway: ${identity.instanceId}`,'i'),'WebSocket 必须经由插件网关');
console.log('WebSocket /api/remote.mux 升级：通过');
console.log('注意：这里只验证基础代理链路，不代表 DSH 全部业务接口通过。全部接口必须使用 audit-gateway-only.mjs 和版本匹配的完整清单。');
