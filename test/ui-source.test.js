import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
const content=await readFile(new URL('../lib/client.js',import.meta.url),'utf8');
test('settings sidebar has icon-free navigation and labelled accessible switch',()=>{
  assert.match(content,/\['base','基础配置'\]/);
  assert.match(content,/\['lan','局域网'\]/);
  assert.match(content,/\['public','Cloudflare隧道'\]/);
  assert.doesNotMatch(content,/📶|🌐|dsh-mobile-tab-dot|dsh-mobile-nav-status/);
  assert.match(content,/dsh-mobile-switch-input/);
  assert.match(content,/aria-label.*开启局域网访问/);
});
test('settings UI offers one LAN QR and IP selector for multiple interfaces',()=>{
  assert.match(content,/lanAddresses\.length>1/);
  assert.match(content,/selectedUrl\(addressSelector/);
  assert.match(content,/preferredAddress=addressSelector\.input\.value/);
  assert.match(content,/每次只显示一个二维码/);
});
test('runtime log panel is resizeable and quick tunnel limitation is explained',()=>{
  assert.match(content,/height:206px/);
  assert.match(content,/resize:vertical/);
  assert.match(content,/Cloudflare 每次创建连接时随机分配/);
  assert.match(content,/最近运行日志/);
});
test('Cloudflare menu copy and native select styling are used consistently',()=>{
  assert.match(content,/\['public','Cloudflare隧道'\]/);
  assert.match(content,/dsh-mobile-select-wrap/);
  assert.match(content,/dsh-mobile-select\{appearance:none/);
  assert.match(content,/document\.createElement\(tag\)/);
});
test('status polling patches live fields rather than rebuilding the whole settings view',()=>{
  const update=content.slice(content.indexOf('async function refresh()'),content.indexOf('function close()'));
  assert.match(update,/if\(!view\)renderContent\(\)/);
  assert.match(update,/syncIndicators\(\)/);
  assert.match(update,/syncLiveView\(\)/);
  assert.doesNotMatch(update,/contains\(document\.activeElement\)/);
  assert.match(content,/if\(key===qrKey\)return/);
  assert.match(content,/viewScroll\[currentTab\]/);
});
test('mounted account button avoids redundant document-wide scans',()=>{
  assert.match(content,/if\(mounted\?\.anchor\?\.isConnected && mounted\?\.trigger\?\.isConnected && button\?\.isConnected\)return/);
  assert.match(content,/Math\.max\(0,600-\(Date\.now\(\)-lastAnchorScan\)\)/);
});

test('dropdown and text input use identical control heights and radii',()=>{
  assert.match(content,/--mobile-control-height:40px/);
  assert.match(content,/\.dsh-mobile-input\{[^\n]*height:var\(--mobile-control-height\);min-height:var\(--mobile-control-height\)/);
  assert.match(content,/\.dsh-mobile-select\{[^\n]*height:var\(--mobile-control-height\);min-height:var\(--mobile-control-height\)/);
  assert.match(content,/\.dsh-mobile-select\{[^\n]*border-radius:9px/);
});
test('sidebar menu contains only single-line labels, runtime states remain in header',()=>{
  assert.match(content,/\.dsh-mobile-tab\{[^\n]*min-height:46px/);
  assert.match(content,/\.dsh-mobile-tab\{min-height:44px;padding:0 11px\}/);
  assert.match(content,/\.dsh-mobile-tab\{min-height:44px;padding:0 8px\}/);
  assert.match(content,/tab\.append\(labelNode\)/);
  assert.doesNotMatch(content,/dsh-mobile-nav-status|sub\.dataset\.mode/);
  assert.match(content,/intro\.append\(overview\)/);
  assert.match(content,/data-dsh-mobile-overview/);
});

test('runtime logs live in standalone sidebar tab, not inside network settings',()=>{
  assert.match(content,/\['logs','运行日志'\]/);
  assert.match(content,/if\(currentTab==='logs'\)\{renderLogPage\(node,savedScroll\);return;\}/);
  assert.equal((content.match(/const logSection=section\('最近运行日志'/g)||[]).length,1);
  const networkPage=content.slice(content.indexOf('const mode=currentTab;const d=status[mode];'),content.indexOf('function locateAnchor()'));
  assert.doesNotMatch(networkPage,/logSection|dsh-mobile-log-top|renderLogs\(/);
  assert.match(content,/viewScroll = \{base:0,lan:0,public:0,frpc:0,logs:0\}/);
});
test('log polling updates in place without dereferencing a network configuration',()=>{
  const live=content.slice(content.indexOf('function syncLiveView()'),content.indexOf('function renderLogPage('));
  assert.match(live,/if\(currentTab==='logs'\)\{/);
  assert.match(live,/renderLogs\(view.logBox,view.logMeta,logs\)/);
  assert.match(live,/view.copyLog.disabled=!logs.length/);
  assert.ok(live.indexOf("if(currentTab==='logs')")<live.indexOf('const d=status[currentTab]'));
  assert.match(content,/dsh-mobile-log--full/);
  assert.match(content,/logHeights.logs/);
});

test('settings dialog keeps the same bounded height for every sidebar tab',()=>{
  // The panel owns the height; tab content scrolls independently.
  assert.match(content,/\.dsh-mobile-panel\{[^\n]*height:min\(760px,calc\(100dvh - 52px\)\)/);
  assert.match(content,/@media\(max-width:760px\)\{[^\n]*\.dsh-mobile-panel\{[^\n]*height:min\(760px,calc\(100dvh - 20px\)\)/);
  assert.match(content,/\.dsh-mobile-layout\{[^\n]*min-height:0;flex:1;overflow:hidden/);
  assert.match(content,/\.dsh-mobile-content\{[^\n]*min-height:0;overflow-y:auto/);
  assert.match(content,/\.dsh-mobile-menu\{[^\n]*overflow-y:auto/);
  assert.match(content,/\.dsh-mobile-header\{[^\n]*flex:0 0 auto/);
});

test('frpc appears as separate icon-free menu and status, preserving fixed-height settings modal',()=>{
  assert.match(content,/\['frpc','frpc隧道'\]/);
  assert.match(content,/\['lan','public','frpc'\]/);
  assert.match(content,/if\(mode==='frpc'\)\{/);
  assert.match(content,/frps 服务器地址/);
  assert.match(content,/frps 公网映射端口/);
  assert.match(content,/共用公网访问密码/);
  assert.match(content,/viewScroll = \{base:0,lan:0,public:0,frpc:0,logs:0\}/);
});
test('basic tab owns passwords and shared port; network tabs keep mirror settings',()=>{
  assert.equal((content.match(/section\('访问安全'/g)||[]).length,1);
  assert.doesNotMatch(content,/field\('密码方式'/);
  assert.doesNotMatch(content,/重新生成随机密码/);
  assert.match(content,/const lanPassword=passwordRow\('局域网访问密码'/);
  assert.match(content,/const publicPassword=passwordRow\('公网访问密码/);
  assert.match(content,/if\(mode==='frpc'\)\{/);
  assert.match(content,/GitHub 下载来源/);
  assert.match(content,/ghfast\.top/);
  assert.match(content,/ghproxy\.net/);
  assert.match(content,/patch\.downloadSource=frpcFields\.downloads\.options\.input\.value/);
  assert.match(content,/patch\.downloadSource=publicDownloadControls\.options\.input\.value/);
});


test('base settings are separate and network forms do not edit common credentials',()=>{
  assert.match(content,/if\(currentTab==='base'\)\{renderBasePage\(node,savedScroll\);return;\}/);
  const base=content.slice(content.indexOf('function renderBasePage('),content.indexOf('function renderContent()'));
  const network=content.slice(content.indexOf('const mode=currentTab;const d=status[mode];'),content.indexOf('function locateAnchor()'));
  assert.match(base,/mode:'base',patch/);
  assert.match(base,/field\('共享代理端口'/);
  assert.match(base,/lanPassword/);
  assert.match(base,/publicPassword/);
  assert.doesNotMatch(network,/const port=field\('共享代理端口'/);
  assert.doesNotMatch(network,/const passwordCurrent=field/);
  assert.match(network,/访问密码与共享代理端口请前往左侧/);
});

test('QR is refreshed on password revision and warns that QR includes a password',()=>{
  assert.match(content,/qrRevision/);
  assert.match(content,/key=mode\+':'\+url\+':'\+revision/);
  assert.match(content,/二维码链接携带访问密码/);
});
