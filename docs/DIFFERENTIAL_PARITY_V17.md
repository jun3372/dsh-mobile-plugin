# DSH Mobile v0.1.0-dev.17：原生 Host / 插件网关差分审计

## 结论（严格口径）

- 已在受认证的**模拟 Host**中成对验证直连和插件代理：HTTP 方法、路径、重复/编码查询参数、二进制/JSON 请求体、状态码 `200/201/204/206/404/422`、响应字节、分段文件、SSE、重定向、WebSocket 数据帧及错误握手响应。
- 已修复 `dev.16` 中 **`/api/...?...token=普通DSH参数` 被误判为二维码 URL 而返回 400** 的问题。二维码特殊处理仅保留在 `GET /?token=<手机访问密码>`；其他原生业务路径可以传递自己的 `token` 参数。若值恰好是手机访问密码，则仍拦截，防止泄露。
- 已修复 **WebSocket 升级被 Host 拒绝时，上游原本的 HTTP 响应体和相关头信息被丢弃** 的问题。
- 当前执行环境未能通过 `npx @deepseek-ai/dsh web` 获取/启动真实 DSH。因此**不能证明所有真实 DSH 接口都通过**。

## 验收所需的两端

真正的全接口一致性测试需要**同一台机器同一版本**的：

1. 原生 DSH Web 地址（例如 `http://127.0.0.1:3080`），能用独立的**原生 DSH 浏览器 Cookie**登录。
2. DSH Mobile 代理地址（例如 `http://127.0.0.1:39081`），能用插件设置的访问密码登录。
3. 从相同 DSH 版本的生成 Remote 描述符与准确注册的 HTTP/Fetch、WebSocket 路由制作的**完整接口清单**，包含每个接口的有效测试输入、固定状态前置条件和预期成功状态。

如果没有第三项，即使清单全部通过，也不能声称覆盖所有接口。请在隔离的 DSH_HOME 或备份过的测试实例上操作，避免真实数据被修改。

## 逐接口的双端对照工具

```bash
# 仅供本机隔离测试：请勿将 Cookie、密码和报告提交公共仓库。
export DSH_DIRECT_URL='http://127.0.0.1:3080'
export DSH_DIRECT_COOKIE='dsh-auth-xxxx=实际从本机 DSH 会话获取的有效凭证'
export DSH_MOBILE_GATEWAY_URL='http://127.0.0.1:39081'
export DSH_MOBILE_TEST_PASSWORD='当前网络入口的插件访问密码'
node scripts/compare-direct-proxy.mjs ./complete-dsh-interfaces.json ./parity-results.json
```

工具先通过网关认证，然后针对清单每项分别向原生 DSH 和网关请求，**原生端只作为对照基线，代理失败后绝不改为直连继续算通过**。HTTP 请求强制 `redirect: manual`，分别比对状态码、响应字节 SHA-256、`Content-Type`、`Content-Encoding`、`Content-Range`、`ETag`、`Cache-Control`、`Content-Disposition`、`Last-Modified`、`Vary` 等稳定的业务相关响应头。DSH Host 内部 Cookie 不可穿透到手机，网关认证标记、Hop-by-Hop 头、连接相关头是**明确排除的必要差异**。同源绝对 `Location` 在网关处转为相对路径，以阻止手机直连 3080。

WebSocket 清单项**必须**含可执行的真实业务帧 `payloadBase64` 和 `expectFrames`，审计会独立向两端发送同样的帧并核对返回帧字节。对多路复用、心跳、竞态、动态会话 ID、取消与重连等场景还需独立准备确定性的场景与规范化规则；单一帧通过不代表整个 Remote 流协议覆盖完成。

清单结构示例（仅示例，不是 DSH 全接口清单）：

```json
{
  "sourceRevision": "实际安装的 DSH 版本或 commit",
  "declaredCount": 2,
  "interfaces": [
    {"id":"home","kind":"http","method":"GET","path":"/","expectStatus":200},
    {"id":"sample-api","kind":"http","method":"POST","path":"/api/真实路由","headers":{"Content-Type":"application/json"},"body":{"参数名":"来自匹配版本的实际有效参数"},"expectStatus":200}
  ]
}
```

HTTP 接口允许在 `bodyBase64` 放原始二进制请求体。真正的 Remote/Fetch 方法应以当前安装版本源码为准，不能靠猜测路径生成清单。未被列出的路由和业务方法一律计为**未验收**。

## 必须明确的例外

- 手机连接前有插件密码认证，所以“未经认证”的网关 401 与已认证原生 DSH 的 200 本来就不等价。比较必须双方完成相应认证。
- 网关不下发 DSH Host 的内部 `dsh-auth-*` Cookie；它只在服务端调用 Host。这是安全隔离，不能为追求逐字节相同而取消。
- 原生 DSH 产生的同源绝对重定向会被转换为相对路径；因此 `Location` 字符串可能不同，但客户端仍应停留在网关。
- 动态时间戳、随机 ID、实时 Agent 输出通常不具备可直接比对的字节确定性，应使用相同的隔离数据与业务结果断言，不应在没有明确理由时直接忽略这些字段。
- Host 401、插件 502、无效接口 404、伪装的 HTML 200，以及无实际业务帧的 WebSocket 101，均不能算作成功的业务接口验收。

## 当前不可获得的证据

本容器尝试 `npx --yes @deepseek-ai/dsh web --no-open --port 31809` 时没有完成下载/启动，npm 网络不可用，Node 为 `v22.16.0`。没有实际 DSH 的完整接口表、真实认证会话及可复现业务前置条件，因此**本次不签署“DSH 全部接口响应一致”的验收结论**。
