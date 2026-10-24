# DSH Mobile Plugin dev.14 · 接口代理集成检查记录

检查日期：2026-10-22

## 检查环境与范围

- 使用用户提供的 `dev.13` 完整源码作为基础，修复代码保留到 `dev.14`。
- 当前执行容器：Node.js 22.16.0 / npm 10.9.2。
- 已实际运行 `npx --yes @deepseek-ai/dsh web --no-open`；npm 请求 `https://registry.npmjs.org/@deepseek-ai%2fdsh` 时因 DNS `EAI_AGAIN` 失败，**没有成功下载/启动 DSH**。
- 文档所需 DSH Node.js 基线为 22.19+ 或 24+，当前 Node 22.16 也不符合要求。
- 因此本轮结论是“可验证的源码修复 + 模拟 DSH Host 的双重认证集成测试”，不是实际 DSH 全接口验收通过。

## 已确认并修复的缺陷

1. **DSH Host 第二层认证缺失。** 旧版在通过插件访问密码后，把原生 `/api` 请求直接送给 DSH；但 DSH Host 的 Remote RPC / WebSocket 还要求其自己的 authority-bound 会话 Cookie，旧版可能得到 401。新版仅在宿主进程内调用官方 `ctx.connection.authenticatedUrl()`，向本机 DSH 的 `GET /?token=…` 完成 Cookie 交换。Cookie 只驻留服务端内存，经网关内部转发，不放入二维码、日志或移动端响应。
2. **非默认 DSH Web 端口。** 新版从 `ctx.webServer.port` 获取真正监听端口，不再强行假设上游永远是 3080；明确设置 `DSH_MOBILE_UPSTREAM` 时保持用户指定地址优先。
3. **上游会话失效。** 收到 DSH Host 的 401 后清理缓存，下次请求按公开接口重新换取会话；进程重启后建立新会话。首次请求可能仍返回 401，调用方可重试；尚未加入非幂等 POST 的自动重放（避免重复执行 Agent 操作）。
4. **上游签名 Cookie 泄漏风险。** 响应中剥离 `dsh-auth-*` Set-Cookie，请求中忽略移动客户端伪造的 `dsh-auth-*` Cookie，只使用本机获取的 Host 会话。
5. **长连接清理。** 下游客户端断开时中断上游 HTTP 请求，避免 SSE/下载类流在客户端离线后继续占用资源。
6. **WebSocket 会话撤销。** 退出登录、访问令牌失效或密码变更时，关闭已建立的 WebSocket，避免授权撤销后仍可继续执行远程操作。
7. **上游认证诊断。** 网关状态新增 `upstreamAuthenticated`，基础配置页可显示“网关已启动但 DSH 接口认证待确认”。

## 已完成的可重复测试

本地 `npm test`：**87 项通过，0 项失败**，其中新增模拟 Host 的集成测试涵盖：

- 无 Host 会话时原生 API 拒绝；取得 Host 会话后原生 RPC HTTP 代理正常；
- 文件二进制下载与 206 Partial Content；
- `/api/remote.mux` 的 WebSocket Upgrade / 101；
- Host Cookie 失效后的重新建立、同一批并发请求不重复建立会话；
- 不允许 DSH 授权令牌随 HTTP 重定向发往外域；
- 无法获得 Host 会话时网关以 502 失败关闭；
- Host 认证 Cookie 不泄漏至移动浏览器；
- 基于当前 DSH Web 实际端口的上游自动发现；
- 退出登录后已建立的 WebSocket 立即关闭。

## 还没有完成的验收

- **真实 DSH 进程与插件加载**：因当前 npm DNS 不通，无法检验插件与实际 DSH 版本的 Cordis API 初始化时序。
- **原生 Typert RPC 方法语义**：会话、Agent、模型、工具、Skills、审批、设置等需要真实 Host 和合规请求数据才能逐项执行；模拟代理能证明传输链路，不代表这些业务接口语义均通过。
- **真实文件上传/大体积断点续传**：已有 HTTP 代理覆盖，尚需真实 DSH 文件管理端点验证。
- **Cloudflare/frpc 公网连通性**：当前没有真实隧道和 frps 服务器，无法完成公网及 WSS 端到端测试。
- **生产安全**：LAN HTTP 仍然明文，不能声称具备生产级传输加密。

## 可联网电脑复测

本源码包含脚本 `scripts/run-live-dsh-smoke.sh`（Linux/macOS + Node.js 22.19+ 或 24+）：

```bash
bash ./scripts/run-live-dsh-smoke.sh
```

脚本使用临时隔离的 `DSH_HOME`，本地打包插件，通过 `npx @deepseek-ai/dsh plugin --profile web add` 安装，再执行 `npx @deepseek-ai/dsh web --no-open`。为避免无意开放公网，测试配置禁用 Cloudflare/frpc，只启用本地网关；检查二维码信息接口、Mobile 密码认证、真实 DSH 首页、API 第二层授权以及 `/api/remote.mux` WebSocket 握手。脚本退出后保留日志路径，便于回溯。

注意：该脚本是可执行测试方案，**当前环境没有成功运行这段实际 DSH 启动流程**，不应将脚本随源码交付等同于已通过实机测试。脚本验证的是基础通道，不是“DSH 所有业务 API 都正确”的证明。
