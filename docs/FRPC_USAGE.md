# DSH Mobile frpc 隧道配置指南（开发预览）

## 准备条件

- 你拥有可连接的 `frps` 服务端（公网 VPS 或其他服务器）；服务器需允许 frps 控制端口和选定的 TCP 远程端口访问。
- 无需预先手动安装 `frpc`：启用 frpc 隧道时，插件先查找用户填写的完整路径、环境变量 `DSH_MOBILE_FRPC`、插件私有 `bin` 目录和系统 PATH。若都没有找到，会自动从 [官方 GitHub Releases](https://github.com/fatedier/frp/releases) 下载 **frp v0.71.1** 对应安装包。
- 自动安装支持 Windows x64/ARM64、macOS x64/ARM64、Linux x64/ARM64/ARM；其他平台或 GitHub 无法访问时，仍可在高级设置填写手动安装的 `frpc` 程序绝对路径。
- 原有的 DSH Mobile 代理网关默认监听 `0.0.0.0:39081`，frpc 会将远程 TCP 端口转发到**同一共享网关**的 `127.0.0.1:39081`，没有额外本地代理端口。

## frps 最小示例

`frps.toml`（**服务器端**，不是插件的配置）：

```toml
bindPort = 7000
auth.method = "token"
auth.token = "请替换成高强度的独立frps令牌"
```

把服务端的 TCP `7000` 以及你选定的远程映射端口在安全组/防火墙里做正确的访问控制。不要在公网暴露管理面板。

## DSH 插件 Web 配置

在左侧选择「frpc隧道」，依次填：

| 字段 | 示例 | 说明 |
|---|---|---|
| frps 服务器地址 | `frps.example.com` | 仅域名/IP，**不带** `http://`、端口 |
| frps 控制端口 | `7000` | 对应 `frps.toml` 的 `bindPort` |
| frps 公网映射端口 | `39081` | 服务器允许的 TCP 端口，与控制端口不同 |
| 映射名称 | `dsh-mobile` | frps 上必须唯一 |
| frps 认证 Token | 自己的 frps Token | 仅保存在本机，不包含在二维码/状态响应 |
| 手机访问地址 | `https://mobile.example.com` | 如留空，则按 `http://frps.example.com:39081` 生成（不安全） |
| frpc 程序路径 | `/usr/local/bin/frpc` | 留空自动查找；找不到则下载 GitHub 官方程序 |

打开开关并点击「保存并应用」。frpc 成功报告代理上线后，顶部状态变为绿色并显示独立二维码。

frpc 生成的配置文件位于 `$DSH_HOME/dsh-mobile-plugin/frpc.toml`。系统支持时使用 `0600` 权限（含 frps Token），请勿提交到仓库。

## 认证与扫码

因为 Cloudflare 和 frpc 共用一个本机代理端口并且都以回环源接入，所以本版 **frpc 与 Cloudflare 共用公网访问密码**（不是 frps Token），局域网保持独立密码。frpc 扫码 payload 使用 `mode: public, transport: frpc`，仍然使用已有的 DSH Mobile 协议。

## 非常重要：HTTPS/WSS

- frpc 的 `transport.tls.enable = true` 只加密 frpc↔frps 通道，**不代表**手机访问的 `http://frps.example.com:39081` 就有 TLS。不要将 HTTP 明文暴露在互联网；高权限 DSH 请求、访问密码、登录令牌可能被第三方截获。
- 建议用已正确配置证书的 HTTPS 反向代理接入 frps TCP 远程映射端口，并配置手机连接 URL 为实际使用的 `https://` 域名；确保 HTTP 和 WebSocket 升级都能经由反向代理正确转发。
- 如需要断点续连，确认反向代理支持长连接和 WSS；真实 frps、HTTP/WSS、移动设备兼容性尚待实机验收。

## 状态和故障排查

- `frpc 自动下载失败`：检查当前运行 DSH 的机器能否访问 `github.com` 及 GitHub Release 下载域名；在「运行日志」查看具体 HTTP 或网络错误。若处于受限网络，请手动下载官方 Release 后在高级设置填写完整路径。
- 自动下载包必须通过官方 `frp_sha256_checksums.txt` 的 SHA-256 校验，校验不通过不安装，也不会执行压缩包中的其他文件；Windows ZIP 仅提取 `frpc.exe`，Linux/macOS tar.gz 仅提取 `frpc`。下载后保存至 `$DSH_HOME/dsh-mobile-plugin/bin/`，下次重启复用已有程序。
- `未找到 frpc`：若已手动填写路径，请检查路径、执行权限及 `DSH_MOBILE_FRPC`；手动指定了无效路径时不会绕过用户选择改用自动下载。
- `frpc 无法连接 frps`：请检查 frps 服务是否启动、7000 TCP 连通性、Token 是否一致、映射名称是否冲突，以及远程端口是否被防火墙阻挡。
- 运行中断：插件会记录中文运行日志并按退避机制自动重试；手动关闭会停止进程，并在下一次 DSH 重启时继续保持关闭。
- Cloudflare 启用与否**不影响 frpc 独立开关**。若关闭两种公网入口，只保留局域网，网关应只接受局域网密码；反之亦然。
