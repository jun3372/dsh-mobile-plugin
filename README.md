# DSH Mobile 手机连接插件

[![Build](https://github.com/jun3372/dsh-mobile-plugin/actions/workflows/build.yml/badge.svg)](https://github.com/jun3372/dsh-mobile-plugin/actions/workflows/build.yml)
![Version](https://img.shields.io/badge/version-1.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)

为 DSH Web 宿主（`dsh web`，基于 `@deepseek-ai/cordis`）提供手机远程访问网关的插件，配套 Flutter 客户端（Android / iOS / HarmonyOS NEXT）。

> **开发预览版**：尚未在大规模真实环境中验收，**不建议公网用于生产环境**。插件为纯 JavaScript（ESM）、Node ≥ 22、零 runtime 依赖；App 为 Flutter（Dart SDK ^3.11.5）。

## 功能特性

**插件（服务端）**

- 单一移动代理网关，默认 `0.0.0.0:39081`，HTTP / WebSocket 共用端口
- 三种访问通道：局域网直连、Cloudflare Tunnel（快速 / 命名）、frpc 隧道
- frpc / cloudflared 未安装时自动从官方 GitHub Release 下载并做 SHA-256 校验
- 扫码配对：二维码为短 URL（含访问密码），App 扫码即连
- DSH 重启后自动恢复已启用的网络，失败按退避策略自动重试
- 中文运行日志（Cordis logger + stderr 双通道，Web 配置页可视化展示）

**App（客户端）**

- 扫码 / 手动绑定多个 DSH 服务端，连接状态管理
- 任务列表：新建、搜索、归档管理
- 会话详情：流式消息、工具调用、审批与多题问答、计划详情、排队消息
- 工作区文件浏览与预览、代码语法高亮
- 会话草稿与附件、模型选择、深浅色主题

## 架构

```
┌──────────┐  局域网 / Cloudflare Tunnel / frpc   ┌─────────────────┐      ┌──────────┐
│ Flutter  │ ───────── HTTP / WebSocket ────────▶ │  移动代理网关    │ ───▶ │ DSH Host │
│   App    │        （共用端口 39081）             │  dsh-mobile     │      │ 3080     │
└──────────┘                                      └─────────────────┘      └──────────┘
        ▲  扫码配对：二维码含连接地址与访问密码
```

- 三种通道共用同一 TCP 端口、HTTP API 与 WebSocket 转发，无需开放额外端口
- 网关通过 TCP 来源识别连接：Cloudflare / frpc 流量必须经本机回环进入才能使用公网密码，**完全不信任** `X-Forwarded-For`、`CF-Connecting-IP` 等可伪造头
- 局域网密码独立，Cloudflare 与 frpc 共用公网密码；改密即时撤销对应入口旧凭证

## 快速开始

### 1. 安装插件

```bash
# 在插件源码目录打包
npm run pack:local    # 生成 dsh-mobile-plugin-1.0.0.tgz

# 安装到 DSH Web 宿主
dsh plugin --profile web add ./dsh-mobile-plugin-1.0.0.tgz
dsh web
```

也可从 [GitHub Releases](https://github.com/jun3372/dsh-mobile-plugin/releases) 直接下载 `.tgz`。

配置持久化于 `$DSH_HOME/dsh-mobile-plugin/settings.json`（无 `DSH_HOME` 时为 `~/.dsh`）。旧版 `schema:1` 配置会在首次加载时自动迁移为 `schema:2`，已有密码、隧道 Token、开关状态均保留。

### 2. 安装 App

从 [Releases](https://github.com/jun3372/dsh-mobile-plugin/releases) 下载对应平台产物：

| 文件 | 平台 | 说明 |
| --- | --- | --- |
| `DSH-Mobile-1.0.0-android.apk` | Android | 直接安装 |
| `DSH-Mobile-1.0.0-ios-unsigned.ipa` | iOS | **未签名**，需用 Xcode / AltStore 等重签后侧载 |
| `DSH-Mobile-1.0.0-harmonyos-unsigned.hap` | HarmonyOS | **未签名**，需用 `hap-sign-tool` 签名后 `hdc install`（配置签名 Secrets 的 CI 会直接产出 `-signed.hap`） |
| `dsh-mobile-plugin-1.0.0.tgz` | 插件 | 安装到 DSH Web 宿主 |

### 3. 扫码连接

1. 在 DSH Web 左下角账号行末尾点击手机图标，打开配置弹窗
2. 在「局域网」「Cloudflare隧道」或「frpc隧道」页面找到二维码
3. App 首页扫码绑定即可；App 侧也可手动输入地址与密码

二维码格式：`<连接地址>?token=<URL 编码后的访问密码>`，例如 `http://192.168.1.50:39081?token=YourPassword`。**二维码包含完整访问密码，请按凭证保护，勿公开分享。**

## 配置说明

DSH Web 手机图标弹窗内五个菜单：

| 菜单 | 管理内容 |
| --- | --- |
| **基础配置** | 共享代理端口（默认 39081）、网关运行状态、局域网访问密码、Cloudflare/frpc 共用公网密码、DSH 实例标识（只读） |
| **局域网** | 独立启停、可用 IP 下拉选择、连接地址与二维码 |
| **Cloudflare隧道** | 独立启停、快速/命名隧道、域名、Tunnel Token、cloudflared 路径、GitHub 下载加速源、二维码 |
| **frpc隧道** | 独立启停、frps 地址/控制端口/公网映射端口、Token、映射名称、frpc 路径、下载加速源、二维码 |
| **运行日志** | 集中展示并复制局域网、Cloudflare、frpc 和网关的中文运行记录 |

- 更换端口会重启共享网关及已启用隧道；更换密码会撤销对应入口旧认证；只打开/保存页面不会轮换随机密码
- 首选端口被占用时网关自动顺延到下一个可用端口（最多 +20），配置中的首选端口保持不变，二维码与连接地址使用实际生效端口
- 每条隧道可单独选择下载加速源（官方 GitHub / ghfast.top / ghproxy.net / 自定义 HTTPS 地址），仅自动下载客户端时生效
- 字段全貌见 [`docs/CONFIGURATION_V13.md`](docs/CONFIGURATION_V13.md)；frps 服务端部署见 [`docs/FRPC_USAGE.md`](docs/FRPC_USAGE.md)

## 构建与 CI

GitHub Actions 工作流 [`.github/workflows/build.yml`](.github/workflows/build.yml)：

| Job | Runner | 产物 | 触发 |
| --- | --- | --- | --- |
| `plugin` | ubuntu | `dsh-mobile-plugin-*.tgz` | PR / push / tag |
| `android` | ubuntu（官方 Flutter 3.41.9） | `DSH-Mobile-*-android.apk` | PR / push / tag |
| `ios` | macos（官方 Flutter 3.41.9） | `DSH-Mobile-*-ios-unsigned.ipa` | PR / push / tag |
| `harmonyos` | ubuntu（flutter-ohos 3.41.9+ohos-1.0.2 + DevEco CLI 26.0.0.821） | `DSH-Mobile-*-harmonyos-*.hap` | PR / push / tag |
| `release` | ubuntu | 汇总上述产物发布 GitHub Release | 仅 `v*` tag |

**HarmonyOS 可选签名 Secrets**（全部配置后 CI 直接产出已签名 HAP）：

| Secret | 内容 |
| --- | --- |
| `OHOS_KEYSTORE_BASE64` | `.p12` 密钥库（base64） |
| `OHOS_CERT_BASE64` | `.cer` 应用证书（base64） |
| `OHOS_PROFILE_BASE64` | `.p7b` Profile 文件（base64） |
| `OHOS_KEY_ALIAS` | 密钥别名 |
| `OHOS_KEY_PASSWORD` / `OHOS_STORE_PASSWORD` | 密钥密码 / 密钥库密码（**明文**） |

**本地构建**：

```bash
# 插件（Node >= 22）
npm run check          # 逐文件语法检查
npm test               # node:test 单测
npm run pack:local     # 打 tgz

# App（Flutter，在 app/ 目录下）
flutter pub get
flutter build apk --release                    # Android
flutter build ios --release --no-codesign      # iOS（未签名）
flutter build hap --release                    # 鸿蒙（需 flutter-ohos SDK + DevEco CLI）

# App 提交前
dart fix --apply && dart format .
flutter test
```

## 安全边界

- `settings.json` 权限为 `0600`（POSIX）。因支持密码回显，文件中保存**可恢复的密码原文**（同时保留 scrypt hash 认证）；Cloudflare Token 与 Ed25519 私钥也在本地文件中，请确保操作系统账号与备份安全，切勿纳入版本控制
- 局域网网关为普通 HTTP，**不能防御局域网嗅探**，仅用于可信网络；公网务必确认 HTTPS/WSS 与隧道访问策略
- 禁止在路由器上将 39081 端口做公网映射，否则外部可绕过 Cloudflare 隧道直连 LAN 认证入口
- 移动代理网关不转发 `/dsh-mobile/admin/*`，并在代理前去除移动认证令牌；Web 管理 API 仅限环回来源
- 登录令牌随对应网络密码变更/网络关闭而撤销；访问密码不会被转发到 DSH Host 的任何接口

## 协议

- 扫码二维码：`<url>?token=<password>`；旧版 JSON payload（`{"protocol":"dsh-mobile/1","instanceId":...,"publicKey":...,"mode":"lan|public","url":...}`）仍可识别
- `GET /_dsh_mobile/v1/info`：返回签名元信息
- `POST /_dsh_mobile/v1/login`：`{"password":"..."}` → `{token, expiresIn, instanceId}`
- 后续请求携带 `Authorization: Bearer <token>`，由网关代理原生 DSH HTTP / WebSocket

## 文档索引

| 文档 | 内容 |
| --- | --- |
| [`docs/COMPATIBILITY.md`](docs/COMPATIBILITY.md) | DSH 宿主兼容性记录 |
| [`docs/CONFIGURATION_V13.md`](docs/CONFIGURATION_V13.md) | 设置菜单与字段清单 |
| [`docs/FRPC_USAGE.md`](docs/FRPC_USAGE.md) | frpc 隧道配置指南 |
| [`docs/DIFFERENTIAL_PARITY_V17.md`](docs/DIFFERENTIAL_PARITY_V17.md) | 原生 Host / 插件网关差分审计 |
| [`docs/INTEGRATION_AUDIT_V14.md`](docs/INTEGRATION_AUDIT_V14.md) / [`V15`](docs/INTEGRATION_AUDIT_V15.md) | 集成验收审计记录 |

## 开发

```
lib/            插件核心（index/service/gateway/tunnel/cloudflared/frpc/security/settings/qr/client 等）
app/            Flutter 客户端（lib/features/{servers,tasks,sessions}，ohos/ 为鸿蒙工程）
test/           node:test 单测 + Playwright 浏览器冒烟（ui-browser-smoke.py）
scripts/        审计与差分冒烟脚本
docs/           版本级规范与审计文档
```

```bash
# 插件
npm run check && npm test
python3 test/ui-browser-smoke.py        # 需本地 Chromium + Playwright
bash ./scripts/run-live-dsh-smoke.sh    # 真实 DSH 隔离联调

# App（在 app/ 下）
dart fix --apply && dart format . && flutter test
flutter emulators --launch <AVD> && flutter run   # Android 模拟器实测
```

插件调试无热载：改动后需重启 `dsh web` 验证。默认上游为 `http://127.0.0.1:3080`，可用 `DSH_MOBILE_UPSTREAM` 覆盖。

## 许可

MIT。参考资料：[dsh-pocket](https://github.com/shaobeichen/dsh-pocket)（GPL-2.0，未复用代码）、[Cloudflare cloudflared](https://github.com/cloudflare/cloudflared/releases)、[CPF-Flutter/flutter_flutter](https://atomgit.com/CPF-Flutter/flutter_flutter)（Flutter 鸿蒙适配）、自带的二维码生成器许可见 [`docs/third-party/`](docs/third-party/)。
