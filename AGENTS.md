# AGENTS.md

本文件供 AI 编码助手与新协作者快速了解本项目的结构、命令与硬性约束。修改代码前请先读完本文。

## 项目概述

**DSH Mobile 手机连接插件**（`dsh-mobile-plugin`，当前 `1.0.1`）：为 DSH Web 宿主（`dsh web`，基于 `@deepseek-ai/cordis` 框架）提供手机远程访问网关，包括局域网直连、Cloudflare Tunnel、frpc 隧道、扫码配对、开机自动恢复。

- 纯 JavaScript（ESM），Node ≥ 22，**零 runtime 依赖**（`@deepseek-ai/cordis` 为可选 peerDependency）
- `app/` 为配套 Flutter 客户端（Android / iOS / HarmonyOS NEXT，Dart SDK ^3.11.5）
- 定位为**开发预览版**：禁止引入公网生产部署假设
- 发布方式为源码直发：`npm pack --ignore-scripts` 打 tgz，再用 `dsh plugin --profile web add <tgz>` 安装

## 目录结构

```
lib/            插件核心（全部逻辑在此）
  index.js        入口 + Cordis 服务注入（['webServer','connection']）
  service.js      服务编排
  gateway.js      HTTP/WS 代理网关
  tunnel.js       隧道管理
  cloudflared.js  Cloudflare Tunnel
  frpc.js / frpc-downloader.js / download-source.js  frpc 及其下载校验
  upstream-auth.js  宿主管理权限校验
  security.js     安全策略（Origin / 回环校验等）
  settings.js     配置持久化
  qr.js           配对二维码
  vendor/QRCode   自带二维码生成器（勿引入 npm qrcode）
  client.js       Web 客户端注入脚本
app/            Flutter 客户端（ohos/ 为鸿蒙工程）
test/           node:test 单测（*.test.js）+ Playwright 冒烟（ui-browser-smoke.py）
scripts/        审计与差分冒烟脚本
docs/           版本级规范文档（COMPATIBILITY、CONFIGURATION_V13、INTEGRATION_AUDIT_* 等）
```

## 常用命令

```bash
# dsh 插件（JS）
npm test                 # 运行全部 node:test 单测
npm run check            # 逐文件语法检查（node --check）
npm run pack:local       # npm pack --ignore-scripts 打 tgz
npm run compare:live     # 真机差分对比（scripts/compare-direct-proxy.mjs）
python3 test/ui-browser-smoke.py   # 浏览器 UI 冒烟

# app 客户端（Flutter，在 app/ 目录下执行）
flutter test             # Dart 单测
flutter run              # 部署到已连接的模拟器/真机
flutter emulators --launch <名称>   # 启动本地 Android 模拟器
```

插件调试无热载：改动后需重启 `dsh web` 验证。默认网关端口 **39081**。

## 代码风格约定

### dsh 插件（lib/，JavaScript）

- **注释与日志用中文**；安全类关键注释可用英文
- 命名：camelCase，文件名 kebab/snake-case；代码紧凑（现有代码多为单行多语句风格，新增代码保持一致即可，不必刻意改写存量代码）
- 错误处理 **fail-closed**：校验失败一律拒绝（如 `dsh_connection_auth_unavailable`）；JSON 错误响应统一 `{ error: '<错误码>' }`
- 日志：Cordis `ctx.logger('dsh-mobile')` + stderr 双通道；**禁止向 stdout 写日志**（会干扰宿主 RPC/ACP 流）
- 示例参见 `lib/index.js`

### app 客户端（app/，Flutter/Dart）

- 遵循 Dart 官方风格（以 `dart format` 输出为准），不手工调整格式
- 命名遵循 Flutter 惯例：类/枚举 PascalCase，其余 lowerCamelCase

## 约束（必须遵守）

### 通用

1. **日志脱敏**：任何日志不得输出密码、Token、配对密钥
2. **开发预览版定位**：禁止引入公网生产部署假设
3. 跨端改动（涉及插件协议 + app 调用）需两侧同步修改并保持接口一致

### dsh 插件（lib/，JavaScript）

1. **零 runtime 依赖**：不得新增 npm dependencies；所需能力优先用 Node 内置模块或 `lib/vendor/` 自带实现
2. **安全红线**：SHA-256 下载校验、回环地址与 Origin 校验不可绕过或放宽；**禁止信任 X-Forwarded-For 等转发头**判定客户端地址
3. **配置兼容**：配置持久化于 `$DSH_HOME/dsh-mobile-plugin/settings.json`（无 `DSH_HOME` 时为 `~/.dsh`），schema 需向后兼容，**不得迁移或丢弃用户已有配置**
4. **协议兼容**：涉及网关协议、扫码配对、持久化结构的改动，先阅读 `docs/COMPATIBILITY.md` 与相关版本审计文档，保持向后兼容；需要了解配置项全貌时参考 `docs/CONFIGURATION_V13.md`

### app 客户端（app/，Flutter/Dart）

1. **Dart 工具链强制**：每次改动后必须依次运行 `dart fix --apply` 和 `dart format .`，处理完提示后再交付
2. **模拟器实测**：改动须在本地 Android 模拟器中验证（`flutter emulators` 查看 AVD，`flutter emulators --launch <名称>` 启动，`flutter run` 部署验证）
3. **依赖管理**：新增 pub 依赖需在 `app/pubspec.yaml` 中明确版本约束，避免过度依赖
4. **鸿蒙工程**：`app/ohos/` 下文件多为 Flutter 工具链生成，非必要不手改；鸿蒙侧问题优先检查 Flutter SDK 与 toolchain 配置

## 变更流程

### dsh 插件（lib/）

1. 改动后运行 `npm run check` 和 `npm test`，全部通过
2. 涉及网关 / UI 行为的改动，另跑 `ui-browser-smoke.py` 或差分脚本验证
3. 打包验证：`npm run pack:local` 后用 `dsh plugin --profile web add <tgz>` 在真实宿主中冒烟

### app 客户端（app/）

1. 依次运行 `dart fix --apply` 和 `dart format .`，处理完提示
2. 运行 `flutter test`（如有测试）
3. 启动本地 Android 模拟器，`flutter run` 实测改动功能
