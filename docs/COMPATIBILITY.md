# DSH 宿主兼容性记录

目前没有提供目标 DSH 版本或真实 dsh Web 实例，下面均为“静态方案 / 待验收”，不能当作已通过实测。

## Web 插件生命周期
- npm 包需同时包含 `dsh.bundle.patch`、`dsh.client`、host `./lib/index.js` 与浏览器 `./lib/client.js`。
- `cordis.patch.yml` 插入唯一 `dsh-mobile-plugin` host 级条目。注意不要将其插入每个 Session 的 agent preset，否则多次创建会话时会重复注册全局路由。
- 为避免 DSH 0.1.5+ 的 `connection.rpc.handle()` 的部分兼容问题，管理路由采用 `ctx.webServer.register({kind:'prefix',path:'/dsh-mobile/admin'})`，并使用 connection.requestRejection(req) 进行宿主检查。

## 头像行按钮
- 本项目**不将**入口注册到 `sidebar.footer.action`，该位置在账号行之上，不满足需求。
- 当前策略：在 `.settingsArea` 中寻找 AccountMenu 对应按钮，只有检测到宽度 >= 110px 的账号行才插入末尾 29x29px 手机按钮；侧边栏折叠后按钮会隐藏，展开后自动恢复。
- 风险：不同 DSH 版本的 DOM、CSS Modules 类名与账户菜单结构变化会令策略失效。未检测到时不修改账号行，也不挪到其他位置。
- 待 DSH 目标版本确定后，可能需要基于 `AccountMenu` 做最小宿主补丁（单独征求批准，不静默修改 app.asar）。

## 需要真实 DSH 实例核验
- DSH 真实 upstream 端口与 trustedHosts/Origin 行为。
- `/api` 的合法会话和 Remote.mux 权限机制；自定义密码**不能**绕开 DSH 原有授权。
- 二维码扫码前的 TLS 配置：当前 LAN HTTP 尚不满足生产级安全传输要求。
- Cloudflare Quick Tunnel 不能使用 SSE；需验证 DSH 0.2.x 流式操作走 WebSocket。
- named Tunnel token 环境变量支持、cloudflared stdout 输出行为及实际路由配置。

## 需要的运行资料
- `dsh --version`
- OS / DSH Web 部署方式，是否 Docker / WSL / 桌面版
- Web 侧账号行 DOM 结构或截图，App 设计图后续再对接

## v0.1.0-dev.5 配置页面与公网域名
- 账号行挂载逻辑保持不变；新版调整的是插件弹窗内的布局、纯文字导航、启用开关以及可调整高度的日志面板，真实 DSH 主题/窗口尺寸仍需验证。
- 局域网 IP 下拉框仅控制向手机展示的 **二维码/连接地址**，不修改网关的 `0.0.0.0:<端口>` 监听行为；`lan.preferredAddress` 新字段在 `schema:2` 配置中为可选，dev.4 用户升级时默认空值且不会触发密码轮换。
- 当首选 IPv4 不再出现在网卡列表中时显示当前可用的首个 IP，保存的首选地址保留，原 IP 恢复后可再次选中。
- Quick Tunnel 临时 `trycloudflare.com` 域名由 Cloudflare 分配，`cloudflared` 进程结束后不能保证复用旧域名；**不会缓存并展示已失效的 URL**。固定域名必须使用 Named Tunnel 并配置 Cloudflare 账户下的域名。
