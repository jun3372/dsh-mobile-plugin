import { networkInterfaces } from 'node:os';
import { createHash } from 'node:crypto';
import { dirname, join } from 'node:path';
import { loadSettings, saveSettings, setPassword } from './settings.js';
import { identityFrom, safeUpstream } from './security.js';
import { MobileGateway } from './gateway.js';
import { TunnelManager } from './tunnel.js';
import { FrpcManager, validFrpcHost, frpcPublicUrl } from './frpc.js';
import { qrPngDataUrl } from './qr.js';
import { UpstreamBrowserSession } from './upstream-auth.js';
import { validateDownloadSource, downloadSourceLabel } from './download-source.js';

function addresses(){
  const result=[];
  for(const [name,entries] of Object.entries(networkInterfaces()))for(const a of entries||[])
    if(a.family==='IPv4'&&!a.internal&&!a.address.startsWith('169.254.'))result.push({interface:name,address:a.address});
  return result;
}
function validPort(n){return Number.isInteger(n)&&n>=0&&n<65536;}
function sanitizeHostname(value){
  const u=new URL(value);
  if(u.protocol!=='https:'||u.username||u.password||u.pathname!=='/'||u.search||u.hash)throw new Error('Provide an https://domain hostname only');
  return u.origin;
}
export class MobileService{
  constructor({file,tunnel,frpc,gatewayFactory,logger=console,addressProvider=addresses,authenticatedUrl,upstreamResolver}={}){
    this.file=file;this.logger=logger;this.addressProvider=addressProvider;this.authenticatedUrl=authenticatedUrl;this.upstreamResolver=upstreamResolver;this.upstreamSession=null;
    this.tunnel=tunnel||new TunnelManager();
    this.frpc=frpc||new FrpcManager({file:file?join(dirname(file),'frpc.toml'):undefined});
    this.gatewayFactory=gatewayFactory||((opts)=>new MobileGateway(opts));
    this.settings=null;this.identity=null;this.gateway=null;
    this.lastError={lan:'',public:'',frpc:''};this.frpcRetryTimer=null;this.frpcRetryDelay=2000;this.retryTimer=null;this.retryDelay=2000;this.gatewayRetryTimer=null;this.gatewayRetryDelay=2000;
    this.lastTunnelState='stopped';this.lastFrpcState='stopped';
    this.closed=false;this.queue=Promise.resolve();this.recentLogs=[];this.startedAt=null;
    this.tunnel.on('change',()=>this.onTunnelChange());
    this.tunnel.on('lost',()=>{
      if(!this.closed&&this.settings?.public.enabled)this.scheduleRetry();
    });
    this.frpc.on('change',()=>this.onFrpcChange());
    this.frpc.on('install',message=>this.log('info',message));
    this.frpc.on('lost',()=>{if(!this.closed&&this.settings?.frpc.enabled)this.scheduleFrpcRetry();});
  }
  log(level,message){
    const item={time:new Date().toISOString(),level,message:String(message)};
    this.recentLogs.push(item);
    if(this.recentLogs.length>60)this.recentLogs.shift();
    this.logger[level]?.(`[dsh-mobile] ${item.message}`);
  }
  onTunnelChange(){
    const {state,url,error}=this.tunnel.snapshot();
    if(state===this.lastTunnelState)return;
    this.lastTunnelState=state;
    if(this.closed)return;
    if(state==='online'){
      this.clearRetry();this.lastError.public='';
      this.log('info',`公网 Cloudflare 已连接${url ? `：${url}` : ''}`);
    } else if(state==='connecting')this.log('info','公网 Cloudflare 隧道连接中');
    else if(state==='error')this.log('warn',`公网 Cloudflare 连接异常：${error||'未知错误'}`);
    else if(state==='stopped')this.log('info','公网 Cloudflare 隧道已停止');
  }
  onFrpcChange(){
    const {state,url,error}=this.frpc.snapshot();
    if(state===this.lastFrpcState)return;
    this.lastFrpcState=state;if(this.closed)return;
    if(state==='online'){this.clearFrpcRetry();this.lastError.frpc='';this.log('info',`frpc 隧道已连接${url?'：'+url:''}`);}
    else if(state==='connecting')this.log('info','frpc 正在连接到 frps 服务端');
    else if(state==='error')this.log('warn',`frpc 连接异常：${error||'未知错误'}`);
    else this.log('info','frpc 隧道已停止');
  }
  async init(){
    this.startedAt=new Date().toISOString();
    this.log('info','正在启动插件，准备恢复上次保存的网络配置');
    this.settings=await loadSettings(this.file);
    if(this.closed)return this;
    this.log('info',`配置已加载；自动恢复：局域网=${this.settings.lan.enabled?'开':'关'}，Cloudflare=${this.settings.public.enabled?'开':'关'}，frpc=${this.settings.frpc.enabled?'开':'关'}，共享端口=${this.settings.gateway.port}`);
    if (!process.env.DSH_MOBILE_UPSTREAM && typeof this.upstreamResolver === 'function') {
      const resolved=this.upstreamResolver();
      if(resolved)this.settings.upstream=safeUpstream(resolved).origin;
    }
    safeUpstream(this.settings.upstream);
    if(typeof this.authenticatedUrl==='function') {
      this.upstreamSession=new UpstreamBrowserSession({upstream:this.settings.upstream,authenticatedUrl:this.authenticatedUrl});
      try { await this.upstreamSession.getCookie();this.log('info','DSH Host 内部会话已建立，可转发原生 API 和 WebSocket'); }
      catch(e) { this.log('warn',`DSH Host 内部会话初始化失败：${e.message}`); }
    } else this.log('warn','DSH Connection 未提供内部会话接口，移动端原生 API 可能需要额外的 Host 身份验证');
    this.identity=identityFrom(this.settings.identity.privateKey);
    if(this.settings.lan.enabled||this.settings.public.enabled||this.settings.frpc.enabled){
      try{await this.startGateway();}catch(e){this.lastError.lan=this.lastError.public=e.message;this.log('error',`共享代理网关启动失败：${e.message}`);this.scheduleGatewayRetry();}
    }
    if(this.gateway&&this.settings.public.enabled)await this.startTunnel();
    if(this.gateway&&this.settings.frpc.enabled)await this.startFrpc();
    const state=await this.snapshot();
    this.log('info',`启动状态：局域网=${state.lan.running?'运行中':(state.lan.enabled?'启动失败/等待重试':'已关闭')}；Cloudflare=${state.public.running?'运行中':(state.public.enabled?'连接中/等待重试':'已关闭')}；frpc=${state.frpc.running?'运行中':(state.frpc.enabled?'连接中/等待重试':'已关闭')}`);
    return this;
  }
  async startGateway(){
    if(this.gateway)return;
    const preferred=this.settings.gateway.port;
    const g=this.gatewayFactory({upstream:this.settings.upstream,instance:this.identity,
      passwordHashes:{lan:this.settings.lan.hash,public:this.settings.public.hash},
      enabledModes:{lan:this.settings.lan.enabled,public:this.settings.public.enabled||this.settings.frpc.enabled},
      port:preferred,logger:this.logger,upstreamSession:this.upstreamSession});
    for(let attempt=0;;attempt++){
      try{await g.start();break;}
      catch(e){
        const busy=e&&((e.code==='EADDRINUSE')||String(e.message).includes('EADDRINUSE'));
        if(!busy||preferred===0||attempt>=20)throw e;
        g.requestedPort=preferred+1+attempt;
      }
    }
    this.gateway=g;this.lastError.lan='';this.clearGatewayRetry();
    this.log('info',`共享代理网关监听成功：${g.bindAddress||'0.0.0.0'}:${g.port}（局域网、Cloudflare 与 frpc 共用端口）`);
    if(g.port!==preferred)this.log('warn',`首选端口 ${preferred} 被占用，已自动顺延至 ${g.port}；配置中的首选端口保持不变`);
    if(this.settings.lan.enabled)this.log('info','局域网服务已启动，手机可使用局域网二维码和密码连接');
  }
  async stopGateway(){const g=this.gateway;this.gateway=null;if(g){await g.stop();this.log('info','共享代理网关已停止');}}
  async startTunnel(){
    if(this.closed||!this.gateway||!this.settings.public.enabled)return;
    this.log('info',`正在启动 Cloudflare ${this.settings.public.mode==='quick'?'快速隧道':'固定域名隧道'}，连接到本机代理端口 ${this.gateway.port}`);
    try{
      await this.tunnel.start({mode:this.settings.public.mode,originPort:this.gateway.port,
        hostname:this.settings.public.hostname,token:this.settings.public.token,binaryPath:this.settings.public.binaryPath||'',
        downloadSource:this.settings.public.downloadSource,downloadMirror:this.settings.public.downloadMirror});
      this.lastError.public='';
      this.onTunnelChange(); // also observe injected tunnel adapters which do not emit events
    }catch(e){
      this.lastError.public=e.message;
      this.log('warn',`公网 Cloudflare 启动失败：${e.message}`);
      this.scheduleRetry();
    }
  }
  async startFrpc(){
    if(this.closed||!this.gateway||!this.settings.frpc.enabled)return;
    this.log('info',`正在启动 frpc 隧道，将 frps 远程端口映射到共享代理端口 ${this.gateway.port}`);
    try{await this.frpc.start({...this.settings.frpc,originPort:this.gateway.port});
      this.lastError.frpc='';this.onFrpcChange();
    }catch(e){this.lastError.frpc=e.message;this.log('warn',`frpc 启动失败：${e.message}`);this.scheduleFrpcRetry();}
  }
  clearFrpcRetry(){if(this.frpcRetryTimer)clearTimeout(this.frpcRetryTimer);this.frpcRetryTimer=null;this.frpcRetryDelay=2000;}
  scheduleFrpcRetry(){
    if(this.frpcRetryTimer||this.closed||!this.settings?.frpc.enabled||!this.gateway)return;
    const delay=this.frpcRetryDelay;this.frpcRetryDelay=Math.min(delay*2,60_000);
    this.log('warn',`frpc 将在 ${Math.round(delay/1000)} 秒后重试`);
    this.frpcRetryTimer=setTimeout(()=>{this.frpcRetryTimer=null;
      this.enqueue(async()=>{if(!this.closed&&this.gateway&&this.settings.frpc.enabled)await this.startFrpc();})
        .catch(e=>this.log('error',`frpc 重试异常：${e.message}`));
    },delay);this.frpcRetryTimer.unref?.();
  }
  clearRetry(){if(this.retryTimer)clearTimeout(this.retryTimer);this.retryTimer=null;this.retryDelay=2000;}
  clearGatewayRetry(){if(this.gatewayRetryTimer)clearTimeout(this.gatewayRetryTimer);this.gatewayRetryTimer=null;this.gatewayRetryDelay=2000;}
  scheduleGatewayRetry(){
    if(this.gatewayRetryTimer||this.closed||this.gateway||!this.settings||(!this.settings.lan.enabled&&!this.settings.public.enabled&&!this.settings.frpc.enabled))return;
    const delay=this.gatewayRetryDelay;
    this.log('warn',`共享代理网关将在 ${Math.round(delay/1000)} 秒后重试`);
    this.gatewayRetryTimer=setTimeout(()=>{
      this.gatewayRetryTimer=null;
      this.enqueue(async()=>{
        if(this.closed||this.gateway||(!this.settings.lan.enabled&&!this.settings.public.enabled&&!this.settings.frpc.enabled))return;
        try{await this.startGateway();if(this.settings.public.enabled)await this.startTunnel();if(this.settings.frpc.enabled)await this.startFrpc();}
        catch(e){this.lastError.lan=this.lastError.public=e.message;this.log('error',`共享代理网关重试失败：${e.message}`);
          this.gatewayRetryDelay=Math.min(this.gatewayRetryDelay*2,60_000);this.scheduleGatewayRetry();}
      }).catch(e=>this.log('error',`网关重试任务异常：${e.message}`));
    },delay);
    this.gatewayRetryTimer.unref?.();
  }
  scheduleRetry(){
    if(this.retryTimer||this.closed||!this.settings?.public.enabled||!this.gateway)return;
    const delay=this.retryDelay;
    this.retryDelay=Math.min(delay*2,60_000);
    this.log('warn',`公网 Cloudflare 将在 ${Math.round(delay/1000)} 秒后重试`);
    this.retryTimer=setTimeout(()=>{
      this.retryTimer=null;
      this.enqueue(async()=>{
        if(this.closed||!this.gateway||!this.settings.public.enabled)return;
        await this.startTunnel();
        // startTunnel() schedules the next retry on errors; do not schedule twice.
      }).catch(e=>this.log('error',`公网重试任务异常：${e.message}`));
    },delay);
    this.retryTimer.unref?.();
  }
  enqueue(fn){const task=this.queue.then(fn);this.queue=task.catch(()=>{});return task;}
  async configure(mode,patch){return this.enqueue(()=>this._configure(mode,patch));}
  async _configure(mode,patch){
    if(this.closed)throw new Error('service closed');
    if(!['base','lan','public','frpc'].includes(mode)||!patch||typeof patch!=='object'||Array.isArray(patch))throw new Error('invalid configuration');
    const allowed=mode==='base' ? ['port','lanPassword','publicPassword'] : mode==='lan' ? ['enabled','port','preferredAddress','passwordMode','password','rotatePassword'] : mode==='frpc' ? ['enabled','port','serverAddr','serverPort','remotePort','authToken','proxyName','publicUrl','binaryPath','downloadSource','downloadMirror','password'] : ['enabled','port','passwordMode','password','rotatePassword','mode','hostname','token','binaryPath','downloadSource','downloadMirror'];
    if(Object.keys(patch).some(key=>!allowed.includes(key)))throw new Error('unknown configuration field');
    const previous=structuredClone(this.settings);
    const next=structuredClone(this.settings);
    const entry=mode==='base'?null:next[mode];
    if(mode==='base'){
      // 共享字段一次校验、一次持久化、一次应用，避免端口和两种密码部分保存。
      if('lanPassword' in patch)setPassword(next,'lan','fixed',patch.lanPassword);
      if('publicPassword' in patch)setPassword(next,'public','fixed',patch.publicPassword);
    }
    if('enabled' in patch){if(typeof patch.enabled!=='boolean')throw new Error('enabled must be boolean');entry.enabled=patch.enabled;}
    if('port' in patch){if(!validPort(patch.port)||(mode==='base'&&patch.port===0))throw new Error('invalid port');next.gateway.port=patch.port;}
    if(mode==='public'||mode==='frpc'){
      const source=patch.downloadSource??entry.downloadSource??'official';
      const mirror=patch.downloadMirror??entry.downloadMirror??'';
      const checked=validateDownloadSource(source,mirror);
      entry.downloadSource=checked.source;entry.downloadMirror=checked.mirror;
    }
    if(mode==='lan' && 'preferredAddress' in patch){
      const addr=patch.preferredAddress;
      if(typeof addr!=='string' || (addr && !this.addressProvider().some(a=>a.address===addr)))
        throw new Error('所选局域网 IP 不可用，请重新选择');
      entry.preferredAddress=addr;
    }
    if(mode==='public'){
      if('mode' in patch){if(!['quick','named'].includes(patch.mode))throw new Error('invalid tunnel mode');entry.mode=patch.mode;}
      if('hostname' in patch)entry.hostname=patch.hostname?sanitizeHostname(patch.hostname):'';
      if('token' in patch){if(typeof patch.token!=='string'||patch.token.length>8192)throw new Error('invalid tunnel token');entry.token=patch.token;}
      if('binaryPath' in patch){if(typeof patch.binaryPath!=='string'||patch.binaryPath.length>2048)throw new Error('invalid cloudflared executable path');entry.binaryPath=patch.binaryPath;}
      if(entry.enabled&&entry.mode==='named'&&(!entry.token||!entry.hostname))throw new Error('named mode requires Cloudflare token and hostname');
    }
    if(mode==='frpc'){
      for(const field of ['serverAddr','authToken','proxyName','publicUrl','binaryPath'])if(field in patch){
        if(typeof patch[field]!=='string'||patch[field].length>(field==='authToken'?8192:2048))throw new Error('frpc 字段内容无效');
        entry[field]=patch[field];
      }
      for(const field of ['serverPort','remotePort'])if(field in patch){if(!validPort(patch[field])||patch[field]===0)throw new Error('frpc 端口无效');entry[field]=patch[field];}
      if(entry.enabled){
        if(!validFrpcHost(entry.serverAddr)||!entry.remotePort||!entry.serverPort)throw new Error('请填写有效的 frps 地址、端口和远程端口');
        if(!/^[a-zA-Z0-9_-]{1,64}$/.test(entry.proxyName))throw new Error('frpc 映射名称无效');
        frpcPublicUrl(entry);
      }else if(entry.publicUrl)frpcPublicUrl({...entry,serverAddr:entry.serverAddr||'localhost',remotePort:entry.remotePort||80});
    }
    if(mode==='frpc'&&'password' in patch)setPassword(next,'public','fixed',patch.password);
    if('rotatePassword' in patch&&typeof patch.rotatePassword!=='boolean')throw new Error('rotatePassword must be boolean');
    if(mode!=='frpc'&&('passwordMode' in patch||'password' in patch||patch.rotatePassword)){
      const kind=patch.passwordMode??entry.passwordMode;
      if(patch.rotatePassword&&kind!=='random')throw new Error('rotatePassword only applies to random mode');
      if(kind==='fixed' && !('password' in patch) && previous[mode].passwordMode==='fixed'){
        // Setting other fields never rewrites an existing fixed password.
      }else{
        setPassword(next,mode,kind,patch.password,{rotate:patch.rotatePassword});
      }
    }
    const portChanged=next.gateway.port!==previous.gateway.port;
    const publicChanged=mode==='public'&&(previous.public.enabled!==next.public.enabled||previous.public.mode!==next.public.mode||previous.public.hostname!==next.public.hostname||previous.public.token!==next.public.token||previous.public.binaryPath!==next.public.binaryPath||previous.public.downloadSource!==next.public.downloadSource||previous.public.downloadMirror!==next.public.downloadMirror);
    const frpcChanged=mode==='frpc' && JSON.stringify(previous.frpc)!==JSON.stringify(next.frpc);
    this.settings=next;
    await saveSettings(next,this.file);
    if(mode==='lan' && next.lan.preferredAddress!==previous.lan.preferredAddress)
      this.log('info',`局域网展示地址已切换为 ${next.lan.preferredAddress||'自动选择'}`);
    if(mode==='base')this.log('info',`基础配置已保存；共享端口=${next.gateway.port}；访问密码已按需更新`);
    else this.log('info',`${mode==='lan'?'局域网':mode==='frpc'?'frpc 隧道':'公网'}配置已保存；启用=${entry.enabled?'是':'否'}；下次启动${entry.enabled?'自动恢复':'保持关闭'}；共享端口=${next.gateway.port}`);
    try{
      if(portChanged){this.clearRetry();this.clearFrpcRetry();this.clearGatewayRetry();this.tunnel.stop();this.frpc.stop();await this.stopGateway();}
      if(!next.lan.enabled&&!next.public.enabled&&!next.frpc.enabled){this.clearRetry();this.clearFrpcRetry();this.clearGatewayRetry();this.tunnel.stop();this.frpc.stop();await this.stopGateway();}
      else {
        if(!this.gateway)await this.startGateway();
        for(const name of ['lan','public'])this.gateway.setMode(name,name==='public'?(next.public.enabled||next.frpc.enabled):next.lan.enabled,next[name].hash);
        if(publicChanged||portChanged){this.clearRetry();this.tunnel.stop();if(next.public.enabled)await this.startTunnel();}
        else if(next.public.enabled&&this.tunnel.state==='stopped')await this.startTunnel();
        if(frpcChanged||portChanged){this.clearFrpcRetry();this.frpc.stop();if(next.frpc.enabled)await this.startFrpc();}
        else if(next.frpc.enabled&&this.frpc.state==='stopped')await this.startFrpc();
      }
      this.lastError.lan='';
      if(!next.public.enabled)this.lastError.public='';
      if(!next.frpc.enabled)this.lastError.frpc='';
    }catch(e){this.lastError[mode==='base'?'lan':mode]=e.message;this.log('error',`${mode==='base'?'基础配置':mode==='lan'?'局域网':mode==='frpc'?'frpc':'公网'}配置生效失败：${e.message}`);throw e;}
    return this.snapshot();
  }
  async snapshot(){
    const lans=this.addressProvider();const gateway=this.gateway;const port=gateway?.port??this.settings.gateway.port;
    const preferred=this.settings.lan.preferredAddress||'';
    const selectedAddress=lans.some(a=>a.address===preferred)?preferred:(lans[0]?.address||'');
    const lanUrls=gateway&&this.settings.lan.enabled ? lans.map(a=>`http://${a.address}:${port}`):[];
    const tunnel=this.tunnel.snapshot();const frpc=this.frpc.snapshot();
    const publicUrl=gateway&&this.settings.public.enabled&&tunnel.state==='online'?tunnel.url:'';
    const frpcUrl=gateway&&this.settings.frpc.enabled&&frpc.state==='online'?frpc.url:'';
    return {
      protocol:'dsh-mobile/1',instanceId:this.identity.id,publicKey:this.identity.publicKey,
      gateway:{running:!!gateway,port,upstreamAuthenticated:!!this.upstreamSession?.cookie},base:{port:this.settings.gateway.port,instanceId:this.identity.id,lanPassword:this.settings.lan.password||'',publicPassword:this.settings.public.password||'',lanPasswordRecoveryRequired:this.settings.lan.passwordMode==='fixed'&&!this.settings.lan.password,publicPasswordRecoveryRequired:this.settings.public.passwordMode==='fixed'&&!this.settings.public.password},startedAt:this.startedAt,recentLogs:this.recentLogs.slice(-30),
      lan:{enabled:this.settings.lan.enabled,autoStart:this.settings.lan.enabled,running:!!gateway&&this.settings.lan.enabled,port,
        addresses:lans,urls:lanUrls,preferredAddress:preferred,selectedAddress,
        url:gateway&&this.settings.lan.enabled&&selectedAddress?`http://${selectedAddress}:${port}`:'',passwordMode:this.settings.lan.passwordMode,
        visiblePassword:this.settings.lan.password||null,qrRevision:createHash('sha256').update(this.settings.lan.hash).digest('hex').slice(0,16),passwordRecoveryRequired:this.settings.lan.passwordMode==='fixed'&&!this.settings.lan.password,error:this.lastError.lan},
      public:{enabled:this.settings.public.enabled,autoStart:this.settings.public.enabled,running:!!gateway&&this.settings.public.enabled&&tunnel.state==='online',port,
        mode:this.settings.public.mode,hostname:this.settings.public.hostname,hasToken:!!this.settings.public.token,
        binaryPath:this.settings.public.binaryPath||'',downloadSource:this.settings.public.downloadSource,downloadMirror:this.settings.public.downloadMirror,url:publicUrl,tunnelState:tunnel.state,
        error:this.lastError.public||tunnel.error,passwordMode:this.settings.public.passwordMode,qrRevision:createHash('sha256').update(this.settings.public.hash).digest('hex').slice(0,16),
        visiblePassword:this.settings.public.password||null,passwordRecoveryRequired:this.settings.public.passwordMode==='fixed'&&!this.settings.public.password},
      frpc:{enabled:this.settings.frpc.enabled,autoStart:this.settings.frpc.enabled,running:!!frpcUrl,port,
        serverAddr:this.settings.frpc.serverAddr,serverPort:this.settings.frpc.serverPort,remotePort:this.settings.frpc.remotePort,
        proxyName:this.settings.frpc.proxyName,publicUrl:this.settings.frpc.publicUrl,binaryPath:this.settings.frpc.binaryPath,downloadSource:this.settings.frpc.downloadSource,downloadMirror:this.settings.frpc.downloadMirror,
        hasToken:!!this.settings.frpc.authToken,url:frpcUrl,tunnelState:frpc.state,error:this.lastError.frpc||frpc.error,
        passwordMode:this.settings.public.passwordMode,qrRevision:createHash('sha256').update(this.settings.public.hash).digest('hex').slice(0,16),visiblePassword:this.settings.public.password||null,passwordRecoveryRequired:this.settings.public.passwordMode==='fixed'&&!this.settings.public.password},
    };
  }
  pairingPayload(mode,url){
    if(!['lan','public','frpc'].includes(mode))throw new Error('invalid mode');
    const valid=new URL(url);
    if(!['http:','https:'].includes(valid.protocol)||valid.username||valid.password||valid.pathname!=='/'||valid.search||valid.hash)throw new Error('invalid URL');
    const password=(mode==='lan'?this.settings.lan:this.settings.public).password;
    if(!password)throw new Error('无法生成扫码链接：请先在「基础配置」中重新设置访问密码');
    // Scan-friendly URL. Password is not a gateway bearer credential and is
    // exchanged for an HttpOnly session cookie on the first GET / request.
    return valid.origin+'?token='+encodeURIComponent(password);
  }
  async qr(mode,url){
    const status=await this.snapshot();const urls=mode==='lan'?status.lan.urls:[mode==='frpc'?status.frpc.url:status.public.url].filter(Boolean);
    if(!urls.includes(url))throw new Error('URL not active');
    const payload=this.pairingPayload(mode,url);
    return {payload,dataUrl:qrPngDataUrl(payload)};
  }
  async stop(){this.closed=true;this.clearRetry();this.clearFrpcRetry();this.clearGatewayRetry();this.tunnel.stop();this.frpc.stop();await this.stopGateway();this.log('info','插件停止，局域网、Cloudflare 与 frpc 连接已清理');}
}
