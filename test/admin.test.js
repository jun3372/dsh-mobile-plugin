import test from 'node:test';
import assert from 'node:assert/strict';
import { createAdminHandler } from '../lib/index.js';
import { EventEmitter } from 'node:events';
import { Readable } from 'node:stream';

function req(method,url,content){
  const r=Readable.from(content?[Buffer.from(JSON.stringify(content))]:[]);
  r.method=method;r.url=url;r.socket={remoteAddress:'127.0.0.1'};
  r.headers={host:'127.0.0.1:3080',origin:'http://127.0.0.1:3080','content-type':'application/json'};
  return r;
}
function res(){const r={code:0,body:'',headersSent:false,writeHead(code){this.code=code;this.headersSent=true;},end(content){this.body=content||'';}};return r;}
const service={identity:{id:'test'},closed:false,snapshot:async()=>({ok:true}),configure:async()=>({updated:true}),qr:async()=>({dataUrl:'mock'})};
test('admin routes fail closed for remote caller, missing auth or rejection',async()=>{
  let r=req('GET','/dsh-mobile/admin/status');r.socket.remoteAddress='192.168.1.1';let s=res();await createAdminHandler(service,{requestRejection:()=>undefined})(r,s);assert.equal(s.code,403);
  r=req('GET','/dsh-mobile/admin/status');s=res();await createAdminHandler(service,{})(r,s);assert.equal(s.code,503);
  r=req('GET','/dsh-mobile/admin/status');s=res();await createAdminHandler(service,{requestRejection:()=>403})(r,s);assert.equal(s.code,403);
});
test('admin status and configure dispatch only for authorized loopback callers',async()=>{
  const handler=createAdminHandler(service,{requestRejection:()=>undefined});
  let s=res();await handler(req('GET','/dsh-mobile/admin/status'),s);assert.equal(s.code,200);assert.deepEqual(JSON.parse(s.body),{ok:true});
  s=res();await handler(req('POST','/dsh-mobile/admin/configure',{mode:'lan',patch:{enabled:true}}),s);assert.equal(s.code,200);assert.deepEqual(JSON.parse(s.body),{updated:true});
});
