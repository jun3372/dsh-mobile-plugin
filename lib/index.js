import { isLoopback, originAllowed } from './security.js';
import { MobileService } from './service.js';

export const name = 'dsh-mobile-plugin';
export const inject = ['webServer', 'connection'];

function send(res, status, data) {
  if(res.headersSent) return;
  const body=JSON.stringify(data);
  res.writeHead(status,{'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});
  res.end(body);
}
async function readBody(req) {
  if(!/^application\/json(?:\s*;|$)/i.test(req.headers['content-type']||'')) throw new Error('application/json required');
  const pieces=[]; let size=0;
  for await (const piece of req) { size+=piece.length; if(size>16_384) throw new Error('body too large');pieces.push(piece); }
  return JSON.parse(Buffer.concat(pieces).toString('utf8'));
}

export function createAdminHandler(service, connection) {
  return async function handler(req,res) {
    // This handler is for the LOCAL DSH Web management UI ONLY.
    // On DSH versions that do not supply requestRejection, fail closed.
    if(!isLoopback(req.socket.remoteAddress)) return send(res,403,{error:'local_admin_only'});
    if(!originAllowed(req)) return send(res,403,{error:'invalid_origin'});
    if(typeof connection?.requestRejection !== 'function') return send(res,503,{error:'dsh_connection_auth_unavailable'});
    let rejection;
    try { rejection=connection.requestRejection(req); }
    catch {return send(res,403,{error:'dsh_authorization_error'});}
    if(rejection!==undefined) return send(res,Number.isInteger(rejection)?rejection:403,{error:'dsh_authorization_rejected'});
    if(!service.identity || service.closed) return send(res,503,{error:'service_unavailable'});
    try {
      const url=new URL(req.url,'http://localhost');
      if(url.pathname==='/dsh-mobile/admin/status' && req.method==='GET') return send(res,200,await service.snapshot());
      if(url.pathname==='/dsh-mobile/admin/qr' && req.method==='GET') {
        const mode=url.searchParams.get('mode');const target=url.searchParams.get('url');
        return send(res,200,await service.qr(mode,target));
      }
      if(url.pathname==='/dsh-mobile/admin/configure' && req.method==='POST') {
        const data=await readBody(req);
        if(typeof data?.mode!=='string') return send(res,400,{error:'mode_required'});
        return send(res,200,await service.configure(data.mode,data.patch));
      }
      return send(res,404,{error:'not_found'});
    } catch(e) {
      return send(res,400,{error:'invalid_request',message:e.message});
    }
  };
}

export function apply(ctx) {
  // Cordis 的 info/warn 有可能仅存入内存缓冲区；同时输出到 stderr，
  // 让启动、重试和异常事件出现在 `dsh web` 的运行终端/进程日志中。
  // 不向 stdout 写入内容，避免干扰上游 RPC/ACP 流。
  const namedLogger=typeof ctx.logger==='function' ? ctx.logger('dsh-mobile') : console;
  const logger=Object.fromEntries(['info','warn','error'].map(level=>[level,(message)=>{
    try{namedLogger[level]?.(message);}catch{};
    if(namedLogger!==console) {
      try{process.stderr.write(`[${new Date().toISOString()}] ${level.toUpperCase()} ${message}\n`);}catch{}
    }
  }]));
  const service=new MobileService({logger,
    authenticatedUrl:typeof ctx.connection?.authenticatedUrl==='function'? (base)=>ctx.connection.authenticatedUrl(base):undefined,
    upstreamResolver:()=>Number.isInteger(ctx.webServer?.port)&&ctx.webServer.port>0?`http://127.0.0.1:${ctx.webServer.port}`:undefined,
  });
  ctx.effect(()=>{
    const startup=service.init().then(()=>logger.info?.('[dsh-mobile] 服务端插件启动流程已执行，网络实际状态请以配置页为准'))
      .catch(e=>logger.error?.(`[dsh-mobile] 插件初始化失败：${e.message}`));
    return ()=>{
      service.closed=true; // guard against a late init after the Cordis scope is disposed
      startup.then(()=>service.stop()).catch(e=>logger.warn?.('[dsh-mobile] 插件停止异常',e));
    };
  },'dsh-mobile service lifecycle');
  ctx.effect(()=>ctx.webServer.register({
    kind:'prefix', path:'/dsh-mobile/admin', handler:createAdminHandler(service,ctx.connection),
  }),'dsh-mobile local admin routes');
}
