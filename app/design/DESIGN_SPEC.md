# DSH Mobile 设计规范（DESIGN SPEC）

> 本文件是 app UI 全部颜色、字号、间距、圆角、组件尺寸的**唯一事实来源**。
> 页面代码只允许引用 `lib/app/theme.dart` 中的 token（`context.dsh.*` / `DshSpace` / `DshRadius` / textTheme），
> 规范外硬编码值由 `tool/design_lint.dart` 检出（0 违规为交付门槛）。

## 0. 基准设备与标定

- 基准设备：**HUAWEI Mate 80 Pro**（官方参数：6.75" OLED，分辨率 **2832 × 1280**，**460 PPI**）。
- 参考截图（`app/images/微信图片_*.jpg`）为该机物理分辨率 1:1（1280 × 2832）。
- 460ppi 对应 Android 密度桶 **480dpi = 3.0x**；设计视口 ≈ **427 × 944 dp**。
- 换算：`dp = px / 3`，取值落到 4dp 网格。JPEG 采样误差 ±2/255。

## 1. 色板

### 1.1 浅色（实测自参考截图）

| Token | 值 | 实测 | 用途 |
|---|---|---|---|
| `background` | `#FFFFFF` | 13_68 (10,700) | 任务/列表页背景、Sheet/Dialog 底 |
| `canvas` | `#F6F6F6` | 17_68 (60,700) | 会话页/新建任务页画布 |
| `surface` | `#FFFFFF` | 14_68 (640,2450) | 输入卡、popover、浮层卡片 |
| `ink`（foreground） | `#141414` | chip `#141414` / 标题 `#131313` | 主文本、选中 chip、主按钮底 |
| `onInk` | `#FFFFFF` | — | 黑底上的文字/图标 |
| `chipGray` | `#F0F0F2` | 13_68 (400,420) | 未选中 chip、禁用底、画布上的次级面（代码块/工具卡/排队条/目标卡） |
| `midText` | `#616161` | 14_68 (1898–1949) / 17_68 (699–749) | 选择器取值、思考折叠行等次级正文 |
| `secondaryText` | `#9E9EA0` | `#9F9E9A`（中和 JPEG 暖偏） | 13sp 以下辅助文字、未选中 chip 文字、图标 |
| `tertiaryText` | `#C4C4C4` | `#C1C1BF` | 禁用/占位图标、chevron |
| `dotGray` | `#E3E3E3` | 13_68 (103,1177) / 17_68 (1150,500) | 状态点（待开始）、空白态图标、会话页用户气泡 |
| `divider` | `#EEEEF0` | 项目既有值固化 | 分隔线、细边框 |
| `accentBlue` | `#3478F6` | 项目既有值固化 | 链接、停止按钮 |
| `runningYellow` | `#FBAE14` | 13_68 (128,1020) | 运行中虚线圆 |
| `dangerRed` | `#E5484D` | 项目既有值固化 | 错误、解绑 |
| 阴影 | `rgba(0,0,0,0.06)`，blur 12–18, offset (0,2~6) | 截图返回钮/输入卡 | 圆钮、浮起卡 |

### 1.2 深色（映射规则，截图无深色样张）

| Token | 值 | 说明 |
|---|---|---|
| `background` / `canvas` | `#0C0C0D` | 近黑画布 |
| `surface` | `#17171A` | 浮起层 |
| `ink` | `#F4F4F6` | 主文本 |
| `onInk` | `#141414` | 白底黑字（主按钮反转） |
| `chipGray`（次级面） | `#222226` | 代码块/工具卡/排队条等 |
| `midText` | `#C9C9CE` | 选择器取值、思考折叠行 |
| `secondaryText` | `#A6A6AD` | 对比 ≥4.5:1 |
| `tertiaryText` | `#7C7C84` | |
| `dotGray` / 用户气泡 | `#3A3A3E` | 浅色气泡为 `#E3E3E3` |
| `divider` / 边框 | `#26262A` / `#2E2E33` | 深色用 1px 边框替代阴影 |
| `accentBlue` / `runningYellow` / `dangerRed` | 不变 | |
| 阴影 | 无（透明） | |
| 扫码相机页 | 恒黑白字，不随主题 | |

## 2. 字阶（sp，随系统缩放）

| Token | 值 | 用途 |
|---|---|---|
| display | 24 / w700 | 任务列表页头/新建任务 Hero 标题**局部覆写为 20**（ui-ux-pro-max 收敛，2026-10） |
| title | 18 / w700 | 会话标题、Sheet/Dialog 标题 |
| body | 16 / w400–w600 | 正文、聊天、行标题 |
| bodySmall | 15 / w400 | 输入框、次级正文 |
| auxiliary | 14 / w400–w500 | chip、辅助说明 |
| caption | 13 / w400–w500 | 分组行、说明 |
| footnote | 12 / w400–w500 | 元信息、Sheet 小标题 |
| badge | 11 / w500 | 徽标 |
| logoGlyph | 34 / w700 | 「D」Logo 字符（专用） |

Markdown 专用（会话页）：h1 22、h2 20、h3 18，正文 16/1.6，行内代码 13.5。

## 3. 间距 / 圆角 / 尺寸

- 间距（4dp 网格）：4 / 8 / 12 / 16 / 20 / 24 / 32；页面左右边距 **20**，任务列表行 **24**（实测图标左沿 27dp）。
- 圆角：8（缩略图）、10（leading 容器）、12（用户气泡/代码块/小卡）、14（输入框）、16（卡片）、20（Sheet/Dialog）、24（输入卡、popover）、28（扫码框）、999（胶囊）。
- 组件尺寸（实测固化）：

| 组件 | 值 | 实测 px |
|---|---|---|
| 任务行节奏（行高） | 56 | 168 |
| 分组行节奏（行高） | 48 | 140 |
| 筛选 chip 高 | 36（触控外包 44） | 106 |
| FAB 直径 | 64，图标 26 | 196 |
| 状态点 | 进行中 16 虚线圈 / 其余 7 实心点 | 51 / 21 |
| 圆形图标钮 | 44，图标 20 | ~122 |
| 主圆形按钮（发送） | 44 | — |
| popover 宽 / 圆角 | 224 / 24 | 679 / ~37 |
| popover 选项行高 / caption 行高 | 52 / 36 | 154–168 / — |
| Sheet 菜单行高 | 48 | — |
| 用户气泡 | 圆角 12 等角、padding 14×10、单行 ≈ 46 | 139 |
| 输入卡起始高 | ≥104 | 312 |
| 主按钮（CTA/绑定） | 高 52，胶囊 | — |
| 触控目标下限 | 44×44，相邻间距 ≥8 | — |

2026-10 大屏精致化（ui-ux-pro-max 收敛）新增 token（实现见 `lib/app/theme.dart`）：

| Token | 值 | 说明 |
|---|---|---|
| `DshIcon` | inline 14 / chip 16 / tool 18 / action 20 / nav 22 | 图标尺寸语义档位：行内装饰、chip 行、工具钮、圆钮与列表 leading、导航级 |
| `DshTouch.minTarget` | 44 | 触控目标下限（视觉尺寸可小于触控区） |
| `DshHeaderMetrics` | padding LTRB(20,8,12,8)；logo 28；logoFontSize 14；title 20；dropdownIcon 20 | 页面头部统一度量：首页/会话页/二级页头部边距一致（左 20 对齐页边距），首页 Logo 32→28、大标题 24→20（局部覆写）、下拉箭头 24→20 |
| `DshButton` | composer 34 / tool 28 / fab 64 / fabIcon 26 | 圆形按钮视觉尺寸（仅 token 化，值不变） |
| `DshChip` | height 36 / rowHeight 52 | 筛选 chip（含触控缓冲容器行） |
| 搜索页 AppBar | 默认 56（移除 toolbarHeight 64） | 全部 Material AppBar 统一默认高度 |

## 4. 结构规则（自截图）

1. 任务列表页：**白底平铺**列表，无卡片、无行分隔线。
2. 会话页 / 新建任务页：**`#F6F6F6` 画布 + 白色浮起卡**（输入条/输入卡带轻阴影）；画布上的次级面（代码块、工具卡、排队条、目标卡、行内气泡）一律用 `chipGray`，不得与画布同色。
3. 分组标题（工作区行）恒为 `secondaryText` 灰（实测 #9D9D9D），展开/折叠只改箭头方向；任务行左侧状态：进行中 = 16dp 黄色虚线圈，其余 = 7dp `dotGray` 实心点（**不使用勾号**）。
4. ⋯ 菜单：**右上 popover**（白底、宽 224、圆角 24、轻阴影、选项行高 52、caption 12 号缩进 16、**选中标记 ✓ 在标签左侧**、分组之间通栏 1px 分割线），不是底部弹层。
5. 长按操作、分组/筛选、工作区选择等无截图对应 → 沿用底部 Sheet（圆角 20 + 拖拽把手 + 行高 48），视觉对齐 popover 规格。
6. 动效：仅标准 Material 反馈 + 160–220ms 颜色/透明度过渡；`MediaQuery.disableAnimations` 生效；**禁止**扫描线、旋转状态点、光晕等截图外装饰动效。


## 5. Token 合规检查

```bash
cd app && dart run tool/design_lint.dart
```

检查项：`fontSize:` 字面量、`BorderRadius.circular` / `Radius.circular` 字面量、`Color(0x…)` 字面量（`theme.dart` 除外）、`DshColors.*` 静态引用（应使用 `context.dsh.*`）。退出码非 0 = 存在违规。
