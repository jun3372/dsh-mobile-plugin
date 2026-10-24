/* DSH Mobile self-contained browser plugin bundle. No browser-side imports. */
window.__ModuleLoader__.load({
  id: 'dsh-mobile-plugin',
  factory: function(require) {
    var module = { exports: {} }; var exports = module.exports;
    const STYLE = `
/* DSH Mobile settings — DSH tokens first, system fallbacks second. */
[data-dsh-mobile-anchor]{display:flex!important;flex-wrap:wrap;align-items:center;row-gap:4px;flex:1 1 auto}
/* 宿主账号容器（按钮/anchor span）默认 width:100% 占满整行，收缩为内容宽度才能让图标与它同行。 */
[data-dsh-mobile-anchor] > :not(.dsh-mobile-trigger){width:auto!important;flex:0 1 auto!important;min-width:0}
.dsh-mobile-trigger{appearance:none;flex:none;width:44px;height:44px;display:inline-flex;align-items:center;justify-content:center;margin-left:auto;border:0;border-radius:8px;background:transparent;color:inherit;cursor:pointer;transition:background .18s,transform .18s}
/* 侧边栏折叠时图标换行到头像正下方（左边距清零即与头像中心对齐）；展开态由 margin-left:auto 推到行尾最右。 */
[data-dsh-mobile-anchor]:has(button[data-collapsed=true]) .dsh-mobile-trigger{margin-left:auto;margin-right:auto}
.dsh-mobile-trigger[data-state=online]{color:#087d48}
.dsh-mobile-trigger[data-state=connecting]{color:#9c6605}
.dsh-mobile-trigger[data-state=error]{color:#b73535}
.dsh-mobile-trigger[data-state=off]{opacity:.55}
.dsh-mobile-trigger:hover{background:var(--dsw-alias-interactive-bg-hover,rgba(125,125,125,.16))}
.dsh-mobile-trigger:focus-visible{outline:2px solid var(--dsw-alias-brand-primary,#497dff);outline-offset:2px}
.dsh-mobile-backdrop{position:fixed;inset:0;z-index:9995;background:rgba(13,21,39,.57);display:flex;align-items:center;justify-content:center;padding:26px;box-sizing:border-box}
.dsh-mobile-panel{--mobile-brand:var(--dsw-alias-brand-primary,#4777e9);--mobile-bg:var(--dsw-alias-bg-primary,var(--dsw-alias-surface-primary,#fff));--mobile-subtle:var(--dsw-alias-bg-secondary,rgba(118,132,160,.07));--mobile-border:var(--dsw-alias-border-default,rgba(100,115,140,.20));--mobile-control-height:40px;color:var(--dsw-alias-text-primary,#202b3b);background:var(--mobile-bg);box-sizing:border-box;width:min(924px,100%);height:min(760px,calc(100vh - 52px));height:min(760px,calc(100dvh - 52px));max-height:calc(100vh - 52px);max-height:calc(100dvh - 52px);display:flex;flex-direction:column;overflow:hidden;border-radius:18px;border:1px solid var(--mobile-border);box-shadow:0 34px 100px rgba(0,0,0,.30);font:inherit}
.dsh-mobile-panel *{box-sizing:border-box}
.dsh-mobile-panel [hidden]{display:none!important}
.dsh-mobile-header{position:relative;flex:0 0 auto;display:flex;align-items:flex-start;justify-content:space-between;gap:18px;padding:21px 26px 18px;border-bottom:1px solid var(--mobile-border);background:linear-gradient(125deg,rgba(81,125,232,.10),transparent 70%)}
.dsh-mobile-title{font-size:19px;font-weight:730;letter-spacing:-.025em;line-height:1.35}
.dsh-mobile-muted{opacity:.69;font-size:12px;line-height:1.55}
.dsh-mobile-close{display:grid;place-items:center;flex:none;width:32px;height:32px;padding:0;border:1px solid var(--mobile-border);border-radius:9px;color:inherit;background:var(--mobile-subtle);font:inherit;font-size:21px;cursor:pointer;transition:background .16s}
.dsh-mobile-close:hover{background:var(--dsw-alias-interactive-bg-hover,rgba(100,100,100,.12))}
.dsh-mobile-layout{display:grid;grid-template-columns:186px minmax(0,1fr);min-height:0;flex:1;overflow:hidden}
.dsh-mobile-menu{background:var(--mobile-subtle);border-right:1px solid var(--mobile-border);padding:20px 12px;display:flex;flex-direction:column;gap:8px;min-height:0;overflow-y:auto;overscroll-behavior:contain}
.dsh-mobile-menu-caption{padding:0 13px 12px;font-size:11px;font-weight:670;letter-spacing:.06em;opacity:.55}
.dsh-mobile-tab{font:inherit;display:flex;align-items:center;text-align:left;gap:0;width:100%;min-height:46px;position:relative;border:1px solid transparent;border-radius:11px;padding:0 14px;background:transparent;color:inherit;cursor:pointer;transition:background .16s,border-color .16s,box-shadow .16s}
.dsh-mobile-tab:hover{background:rgba(105,124,157,.085)}
.dsh-mobile-tab[aria-selected=true]{color:var(--mobile-brand);border-color:rgba(88,124,205,.20);background:var(--mobile-bg);box-shadow:0 3px 12px rgba(23,43,91,.07)}
.dsh-mobile-tab[aria-selected=true]::before{content:'';position:absolute;top:9px;bottom:9px;left:0;width:3px;background:var(--mobile-brand);border-radius:0 4px 4px 0}
.dsh-mobile-tab-name{font-size:13px;font-weight:680;line-height:1.4}
.dsh-mobile-content{padding:24px 26px 28px;min-height:0;overflow-y:auto;overflow-x:hidden;overscroll-behavior:contain;scrollbar-gutter:stable;display:flex;flex-direction:column;gap:16px;font-size:13px;-webkit-overflow-scrolling:touch}
.dsh-mobile-row{display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}
.dsh-mobile-overview{display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-top:12px}
.dsh-mobile-overview-pill{display:inline-flex;align-items:center;gap:5px;font-size:11px;font-weight:650;border:1px solid var(--mobile-border);border-radius:99px;padding:5px 10px;background:var(--mobile-bg)}
.dsh-mobile-overview-pill[data-state=online]{color:#108451;border-color:rgba(33,170,109,.3);background:rgba(24,176,107,.08)}
.dsh-mobile-overview-pill[data-state=connecting]{color:#a46f12;border-color:rgba(234,163,48,.25);background:rgba(241,175,32,.08)}
.dsh-mobile-overview-pill[data-state=error]{color:#c14747;border-color:rgba(226,82,82,.26);background:rgba(221,64,64,.075)}
.dsh-mobile-status-card{border:1px solid var(--mobile-border);background:var(--mobile-subtle);border-radius:13px;padding:16px 18px;display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap}
.dsh-mobile-status-card[data-state=online]{border-color:rgba(20,167,97,.36);background:rgba(20,167,97,.075)}
.dsh-mobile-status-card[data-state=connecting]{border-color:rgba(232,163,48,.36);background:rgba(232,163,48,.07)}
.dsh-mobile-status-card[data-state=error]{border-color:rgba(226,75,75,.36);background:rgba(226,75,75,.07)}
.dsh-mobile-status-title{font-size:15px;font-weight:700;margin-bottom:3px}
.dsh-mobile-state{display:inline-flex;align-items:center;gap:7px;border:1px solid var(--mobile-border);border-radius:999px;padding:7px 12px;font-size:12px;line-height:1;font-weight:700;white-space:nowrap;background:var(--mobile-bg)}
.dsh-mobile-state::before{content:'';width:7px;height:7px;border-radius:50%;background:currentColor;flex:none}
.dsh-mobile-state[data-state=online]{color:#087d48;border-color:rgba(27,172,102,.36);background:rgba(28,175,97,.11)}
.dsh-mobile-state[data-state=connecting]{color:#9c6605;border-color:rgba(217,147,33,.36);background:rgba(234,163,48,.10)}
.dsh-mobile-state[data-state=error]{color:#b73535;border-color:rgba(211,74,74,.36);background:rgba(217,73,73,.09)}
.dsh-mobile-state[data-state=off]{opacity:.65}
.dsh-mobile-switch-row{display:flex;align-items:center;justify-content:space-between;gap:18px;background:var(--mobile-bg);border:1px solid var(--mobile-border);border-radius:12px;padding:15px 17px;cursor:pointer}
.dsh-mobile-switch-name{display:block;font-size:13px;font-weight:700;margin-bottom:4px}
.dsh-mobile-switch-note{display:block;font-size:11px;opacity:.64;line-height:1.5}
.dsh-mobile-switch-input{appearance:none;-webkit-appearance:none;outline-offset:3px;width:44px;height:25px;border-radius:100px;flex:none;cursor:pointer;position:relative;border:1px solid rgba(125,135,147,.25);background:#aab4c3;transition:background .2s,border-color .2s}
.dsh-mobile-switch-input::after{content:'';display:block;position:absolute;top:2px;left:2px;height:19px;width:19px;border-radius:50%;background:#fff;box-shadow:0 1px 3px rgba(0,0,0,.20);transition:transform .2s}
.dsh-mobile-switch-input:checked{background:var(--mobile-brand);border-color:var(--mobile-brand)}
.dsh-mobile-switch-input:checked::after{transform:translateX(19px)}
.dsh-mobile-switch-input:focus-visible{outline:2px solid var(--mobile-brand)}
.dsh-mobile-password-block{display:flex;flex-direction:column;gap:8px;padding:10px 0}.dsh-mobile-password-block+.dsh-mobile-password-block{border-top:1px solid var(--mobile-border)}.dsh-mobile-id-value{font-family:ui-monospace,SFMono-Regular,Consolas,monospace;font-size:12px;overflow-wrap:anywhere;padding:10px 12px;border:1px solid var(--mobile-border);border-radius:9px;background:var(--mobile-subtle)}
.dsh-mobile-section{display:flex;flex-direction:column;gap:13px;padding:17px 18px 18px;border:1px solid var(--mobile-border);border-radius:13px;background:var(--mobile-bg)}
.dsh-mobile-section-heading{display:flex;flex-direction:column;gap:3px;border-bottom:1px solid var(--mobile-border);padding-bottom:11px;margin-bottom:3px}
.dsh-mobile-section-title{font-size:13px;font-weight:740}
.dsh-mobile-section-note{font-size:11px;opacity:.64;line-height:1.5}
.dsh-mobile-grid{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:13px}
.dsh-mobile-field{display:flex;flex-direction:column;gap:7px;min-width:0}
.dsh-mobile-label{font-size:12px;font-weight:670}
.dsh-mobile-input{display:block;box-sizing:border-box;width:100%;min-width:0;height:var(--mobile-control-height);min-height:var(--mobile-control-height);padding:0 11px;border:1px solid var(--mobile-border);border-radius:9px;background:var(--mobile-bg);color:inherit;font:inherit;font-size:12px;line-height:normal;transition:border-color .17s,box-shadow .17s}
.dsh-mobile-input:focus{border-color:var(--mobile-brand);outline:0;box-shadow:0 0 0 3px rgba(69,117,219,.13)}
.dsh-mobile-input[readonly]{opacity:.8}
/* 使用浏览器原生选择面板，避免自绘下拉列表带来的重排与滚动卡顿。 */
.dsh-mobile-select-wrap{position:relative;display:block;width:100%;min-width:0}
.dsh-mobile-select{appearance:none;-webkit-appearance:none;cursor:pointer;height:var(--mobile-control-height);min-height:var(--mobile-control-height);padding:0 42px 0 11px;border-radius:9px;font-weight:620;font-size:12px;line-height:normal;background:var(--mobile-bg);border-color:var(--mobile-border);box-shadow:0 1px 2px rgba(16,34,61,.025);text-overflow:ellipsis;white-space:nowrap}
.dsh-mobile-select-wrap::after{content:'';position:absolute;pointer-events:none;right:16px;top:calc(50% - 3px);width:8px;height:8px;border-right:1.8px solid currentColor;border-bottom:1.8px solid currentColor;opacity:.68;transform:translateY(-20%) rotate(45deg);transition:transform .14s,opacity .14s}
.dsh-mobile-select-wrap:hover .dsh-mobile-select{border-color:var(--mobile-brand);background:var(--mobile-subtle)}
.dsh-mobile-select-wrap:hover::after{opacity:1}
.dsh-mobile-select-wrap:focus-within::after{opacity:1;transform:translateY(0) rotate(45deg);color:var(--mobile-brand)}
.dsh-mobile-select option{color:var(--dsw-alias-text-primary,#202b3b);background:var(--dsw-alias-bg-primary,#fff);font-weight:500;padding:8px}
.dsh-mobile-select:disabled{cursor:not-allowed;opacity:.6}
@media(prefers-reduced-motion:reduce){.dsh-mobile-select-wrap::after,.dsh-mobile-select{transition:none}}
.dsh-mobile-button{display:inline-flex;align-items:center;justify-content:center;min-height:34px;padding:7px 12px;border:1px solid var(--mobile-border);border-radius:9px;background:var(--mobile-subtle);color:inherit;font:inherit;font-size:12px;font-weight:630;cursor:pointer;white-space:nowrap;transition:background .15s,transform .15s}
.dsh-mobile-button:hover:not(:disabled){background:var(--dsw-alias-interactive-bg-hover,rgba(125,125,125,.13))}
.dsh-mobile-button:active:not(:disabled){transform:translateY(1px)}
.dsh-mobile-button:focus-visible{outline:2px solid var(--mobile-brand);outline-offset:2px}
.dsh-mobile-primary{min-height:39px;padding:9px 17px;background:var(--mobile-brand);border-color:transparent;color:#fff;font-size:13px}
.dsh-mobile-primary:hover:not(:disabled){background:var(--mobile-brand);filter:brightness(1.075)}
.dsh-mobile-button:disabled{opacity:.45;cursor:not-allowed}
.dsh-mobile-password-actions{display:flex;align-items:center;justify-content:flex-start;gap:8px;flex-wrap:wrap}
.dsh-mobile-qr{display:flex;align-items:center;gap:20px;flex-wrap:wrap;min-width:0}
.dsh-mobile-qr img{display:block;width:164px;height:164px;object-fit:contain;background:white;border:1px solid rgba(145,145,145,.18);border-radius:12px;padding:9px;box-shadow:0 4px 14px rgba(19,35,69,.06)}
.dsh-mobile-qr-body{min-width:0;flex:1;display:flex;flex-direction:column;gap:10px}
.dsh-mobile-url{overflow-wrap:anywhere;font:600 12px/1.7 ui-monospace,SFMono-Regular,Consolas,monospace}
.dsh-mobile-note{background:var(--mobile-subtle);border-radius:9px;padding:10px 12px;font-size:11px;line-height:1.7;opacity:.86}
.dsh-mobile-note[data-variant=warning]{border-left:3px solid #dc9c26;background:rgba(218,156,38,.08);opacity:1}
.dsh-mobile-note[data-variant=success]{border-left:3px solid #2bb27b;background:rgba(43,178,123,.07)}
.dsh-mobile-error{font-size:12px;color:#d15249;overflow-wrap:anywhere;line-height:1.6}
.dsh-mobile-actions{display:flex;align-items:center;gap:13px;flex-wrap:wrap}
.dsh-mobile-log-top{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap}
.dsh-mobile-log-heading{font-size:13px;font-weight:730}
.dsh-mobile-log-meta{font-size:11px;opacity:.65;margin-top:4px}
.dsh-mobile-log{height:206px;min-height:155px;max-height:310px;resize:vertical;overflow-y:auto;overscroll-behavior:contain;border:1px solid var(--mobile-border);border-radius:10px;background:var(--dsw-alias-bg-secondary,rgba(39,51,72,.045));padding:5px 11px;scrollbar-width:thin;font-size:11px;font-family:ui-monospace,SFMono-Regular,Consolas,monospace;line-height:1.6}
.dsh-mobile-log--full{height:min(48vh,420px);min-height:230px;max-height:70vh}
.dsh-mobile-log-line{display:grid;grid-template-columns:61px 32px minmax(0,1fr);align-items:start;gap:8px;padding:8px 2px;overflow-wrap:anywhere;white-space:pre-wrap;border-bottom:1px solid var(--mobile-border)}
.dsh-mobile-log-line:last-child{border-bottom:0}
.dsh-mobile-log-time{opacity:.55;font-variant-numeric:tabular-nums}
.dsh-mobile-log-level{font-size:10px;font-weight:730;color:#52816b}
.dsh-mobile-log-line[data-level=warn] .dsh-mobile-log-level{color:#bc871d}
.dsh-mobile-log-line[data-level=error] .dsh-mobile-log-level{color:#d14848}
.dsh-mobile-log-msg{min-width:0;word-break:break-word}
@media(max-width:760px){.dsh-mobile-backdrop{padding:10px}.dsh-mobile-panel{height:min(760px,calc(100vh - 20px));height:min(760px,calc(100dvh - 20px));max-height:calc(100vh - 20px);max-height:calc(100dvh - 20px)}.dsh-mobile-header{padding:17px}.dsh-mobile-layout{grid-template-columns:132px minmax(0,1fr)}.dsh-mobile-menu{padding:14px 7px}.dsh-mobile-tab{min-height:44px;padding:0 11px}.dsh-mobile-content{padding:16px;gap:13px}.dsh-mobile-grid{grid-template-columns:1fr}}
@media(max-width:470px){.dsh-mobile-layout{grid-template-columns:102px minmax(0,1fr)}.dsh-mobile-menu{padding:12px 4px}.dsh-mobile-menu-caption{padding-left:9px}.dsh-mobile-tab{min-height:44px;padding:0 8px}.dsh-mobile-content{padding:12px}.dsh-mobile-section{padding:12px}.dsh-mobile-header{padding:13px}.dsh-mobile-title{font-size:16px}.dsh-mobile-qr img{width:142px;height:142px}.dsh-mobile-log-line{grid-template-columns:52px 27px minmax(0,1fr);gap:6px}}
    `;
    const apiBase = '/dsh-mobile/admin';
    let currentTab = 'base';
    let modal = null;
    let status = null;
    let polling = null;
    let mounted = null;
    let button = null;
    let observer = null;
    let pending = false;
    let anchorScanTimer = null;
    let lastAnchorScan = 0;
    let triggerPoll = null;
    let sizeObserver = null;
    let disposed = false;
    let view = null;
    let refreshInFlight = null;
    let statusGeneration = 0;
    let viewScroll = {base:0,lan:0,public:0,frpc:0,logs:0};
    let logHeights = {logs:null};
    const qrCache = new Map();
    function el(tag,cls,text) {
      const e=document.createElement(tag); if(cls)e.className=cls;
      if(text!==undefined)e.textContent=String(text); return e;
    }
    function add(parent,...children){children.forEach(c=>parent.append(c));return parent;}
    function field(label,value,opts={}) {
      const outer=el('label','dsh-mobile-field');add(outer,el('span','dsh-mobile-label',label));
      let input;
      if(opts.choices){
        input=el('select','dsh-mobile-input dsh-mobile-select');
        for(const [v,t] of opts.choices){const op=el('option',null,t);op.value=v;input.append(op);}
      } else { input=el('input','dsh-mobile-input');input.type=opts.type||'text'; }
      input.value=value??''; if(opts.placeholder)input.placeholder=opts.placeholder;
      if(opts.choices){const wrap=el('span','dsh-mobile-select-wrap');wrap.append(input);outer.append(wrap);}
      else outer.append(input);
      return {outer,input};
    }
    function downloadSourceControls(target,d,clientName){
      const options=field('GitHub 下载来源',d.downloadSource||'official',{choices:[
        ['official','GitHub 官方（默认）'],['ghfast','国内加速 · ghfast.top'],
        ['ghproxy','国内加速 · ghproxy.net'],['custom','自定义 HTTPS 加速地址']
      ]});
      const mirror=field('自定义加速地址前缀',d.downloadMirror||'',{placeholder:'https://你的加速域名/'});
      const update=()=>{mirror.outer.hidden=options.input.value!=='custom';};
      options.input.addEventListener('change',update);update();
      target.append(options.outer,mirror.outer);
      target.append(note('仅在本机没有 '+clientName+' 时使用；国内加速源由第三方运营，可能失效。所有下载包必须通过 SHA-256 校验才能安装。','warning'));
      return {options,mirror};
    }
    function buttonElement(label,onClick,primary=false) {
      const b=el('button',`dsh-mobile-button${primary?' dsh-mobile-primary':''}`,label);b.type='button';b.addEventListener('click',onClick);return b;
    }
    function appendLine(box,label,value){const row=el('div','dsh-mobile-row');add(row,el('span','dsh-mobile-muted',label),el('span',null,value));box.append(row);}
    function errorInChinese(message){
      const text=String(message||'未知错误');
      if(/cloudflared not installed|cloudflared not found|cloudflared executable missing/i.test(text))return '没有找到 cloudflared。请检查网络后重试自动安装，或在公网设置中填写可执行文件完整路径。详细信息：'+text;
      if(/automatic download failed|cloudflared official download/i.test(text))return 'cloudflared 自动下载失败。请检查访问 GitHub 的网络，或手动配置可执行文件路径。详细信息：'+text;
      if(/frpc 自动下载失败|frpc 下载包|frpc 下载.*校验|GitHub 官方下载/i.test(text))return 'frpc 自动安装失败，请检查 GitHub 网络与文件权限；可在高级设置手动填写程序完整路径。详细信息：'+text;
      if(/未找到 frpc|frpc 可执行文件不存在/i.test(text))return '未找到 frpc，插件会尝试自动下载；如失败请检查运行日志或手动配置完整路径。';
      if(/frps 地址|frpc 端口|frpc 映射|frpc 手机连接地址/i.test(text))return text;
      if(/EADDRINUSE/i.test(text))return '代理端口已被其他程序占用，请修改共享代理端口。详细信息：'+text;
      if(/named mode requires/i.test(text))return '固定域名方式需要同时配置域名和 Cloudflare 隧道令牌。';
      if(/invalid port/i.test(text))return '代理端口无效，请输入 0–65535 之间的整数。';
      if(/service_unavailable|service closed/i.test(text))return '插件服务尚未就绪，请稍后重试。';
      if(/dsh_connection_auth_unavailable/i.test(text))return '当前 DSH 版本无法验证管理权限，请检查插件兼容性。';
      return text;
    }
    async function api(path,options={}) {
      const res=await fetch(apiBase+path,{credentials:'same-origin', cache:'no-store',headers:{'Content-Type':'application/json'}, ...options});
      const payload=await res.json();
      if(!res.ok)throw new Error(errorInChinese(payload?.message||payload?.error||`HTTP ${res.status}`));
      return payload;
    }
    // 轮询只修改在线状态、连接地址和日志，不重建配置表单或滚动容器。
    async function refresh() {
      if(!modal || refreshInFlight===modal)return;
      const owner=modal, generation=statusGeneration;
      refreshInFlight=owner;
      try {
        const latest=await api('/status');
        if(modal!==owner || generation!==statusGeneration)return;
        status=latest;
        if(!view)renderContent();
        syncIndicators();
        syncTriggerState();
        syncLiveView();
      }catch(err){
        if(modal!==owner || generation!==statusGeneration)return;
        if(!status){const node=modal.querySelector('[data-dsh-mobile-content]');
          if(node)node.replaceChildren(el('div','dsh-mobile-error',`读取服务端状态失败：${err.message}`));}
        else if(view?.pollError){view.pollError.textContent=`状态更新失败：${err.message}`;view.pollError.hidden=false;}
      }finally{if(refreshInFlight===owner)refreshInFlight=null;}
    }
    function close() {
      statusGeneration++;
      refreshInFlight=null;
      if(polling){clearInterval(polling);polling=null;}
      if(modal){modal.remove();modal=null;}
      view=null;
      document.removeEventListener('keydown',escapeHandler);
      document.removeEventListener('visibilitychange',visibilityHandler);
    }
    function visibilityHandler(){if(!document.hidden)refresh();}
    function open() {
      if(modal)return;
      status=null;view=null;viewScroll={base:0,lan:0,public:0,frpc:0,logs:0};logHeights={logs:null};
      modal=el('div','dsh-mobile-backdrop');modal.addEventListener('click',e=>{if(e.target===modal)close();});
      const panel=el('section','dsh-mobile-panel');panel.setAttribute('role','dialog');panel.setAttribute('aria-modal','true');panel.setAttribute('aria-label','DSH Mobile 配置');
      const header=el('div','dsh-mobile-header'); const intro=el('div'); add(intro,el('div','dsh-mobile-title','DSH Mobile · 手机连接'),el('div','dsh-mobile-muted','局域网、Cloudflare 与 frpc 隧道 · 重启 DSH 后恢复已启用的服务'));
      const overview=el('div','dsh-mobile-overview');overview.dataset.dshMobileOverview='';intro.append(overview); const x=el('button','dsh-mobile-close','×');x.type='button';x.setAttribute('aria-label','关闭');x.onclick=close;add(header,intro,x);
      const layout=el('div','dsh-mobile-layout');const menu=el('nav','dsh-mobile-menu');const content=el('main','dsh-mobile-content');content.dataset.dshMobileContent='';
      menu.append(el('div','dsh-mobile-menu-caption','连接与诊断'));
      for(const [id,label] of [['base','基础配置'],['lan','局域网'],['public','Cloudflare隧道'],['frpc','frpc隧道'],['logs','运行日志']]){
        const tab=el('button','dsh-mobile-tab');tab.type='button';tab.dataset.tab=id;
        const labelNode=el('span','dsh-mobile-tab-name',label);
        tab.append(labelNode);tab.setAttribute('aria-selected',String(currentTab===id));
        tab.onclick=()=>{
          if(currentTab===id)return;
          viewScroll[currentTab]=content.scrollTop;
          currentTab=id;
          for(const item of menu.querySelectorAll('[data-tab]'))item.setAttribute('aria-selected',String(item.dataset.tab===id));
          renderContent();
        };menu.append(tab);
      }
      content.addEventListener('scroll',()=>{viewScroll[currentTab]=content.scrollTop;},{passive:true});
      add(layout,menu,content);add(panel,header,layout);modal.append(panel);document.body.append(modal);
      document.addEventListener('keydown',escapeHandler);
      document.addEventListener('visibilitychange',visibilityHandler);
      polling=setInterval(()=>{if(!document.hidden)refresh();},6000);
      refresh();
    }
    function escapeHandler(e){if(e.key==='Escape'&&modal){e.stopPropagation();close();}}
    function statusLabel(d,mode){
      if(!d.enabled)return '已关闭';
      if(d.error)return '错误';
      if(mode==='public'||mode==='frpc')return ({online:'已连接',connecting:'连接中',error:'错误',stopped:'未连接'})[d.tunnelState]||d.tunnelState;
      return d.running?'运行中':'待启动';
    }
    function stateTone(d,mode){
      if(!d.enabled)return 'off';
      if(d.error || ((mode==='public'||mode==='frpc') && d.tunnelState==='error'))return 'error';
      if(mode==='public'||mode==='frpc')return d.running&&d.tunnelState==='online'?'online':'connecting';
      return d.running?'online':'connecting';
    }
    // 图标颜色取三个模式的最差状态：error > connecting > online > off。
    function overallTone(s){
      const tones=['lan','public','frpc'].map(m=>stateTone(s[m],m));
      for(const t of ['error','connecting','online'])if(tones.includes(t))return t;
      return 'off';
    }
    function syncTriggerState(){
      if(!button||!status)return;
      const tone=overallTone(status);
      if(button.dataset.state!==tone)button.dataset.state=tone;
    }
    function syncIndicators(){
      if(!status||!modal)return;
      const overview=modal.querySelector('[data-dsh-mobile-overview]');
      if(overview){
        for(const mode of ['lan','public','frpc']){
          let item=overview.querySelector(`[data-overview-mode="${mode}"]`);
          if(!item){item=el('span','dsh-mobile-overview-pill');item.dataset.overviewMode=mode;overview.append(item);}
          const tone=stateTone(status[mode],mode);
          const label=`${mode==='lan'?'局域网':mode==='frpc'?'frpc隧道':'Cloudflare隧道'} · ${statusLabel(status[mode],mode)}`;
          if(item.dataset.state!==tone)item.dataset.state=tone;
          if(item.textContent!==label)item.textContent=label;
        }
      }
      if(currentTab==='logs'||currentTab==='base')return; // 非网络页没有单独的连接状态。
      const d=status[currentTab];const tone=stateTone(d,currentTab);
      const pill=modal.querySelector('[data-dsh-mobile-live-status]');
      if(pill){
        const label=statusLabel(d,currentTab);
        if(pill.textContent!==label)pill.textContent=label;
        if(pill.dataset.state!==tone)pill.dataset.state=tone;
      }
      const card=modal.querySelector('[data-dsh-mobile-status-card]');
      if(card&&card.dataset.state!==tone)card.dataset.state=tone;
    }
    function section(title,subtitle){
      const root=el('section','dsh-mobile-section');
      const heading=el('div','dsh-mobile-section-heading');
      add(heading,el('div','dsh-mobile-section-title',title));
      if(subtitle)heading.append(el('div','dsh-mobile-section-note',subtitle));
      root.append(heading);return root;
    }
    function note(text,variant){const e=el('div','dsh-mobile-note',text);if(variant)e.dataset.variant=variant;return e;}
    function renderLogs(logBox,meta,records){
      const key=records.map(r=>[r.time,r.level,r.message].join('~')).join('\n');
      if(logBox.dataset.logKey===key)return;
      const wasAtTop=logBox.scrollTop<=4;
      const previousTop=logBox.scrollTop;
      const frag=document.createDocumentFragment();
      for(const item of records.slice(-30).reverse()){
        const line=el('div','dsh-mobile-log-line');line.dataset.level=item.level;
        add(line,
          el('span','dsh-mobile-log-time',new Date(item.time).toLocaleTimeString('zh-CN',{hour12:false})),
          el('span','dsh-mobile-log-level',({info:'信息',warn:'警告',error:'错误'})[item.level]||item.level),
          el('span','dsh-mobile-log-msg',item.message));
        frag.append(line);
      }
      if(!records.length)frag.append(el('div','dsh-mobile-muted','暂无运行日志'));
      logBox.replaceChildren(frag);
      logBox.dataset.logKey=key;
      logBox.scrollTop=wasAtTop?0:previousTop;
      meta.textContent=`${records.length} 条 · 不包含密码和隧道令牌`;
    }
    function syncLiveView(){
      if(!view || !status || view.mode!==currentTab)return;
      view.pollError.hidden=true;
      view.pollError.textContent='';
      if(currentTab==='logs'){
        const logs=Array.isArray(status.recentLogs)?status.recentLogs:[];
        renderLogs(view.logBox,view.logMeta,logs);
        view.copyLog.disabled=!logs.length;
        return;
      }
      if(currentTab==='base'){
        if(view.gatewayPill){
          const running=!!status.gateway?.running;
          view.gatewayPill.dataset.state=running?'online':'off';
          view.gatewayPill.textContent=running?'网关运行中':'网关已停止';
        }
        return;
      }
      const d=status[currentTab];
      if(!view.toggleDirty && view.toggle.checked!==!!d.enabled)view.toggle.checked=!!d.enabled;
      const note=d.enabled?'已保存开启状态，重启 DSH 后将自动恢复':'关闭后将保持停用，重启 DSH 也不会自动开启';
      if(view.enabledNote.textContent!==note)view.enabledNote.textContent=note;
      if(currentTab==='public'||currentTab==='frpc')view.drawQr(d.url||'');
      else {
        const ip=view.addressSelector?.input.value||d.selectedAddress;
        view.drawQr(view.selectedUrl(ip)||'');
      }
      const runtimeMessage=d.error?'当前异常：'+d.error:'';
      if(view.runtimeError.textContent!==runtimeMessage)view.runtimeError.textContent=runtimeMessage;
      view.runtimeError.hidden=!d.error;
    }
    // 运行日志是单独的菜单页面，不与任何网络配置表单耦合。
    function renderLogPage(node,savedScroll){
      const records=Array.isArray(status.recentLogs)?status.recentLogs:[];
      const logSection=section('最近运行日志','集中展示局域网、Cloudflare、frpc 和插件自身的运行记录；最新日志置顶');
      logSection.dataset.dshMobileLogView='';
      const logTop=el('div','dsh-mobile-log-top');
      const logDescription=el('div');
      const logMeta=el('div','dsh-mobile-log-meta');
      add(logDescription,el('span','dsh-mobile-log-heading','运行记录'),logMeta);
      const copyLog=buttonElement('复制日志',async()=>{
        const items=Array.isArray(status?.recentLogs)?status.recentLogs:[];
        try{
          await navigator.clipboard.writeText(items.map(r=>`${new Date(r.time).toLocaleString('zh-CN')} [${r.level}] ${r.message}`).join('\n'));
          copyLog.textContent='已复制';
        }catch{copyLog.textContent='复制失败';}
      });copyLog.disabled=!records.length;
      add(logTop,logDescription,copyLog);logSection.append(logTop);
      const logBox=el('div','dsh-mobile-log dsh-mobile-log--full');
      logBox.setAttribute('role','log');logBox.setAttribute('aria-label','最近运行日志');
      if(logHeights.logs)logBox.style.height=logHeights.logs+'px';
      const rememberHeight=()=>{logHeights.logs=logBox.getBoundingClientRect().height;};
      logBox.addEventListener('pointerup',rememberHeight);
      logBox.addEventListener('mouseup',rememberHeight);
      logSection.append(logBox);node.append(logSection);
      const pollError=el('div','dsh-mobile-error');pollError.hidden=true;node.append(pollError);
      view={mode:'logs',logBox,logMeta,copyLog,pollError};
      renderLogs(logBox,logMeta,records);
      syncIndicators();
      node.scrollTop=savedScroll;
    }
    // 所有入口共用代理端口；LAN 和公网密码独立，其中 Cloudflare/frpc 共用公网密码。
    // 独立的基础配置保存请求以原子方式修改以上字段，不改变三个隧道的启停状态。
    function renderBasePage(node,savedScroll){
      const base=status.base||{port:status.gateway.port,instanceId:status.instanceId,
        lanPassword:status.lan.visiblePassword||'',publicPassword:status.public.visiblePassword||'',
        lanPasswordRecoveryRequired:status.lan.passwordRecoveryRequired,
        publicPasswordRecoveryRequired:status.public.passwordRecoveryRequired};
      const gateway=section('共享代理网关','局域网、Cloudflare 与 frpc 共用同一个本地代理端口，修改后将重新建立网络连接。');
      const gatewayPill=el('span','dsh-mobile-state');gatewayPill.setAttribute('role','status');
      gatewayPill.dataset.state=status.gateway?.running?(status.gateway.upstreamAuthenticated?'online':'connecting'):'off';
      gatewayPill.textContent=status.gateway?.running?(status.gateway.upstreamAuthenticated?'网关及 DSH 接口认证正常':'网关运行中 · DSH 接口认证待确认'):'网关已停止';
      gateway.append(gatewayPill);
      const port=field('共享代理端口',base.port,{type:'number'});
      port.input.min='1';port.input.max='65535';port.input.step='1';
      gateway.append(port.outer);node.append(gateway);

      const access=section('访问安全','局域网使用独立密码；Cloudflare 隧道和 frpc 隧道共用公网访问密码。');
      function passwordRow(title,password,recovery){
        const group=el('div','dsh-mobile-password-block');
        const control=field(title,password||'',{type:'password',placeholder:recovery?'旧密码不可恢复，请输入新密码':'输入新密码后保存'});
        control.input.autocomplete='new-password';group.append(control.outer);
        const actions=el('div','dsh-mobile-password-actions');
        const show=buttonElement('显示密码',()=>{
          const visible=control.input.type==='text';control.input.type=visible?'password':'text';
          show.textContent=visible?'显示密码':'隐藏密码';
        });
        const copy=buttonElement('复制密码',async()=>{
          if(!control.input.value)return;
          try{await navigator.clipboard.writeText(control.input.value);copy.textContent='已复制';}
          catch{copy.textContent='复制失败';}
        });
        add(actions,show,copy);group.append(actions);
        if(recovery)group.append(note('旧版密码仅保存哈希，无法回显。可在这里重新设置密码。','warning'));
        return {group,input:control.input};
      }
      const lanPassword=passwordRow('局域网访问密码',base.lanPassword,base.lanPasswordRecoveryRequired);
      const publicPassword=passwordRow('公网访问密码（Cloudflare / frpc 共用）',base.publicPassword,base.publicPasswordRecoveryRequired);
      access.append(lanPassword.group,publicPassword.group);
      access.append(note('密码长度为 8–64 位。首次生成的随机密码会持续保存；只有主动修改密码后才会变更。更换密码会使对应入口的旧连接凭证失效。'));
      node.append(access);

      const info=section('服务端信息','同一台 DSH 在不同网络入口下使用同一个服务端标识。');
      const idValue=el('div','dsh-mobile-id-value',base.instanceId||status.instanceId);
      info.append(el('div','dsh-mobile-label','DSH 实例标识'),idValue);
      node.append(info);
      const actions=el('div','dsh-mobile-actions');const feedback=el('span','dsh-mobile-error');
      const save=buttonElement('保存基础配置',async()=>{
        const portNumber=Number(port.input.value);
        if(!Number.isInteger(portNumber)||portNumber<1||portNumber>65535){feedback.textContent='代理端口必须在 1–65535 之间';return;}
        const patch={port:portNumber};
        for(const [key,control,old] of [['lanPassword',lanPassword.input,base.lanPassword],['publicPassword',publicPassword.input,base.publicPassword]]){
          if(control.value!==String(old||'')){
            if(control.value.length<8||control.value.length>64){feedback.textContent='访问密码需要 8–64 位字符';return;}
            patch[key]=control.value;
          }
        }
        feedback.textContent='';save.disabled=true;save.textContent='正在应用…';
        try{statusGeneration++;status=await api('/configure',{method:'POST',body:JSON.stringify({mode:'base',patch})});renderContent();}
        catch(e){feedback.textContent=e.message;save.disabled=false;save.textContent='保存基础配置';}
      },true);
      add(actions,save,feedback);node.append(actions);
      const pollError=el('div','dsh-mobile-error');pollError.hidden=true;node.append(pollError);
      view={mode:'base',gatewayPill,pollError};syncIndicators();node.scrollTop=savedScroll;
    }
    function renderContent(){
      if(!modal)return;
      const node=modal.querySelector('[data-dsh-mobile-content]');if(!node)return;
      const savedScroll=viewScroll[currentTab]||0;
      node.replaceChildren();view=null;
      if(!status){node.append(el('p','dsh-mobile-muted','正在读取状态…'));return;}
      if(currentTab==='logs'){renderLogPage(node,savedScroll);return;}
      if(currentTab==='base'){renderBasePage(node,savedScroll);return;}
      const mode=currentTab;const d=status[mode];
      const stateCard=el('div','dsh-mobile-status-card');stateCard.dataset.dshMobileStatusCard='';
      const stateGroup=el('div');add(stateGroup,el('div','dsh-mobile-status-title',mode==='lan'?'局域网连接':mode==='frpc'?'frpc 隧道':'Cloudflare 公网访问'),
        el('div','dsh-mobile-muted',mode==='lan'?'与手机处于同一网络即可连接':mode==='frpc'?'通过自己的 frps 服务端提供固定公网入口':'通过 Cloudflare 安全隧道访问服务端'));
      const pill=el('span','dsh-mobile-state');pill.dataset.dshMobileLiveStatus='';pill.setAttribute('role','status');pill.setAttribute('aria-live','polite');
      add(stateCard,stateGroup,pill);node.append(stateCard);

      const enabled=el('label','dsh-mobile-switch-row');
      const enabledText=el('span');add(enabledText,el('span','dsh-mobile-switch-name',mode==='lan'?'开启局域网访问':mode==='frpc'?'开启 frpc 隧道':'开启 Cloudflare 隧道'),
        el('span','dsh-mobile-switch-note',d.enabled?'已保存开启状态，重启 DSH 后将自动恢复':'关闭后将保持停用，重启 DSH 也不会自动开启'));
      const toggle=el('input','dsh-mobile-switch-input');toggle.type='checkbox';toggle.checked=!!d.enabled;
      toggle.setAttribute('aria-label',mode==='lan'?'开启局域网访问':mode==='frpc'?'开启 frpc 隧道':'开启 Cloudflare 隧道');
      add(enabled,enabledText,toggle);node.append(enabled);
      syncIndicators();

      const connection=section('连接信息',mode==='lan'?'选择手机可访问的局域网 IP；每次只显示一个二维码':mode==='frpc'?'把共享代理端口映射到自己部署的 frps 服务端':'公网地址由 Cloudflare 隧道提供');
      let addressSelector=null;
      const lanAddresses=mode==='lan'&&Array.isArray(d.addresses)?d.addresses:[];
      if(mode==='lan'&&lanAddresses.length>1){
        addressSelector=field('选择局域网 IP',d.selectedAddress||lanAddresses[0].address,
          {choices:lanAddresses.map(a=>[a.address,`${a.address} · ${a.interface}`])});
        connection.append(addressSelector.outer);
        connection.append(note('当前设备发现多个网络地址。请选择与手机处于相同局域网的 IP，点击「保存并应用」后会在下次打开时记住选择。'));
      }else if(mode==='lan'){
        const addressFields=el('div','dsh-mobile-grid');
        if(lanAddresses.length){const single=field('局域网地址',`${lanAddresses[0].address} · ${lanAddresses[0].interface}`);single.input.readOnly=true;addressFields.append(single.outer);}
        connection.append(addressFields);
      }
      let tmode,hostname,token,binaryPath,publicDownloadControls;
      let frpcFields=null;
      if(mode==='public'){
        tmode=field('公网访问方式',d.mode,{choices:[['quick','快速隧道（临时地址）'],['named','命名隧道（固定域名）']]});
        connection.append(tmode.outer);
        const namedOptions=el('div','dsh-mobile-grid');
        hostname=field('固定域名（https://...）',d.hostname||'',{placeholder:'https://mobile.example.com'});
        token=field('Cloudflare 隧道令牌（留空保持不变）','',{type:'password',placeholder:d.hasToken?'已配置令牌':'填写隧道令牌'});
        add(namedOptions,hostname.outer,token.outer);connection.append(namedOptions);
        const temporaryHint=note('快速隧道的 trycloudflare.com 地址由 Cloudflare 每次创建连接时随机分配，无法在重启 DSH 后保留。需要长期不变的地址，请使用 Cloudflare 命名隧道并绑定自己的域名。','warning');
        connection.append(temporaryHint);
        const advanced=el('details');const summary=el('summary','dsh-mobile-label','高级设置：cloudflared 自动下载与程序路径');advanced.append(summary);
        binaryPath=field('cloudflared 路径（留空自动查找或下载）',d.binaryPath||'',{placeholder:'例如 C:\\Program Files\\cloudflared\\cloudflared.exe'});
        advanced.append(binaryPath.outer);publicDownloadControls=downloadSourceControls(advanced,d,'cloudflared');connection.append(advanced);
        const updateTunnelOptions=()=>{
          const named=tmode.input.value==='named';namedOptions.hidden=!named;temporaryHint.hidden=named;
        };
        tmode.input.addEventListener('change',updateTunnelOptions);updateTunnelOptions();
        connection.append(note('公网连接拥有控制 DSH 宿主的高权限。命名隧道需在 Cloudflare 将公开域名转发到本机 127.0.0.1 的共享代理端口。'));
      }
      if(mode==='frpc'){
        const grid1=el('div','dsh-mobile-grid');
        const serverAddr=field('frps 服务器地址',d.serverAddr||'',{placeholder:'frp.example.com'});
        const serverPort=field('frps 控制端口',d.serverPort||7000,{type:'number'});
        add(grid1,serverAddr.outer,serverPort.outer);connection.append(grid1);
        const grid2=el('div','dsh-mobile-grid');
        const remotePort=field('frps 公网映射端口',d.remotePort||'',{type:'number',placeholder:'39081'});
        const proxyName=field('映射名称',d.proxyName||'dsh-mobile');
        add(grid2,remotePort.outer,proxyName.outer);connection.append(grid2);
        const externalUrl=field('手机访问地址（可选，HTTPS 请自行配置）',d.publicUrl||'',{placeholder:'https://mobile.example.com 或留空自动生成 HTTP 地址'});
        connection.append(externalUrl.outer);
        const frpsToken=field('frps 认证 Token（留空保持不变）','',{type:'password',placeholder:d.hasToken?'已配置，留空保持不变':'填写 frps 配置的 auth.token'});
        connection.append(frpsToken.outer);
        const advanced=el('details');advanced.append(el('summary','dsh-mobile-label','高级设置：frpc 自动安装与程序路径'));
        const executable=field('frpc 完整路径（留空自动查找或从 GitHub 安装）',d.binaryPath||'',{placeholder:'例如 /usr/local/bin/frpc'});
        advanced.append(executable.outer);const downloads=downloadSourceControls(advanced,d,'frpc');advanced.append(note('首次启用时若未找到 frpc，将下载官方 frp Release 并校验 SHA-256；下载状态可在「运行日志」中查看。'));connection.append(advanced);
        connection.append(note('需要预先部署 frps 并允许指定远程端口。frpc 与 Cloudflare 共用公网访问密码，但独立启停及生成二维码。frpc TCP 远程端口默认不提供 HTTPS，请配合 TLS 终止代理使用；勿将未加密入口直接暴露在公网。','warning'));
        frpcFields={serverAddr,serverPort,remotePort,proxyName,externalUrl,frpsToken,executable,downloads};
      }
      const qrBlock=el('div','dsh-mobile-qr');connection.append(qrBlock);
      let qrKey=null,qrRequestSeq=0;
      function drawQr(url){
        // A password change must replace the QR even if its network address
        // stays the same. Revisions contain no plaintext password.
        const revision=status[mode]?.qrRevision||'';
        const key=mode+':'+url+':'+revision;
        if(key===qrKey)return;
        qrKey=key;const request=++qrRequestSeq;
        qrBlock.replaceChildren();
        if(!url){qrBlock.append(el('div','dsh-mobile-muted',status[mode].enabled?'正在等待可用连接地址…':'启用并保存网络服务后将显示连接二维码。'));return;}
        const img=el('img');img.alt=`${mode==='lan'?'局域网':mode==='frpc'?'frpc':'Cloudflare'}配对二维码`;
        const details=el('div','dsh-mobile-qr-body');
        const addr=el('div','dsh-mobile-url',url);
        const copy=buttonElement('复制连接地址',async()=>{
          try{await navigator.clipboard.writeText(url);copy.textContent='已复制';}
          catch{copy.textContent='复制失败';}
        });
        add(details,el('div','dsh-mobile-label','手机扫码打开连接链接（自动登录）'),addr,copy);
        details.append(note('二维码链接携带访问密码，请勿公开分享二维码截图或链接。登录后浏览器会跳转到不含密码的地址。','warning'));
        add(qrBlock,img,details);
        if(qrCache.has(key)){img.src=qrCache.get(key);return;}
        api('/qr?mode='+encodeURIComponent(mode)+'&url='+encodeURIComponent(url)).then(result=>{
          if(typeof result.dataUrl!=='string'||!result.dataUrl.startsWith('data:image/png;base64,'))return;
          if(qrCache.size>=12)qrCache.delete(qrCache.keys().next().value);
          qrCache.set(key,result.dataUrl);
          if(img.isConnected && request===qrRequestSeq)img.src=result.dataUrl;
        }).catch(e=>{if(img.isConnected&&request===qrRequestSeq)img.replaceWith(el('div','dsh-mobile-error','二维码暂不可用：'+e.message));});
      }
      const selectedUrl=ip=>Array.isArray(status.lan.urls)?status.lan.urls.find(u=>{try{return new URL(u).hostname===ip;}catch{return false;}}):null;
      drawQr(mode!=='lan'?(d.url||''):(selectedUrl(addressSelector?.input.value||d.selectedAddress)||''));
      if(addressSelector)addressSelector.input.addEventListener('change',()=>drawQr(selectedUrl(addressSelector.input.value)||''));
      node.append(connection);

      // 访问密码统一在「基础配置」中管理；各隧道页只处理自己的连接参数。
      node.append(note('访问密码与共享代理端口请前往左侧「基础配置」统一管理。'));

      const controls=el('div','dsh-mobile-actions');const feedback=el('span','dsh-mobile-error');
      const save=buttonElement('保存并应用',async()=>{
        const patch={enabled:toggle.checked};
        if(mode==='lan'){
          if(addressSelector)patch.preferredAddress=addressSelector.input.value;
          else if(lanAddresses.length===1)patch.preferredAddress=lanAddresses[0].address;
        }
        if(mode==='public'){
          patch.mode=tmode.input.value;patch.hostname=hostname.input.value;patch.binaryPath=binaryPath.input.value;
          patch.downloadSource=publicDownloadControls.options.input.value;patch.downloadMirror=publicDownloadControls.mirror.input.value.trim();
          if(token.input.value)patch.token=token.input.value;
          if(patch.enabled&&!d.enabled&&!confirm('启用公网允许从互联网访问 DSH 的敏感功能。确认开启？'))return;
        }
        if(mode==='frpc'){
          patch.serverAddr=frpcFields.serverAddr.input.value.trim();
          patch.serverPort=Number(frpcFields.serverPort.input.value);
          patch.remotePort=Number(frpcFields.remotePort.input.value);
          patch.proxyName=frpcFields.proxyName.input.value.trim();
          patch.publicUrl=frpcFields.externalUrl.input.value.trim();
          patch.binaryPath=frpcFields.executable.input.value.trim();
          patch.downloadSource=frpcFields.downloads.options.input.value;patch.downloadMirror=frpcFields.downloads.mirror.input.value.trim();
          if(frpcFields.frpsToken.input.value)patch.authToken=frpcFields.frpsToken.input.value;
          if(patch.enabled&&!d.enabled&&!confirm('开启 frpc 将允许通过 frps 公网端口访问 DSH，确认继续？'))return;
        }
        feedback.textContent='';save.disabled=true;save.textContent='正在应用…';
        try{statusGeneration++;status=await api('/configure',{method:'POST',body:JSON.stringify({mode,patch})});renderContent();}
        catch(e){feedback.textContent=e.message;save.disabled=false;save.textContent='保存并应用';}
      },true);
      add(controls,save,feedback);node.append(controls);
      const runtimeError=el('div','dsh-mobile-error',d.error?'当前异常：'+d.error:'');runtimeError.hidden=!d.error;node.append(runtimeError);

      const pollError=el('div','dsh-mobile-error');pollError.hidden=true;node.append(pollError);
      view={mode,toggle,toggleDirty:false,enabledNote:enabledText.lastChild,addressSelector,drawQr,selectedUrl,runtimeError,pollError};
      toggle.addEventListener('change',()=>{if(view?.mode===mode)view.toggleDirty=true;});
      syncIndicators();
      node.scrollTop=savedScroll;

    }
    function locateAnchor(){
      // Known DSH 0.2.x footer layout: .settingsArea contains AccountMenu.
      // Never attach to footerActions (it is ABOVE the account row).
      const explicit=document.querySelector('[data-dsh-mobile-account-row],[data-testid="sidebar-account-row"]');
      if(explicit){const trigger=explicit.querySelector('button:not(.dsh-mobile-trigger)');if(trigger)return {anchor:explicit,trigger};}
      const settingsAreas=[...document.querySelectorAll('[class*="settingsArea"],[data-testid="sidebar-settings"]')];
      for(const area of settingsAreas){
        if(!area.closest('aside,[class*="sidebar"],[class*="Sidebar"]'))continue;
        const trigger=area.querySelector('button[aria-haspopup="menu"],button[aria-haspopup="true"],button:not(.dsh-mobile-trigger)');
        if(!trigger)continue;
        const anchor=trigger.parentElement;
        if(anchor && anchor.getBoundingClientRect().width>=20)return {anchor,trigger};
      }
      return null;
    }
    function detach(){if(button){button.remove();button=null;}if(sizeObserver){sizeObserver.disconnect();sizeObserver=null;}if(mounted){mounted.host?.removeAttribute('data-dsh-mobile-anchor');mounted=null;}}
    function install(){
      if(disposed)return;
      if(mounted?.anchor?.isConnected && mounted?.trigger?.isConnected && button?.isConnected)return;
      const found=locateAnchor();
      if(!found){detach();return;}
      if(mounted && mounted.anchor===found.anchor && button?.isConnected)return;
      detach();
      // 图标直接挂在 settings.launcher 下（与 yHnPSG_root 同级）；launcher 是 display:contents，
      // 挂载属性会把它升级为 flex 容器来承载 [账号区块 | 图标] 布局。
      const launcher=found.anchor.closest('[data-slot="settings.launcher"]');
      const host=launcher||found.anchor.parentElement||found.anchor;
      mounted={...found,host};
      host.dataset.dshMobileAnchor='';
      const b=el('button','dsh-mobile-trigger'); b.type='button'; b.dataset.state='off'; b.setAttribute('aria-label','DSH Mobile 手机连接设置'); b.setAttribute('title','DSH Mobile 手机连接设置');
      b.innerHTML='<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="7" y="2" width="10" height="20" rx="2"/><path d="M11 18h2"/></svg>';
      b.addEventListener('click',e=>{e.preventDefault();e.stopPropagation();open();});
      b.addEventListener('pointerdown',e=>e.stopPropagation());
      if(launcher){found.anchor.parentElement.after(b);}else{found.anchor.after(b);}
      button=b;
      // 图标框宽高始终跟随账号按钮高度保持正方形（展开 44px / 折叠 36px），保证两处行高一致。
      const syncHeight=()=>{const h=found.trigger.getBoundingClientRect().height;if(h){b.style.height=h+'px';b.style.width=h+'px';}};
      syncHeight();
      sizeObserver?.disconnect();
      sizeObserver=new ResizeObserver(syncHeight);
      // 观察 host（root 容器）而不是账号按钮：按钮高度差来自 padding（content-box 恒为头像尺寸，
      // 部分 Chrome 的 box:'border-box' 选项不生效），host 内容高度随折叠必定变化。
      sizeObserver.observe(host);
      syncTriggerState();
    }
    function scheduleInstall(){
      if(pending||disposed)return;
      pending=true;
      // 宿主还没有可用的账号行时限制探测频率，避免频繁全局 DOM 查询。
      // 不用 requestAnimationFrame：后台标签页里 rAF 不触发，会让重装永久卡住。
      const delay=Math.max(0,600-(Date.now()-lastAnchorScan));
      anchorScanTimer=setTimeout(()=>{
        anchorScanTimer=null;lastAnchorScan=Date.now();install();pending=false;
      },delay);
    }
    function apply(ctx){
      disposed=false;
      const style=el('style');style.dataset.plugin='dsh-mobile-plugin';style.textContent=STYLE;document.head.append(style);
      install();
      // 不再对弹窗内部每一次文本/日志更新反复全局查找侧边栏。
      observer=new MutationObserver(()=>{
        if(!mounted?.anchor?.isConnected || !mounted?.trigger?.isConnected || !button?.isConnected)scheduleInstall();
      });
      observer.observe(document.body,{childList:true,subtree:true});
      // 图标常驻侧边栏，用低频轮询维持状态色；弹窗打开时由 refresh() 负责，避免重复请求。
      const pollTrigger=()=>{
        if(document.hidden||modal)return;
        api('/status').then(s=>{status=s;syncTriggerState();}).catch(()=>{});
      };
      const triggerVisibility=()=>{if(!document.hidden)pollTrigger();};
      document.addEventListener('visibilitychange',triggerVisibility);
      pollTrigger();
      triggerPoll=setInterval(pollTrigger,20000);
      const disposer=()=>{disposed=true;observer?.disconnect();observer=null;if(anchorScanTimer){clearTimeout(anchorScanTimer);anchorScanTimer=null;}pending=false;if(triggerPoll){clearInterval(triggerPoll);triggerPoll=null;}document.removeEventListener('visibilitychange',triggerVisibility);close();document.removeEventListener('keydown',escapeHandler);detach();style.remove();};
      if(typeof ctx.effect==='function')ctx.effect(()=>disposer,'dsh-mobile browser UI');
      return disposer;
    }
    exports.name='dsh-mobile-plugin';exports.apply=apply;
    return module.exports;
  }
});
