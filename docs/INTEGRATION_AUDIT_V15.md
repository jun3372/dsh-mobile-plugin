# DSH Mobile Plugin v0.1.0-dev.15：严格网关代理接口审计

审计日期：2026-10-22。

## 最重要的结论

**不能宣布 DSH 所有接口通过。** 已尝试在当前容器执行 `npx --yes @deepseek-ai/dsh web --no-open --port 31809`，但 npm 下载 `@deepseek-ai/dsh` 失败：DNS `EAI_AGAIN registry.npmjs.org`。本机 Node.js 为 `v22.16.0`，低于项目建议使用的 `22.19+`。因此真实 DSH Host 未能启动，无法从该安装版本获得完整业务 RPC 描述符，也无法执行真实的 Session / Agent / Approval / File / Settings 调用。

截至本轮，**离线代理覆盖**与**真实 DSH 全接口覆盖**必须严格区分；测试用例数不等于已验证 DSH 接口数。

## 修复了什么

1. **重定向不能绕过代理。** DSH Host 若返回绝对 `Location: http://127.0.0.1:<Host端口>/...` 或其 `localhost` 别名，插件将其转换成相对路径，令客户端仍请求插件端口。如果返回指向其他本机端口的重定向，插件拒绝并返回 `502 upstream_direct_redirect_blocked`，绝不让客户端悄悄跳到 DSH 3080。跨互联网的合法重定向并未被代理改写，但严格审计脚本不会视其为成功接口响应。
2. **对代理响应做独立确认。** 通过插件代理的 HTTP / WebSocket Upgrade 响应都带 `X-DSH-Mobile-Gateway: <instanceId>`。用于集成路由验证，**不是认证凭证**，不能取代身份校验。
3. **修复假阳性冒烟脚本。** 旧脚本检查不存在的 `/api/__dsh_mobile_smoke__`，只要求不是 401/502，故 404 也会误算通过。新脚本明确要求不存在的 API 返回 404，并标记为“负向控制，不计入成功 API”；首页还需要通过网关取得 2xx 与 HTML；原生 WebSocket 需要网关转发标记。
4. **禁用测试过程自动跟随重定向。** 对所有 HTTP 审计调用设置 `redirect:'manual'`；如重定向指向网关以外的地址，判定失败。
5. **添加离线反向验证。** 正常 Host 仍在，但网关停止时请求必须失败；路由错误时的 404、SPA fallback HTML 200、未经网关的 101，都不构成通过证明。增加方法、二进制上传/下载、206、multipart、SSE、WebSocket 的正向传输测试。

## 真实 DSH 验收：必须进行“逐接口清单”验证

首先在能联网、安装 Node.js 22.19+ 或 24+ 的机器运行 `npx @deepseek-ai/dsh web`，并安装 **dev.15** 插件。然后从**同一版本 DSH**的生成 Remote 描述符和准确注册的 Fetch / WS 路由建立完整接口清单，写入 JSON 文件（示例仅表示格式，绝不能冒充完整清单）：

```json
{
  "sourceRevision": "实际安装的 DSH 版本或 Git commit",
  "declaredCount": 2,
  "interfaces": [
    {"id":"web-shell", "kind":"http", "path":"/", "method":"GET", "expect":{"status":200,"contentType":"text/html","minimumBytes":10}},
    {"id":"remote-stream-transport", "kind":"websocket", "path":"/api/remote.mux", "expect":{"status":101}}
  ]
}
```

上面仅覆盖 Web 页面和 WS 握手，**并未覆盖任何真正的 Remote 业务方法**。业务接口须补充如 `/api/<namespace>/<method>` 的具体方法、输入 `{"args":{...}}`、预期 JSON/附件/行为；文件上传下载与会话状态也必须分别提供可复现的数据。需要确认依赖服务、权限、Agent 模型以及审批流程的状态前置条件。对会修改数据的请求应使用隔离测试 DSH_HOME。

专用工具：

```bash
export DSH_MOBILE_GATEWAY_URL=http://127.0.0.1:39081
export DSH_MOBILE_TEST_PASSWORD='此网关本机回环入口对应的实际访问密码'
node scripts/audit-gateway-only.mjs ./complete-api-manifest.json ./gateway-audit-report.json
```

**密码选择说明：** 在当前共享网关设计中，如已启用 Cloudflare/frpc 公网访问，`127.0.0.1` 回环入口会使用“公网访问密码”；只有公网入口关闭时才使用局域网密码。执行工具前必须提供实际对应的密码，否则会正确地判为认证失败。

这个脚本：

- **只接受网关地址**，不接收直接 Host 地址作为“备选目标”，也不会从失败的插件请求跳到 3080；
- 必须正确登录插件，全部 HTTP 请求必须使用插件令牌；
- 检查 HTTP 2xx / WS 101、返回 MIME、内容/大小/哈希、`X-DSH-Mobile-Gateway` 与响应 URL；
- 404、401、502、返回 SPA HTML 的假 200、缺少网关标识、任何离开网关的重定向都判失败；
- 清单数量不匹配、无接口列表、重复 ID 等都直接终止；
- 每个声明接口都要取得真实成功响应，否则退出码非零；
- 导出 JSON 检查结果；只有**已经对照相同版本 DSH 实际路由/Remote 描述符完成清单校验**，才能说“清单覆盖所有接口”。运行器自身不能凭手工清单推断 DSH 是否还有遗漏的接口。

WebSocket 检查支持本地 HTTP/WS 与 HTTPS/WSS（TLS 证书须受信任），目前只覆盖 101 Upgrade 和路由标记；真正的 Remote stream 帧、取消、重连和方法语义仍须有对应的端到端场景，**不能仅凭 101 宣称所有流式接口通过**。

可使用隔离宿主的执行脚本：

```bash
DSH_MOBILE_REQUIRE_FULL_AUDIT=1 \
DSH_MOBILE_AUDIT_MANIFEST=/absolute/path/complete-api-manifest.json \
bash ./scripts/run-live-dsh-smoke.sh
```

该脚本会把测试时 Cloudflare、frpc 关闭，启动全新的 DSH_HOME；如果要求完整审计但没提供清单，会**立即以错误码 3 终止**，不再将默认 3080 的可访问性判成通过。

## 已完成和待完成

| 项目 | 结果 |
|---|---|
| Mock DSH HTTP 方法与响应透传 | 离线测试通过 |
| 二进制文件、206、multipart、SSE、WebSocket 握手 | 离线测试通过 |
| 登录、Host 第二层 Cookie、权限撤销 | 离线测试通过 |
| 代理失败但原生 Host 正常 | 反向测试通过；代理验收判失败 |
| 直连 3080 的重定向 | 同源归一化 / 非同端口拒绝 |
| 真实 `npx @deepseek-ai/dsh web` | **失败：npm DNS EAI_AGAIN** |
| 真实 DSH 完整 Remote 方法清单 | **未取得，未验收** |
| 真实 Agent/模型/会话/文件/审批全流程 | **未验收** |
| Cloudflare/frpc 公网逐接口复测 | **未验收** |

## 结论口径

正确：**“dev.15 通过代理层离线回归，增加了严格网关路由验收工具；真实 DSH 全业务接口未验证。”**

不正确：**“DSH 默认 3080 可以访问，所以代理全部通了。”**
