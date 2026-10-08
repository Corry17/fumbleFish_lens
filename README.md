# 镜内 MirrorLens

> macOS 摸鱼神器 —— 把任意窗口装进一面"镜子"，随时缩放、调速透明度、一键对齐，还能直接在镜内操作程序。

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License](https://img.shields.io/badge/license-MIT-green)

---

## 这是什么

「镜内」是一个 macOS 菜单栏常驻的悬浮小工具。启动后屏幕上出现一个小方框（镜子），你可以：

- 把**任意窗口的内容"拖入"镜子**，实时显示该窗口画面（15 FPS 窗口级捕获）
- 用快捷键**等比缩放**镜子大小、调节内容**透明度**、**移动**位置
- 单击镜内画面进入**操作模式**：在镜内直接点击/滚动/敲键盘，事件透传到目标窗口——**相当于在镜内运行那个程序**

典型场景：上班时把视频/小说/终端窗口缩小装进镜子放在屏幕角落，老板来了按两下快捷键调低透明度；或者把 Terminal 拖进镜子，直接在镜内敲命令跑程序。

## 功能特性

| 功能 | 说明 |
| --- | --- |
| 拖入捕获 | 按住任意窗口标题栏拖到镜子上松手，即开始实时捕获（绿框高亮提示） |
| 实时画面 | ScreenCaptureKit 窗口级捕获，15 FPS，随目标窗口移动/更新 |
| 等比缩放 | `Option+↑/↓` 每次 ±10%；也可直接拖动镜子边缘/四角自由缩放 |
| 透明度 | `Option+←/→` 调节镜内内容透明度（10% ~ 100%），边框保持可见 |
| 移动 | `Cmd+方向键` 每次移动 20pt；也可直接拖拽镜子本体 |
| 操作模式 | **单击镜内画面**进入：点击/拖动/滚轮/键盘透传到目标窗口，实现"在镜内运行程序" |
| 退出操作 | 点击镜子标题栏 或 `Option+Esc` |
| 菜单栏管理 | 添加窗口（列表点选捕获）、窗口管理（删除/新建镜子）、权限状态、退出 |
| 非激活悬浮 | 镜子永不抢占焦点，点击镜内不打断当前应用（摸鱼关键） |

## 环境要求

- macOS 13.0+（ScreenCaptureKit 窗口捕获）
- Xcode Command Line Tools（Swift 5.9+），**无需完整 Xcode**
- 权限：
  - **屏幕录制**：必需（捕获窗口画面），首次启动会弹窗引导
  - **辅助功能**：拖入识别与操作模式事件注入需要，菜单栏可查看状态

## 快速开始

```bash
# 克隆
git clone https://github.com/Corry17/fumbleFish_lens.git
cd fumbleFish_lens

# 编译并直接运行（推荐，开发调试用）
swift build
.build/debug/MirrorLens
```

也可以打包成 `.app` 应用：

```bash
./build.sh        # 生成 MirrorLens.app（ad-hoc 签名）
open MirrorLens.app
```

> 首次运行请在系统设置中授权「屏幕录制」与「辅助功能」权限，授权后重启应用生效。

## 快捷键一览

| 快捷键 | 功能 |
| --- | --- |
| `Option + ↑ / ↓` | 内容等比放大 / 缩小（10% 步进） |
| `Option + ← / →` | 内容透明度降低 / 提高 |
| `Cmd + 方向键` | 移动镜子窗口（20pt 步进） |
| `Option + Esc` | 退出操作模式 |
| 单击镜内画面 | 进入操作模式（在镜内操作目标程序） |
| 点击镜子标题栏 | 退出操作模式 / 拖动镜子 |
| 拖动镜子边缘、四角 | 自由缩放镜子 |

## 使用说明

1. 启动后屏幕出现空镜子（默认 320×240），菜单栏出现镜面图标
2. **装内容**：把目标窗口拖到镜子上松手；或菜单栏 →「添加窗口」点选
3. **摸鱼看**：`Option+↑/↓` 缩放、`Option+←/→` 调透明度、`Cmd+方向键` 挪位置
4. **上手操作**：单击镜内画面 → 标题栏显示"操作中" → 在镜内点击/敲键盘（事件透传到目标窗口）
5. **收工**：`Option+Esc` 或点标题栏退出操作模式；菜单栏可删除镜子

## 技术方案

macOS 系统层面不允许把其他 app 的窗口真正嵌入另一窗口（无公开 API），「镜内」采用**画面镜像 + 事件透传**实现等效体验：

```
┌──────────────────────────────────────────────┐
│  AppKit 悬浮层（非激活 NSPanel，始终置顶）        │
│   ├─ 标题栏（窗口名 / 操作状态 / 关闭）           │
│   └─ 内容层（实时画面 / 占位 / 拖入高亮）         │
├──────────────────────────────────────────────┤
│  核心能力                                     │
│   ├─ ScreenCaptureKit  窗口级捕获 SCStream     │
│   ├─ CGWindowList      窗口识别 / 落点查询      │
│   ├─ CGEvent           事件注入（操作模式）      │
│   └─ Carbon HotKey     全局快捷键              │
└──────────────────────────────────────────────┘
```

| 模块 | 实现 |
| --- | --- |
| 悬浮窗 | `NSPanel`（`.nonactivatingPanel`，不抢焦点，`.floating` 置顶） |
| 窗口捕获 | `ScreenCaptureKit` + `SCContentFilter(desktopIndependentWindow:)` |
| 拖入识别 | 全局鼠标事件 + `CGWindowListCopyWindowInfo` 落点查询 |
| 操作模式 | 坐标等比映射（letterbox 修正）+ `CGEvent.post(tap: .cghidEventTap)` |
| 全局热键 | Carbon `RegisterEventHotKey` |
| 构建 | Swift Package Manager（无需完整 Xcode） |

## 目录结构

```
fumbleFish_lens/
├── Package.swift                     # SPM 工程定义
├── build.sh                          # 打包 .app 脚本
├── Support/
│   └── Info.plist                    # 应用配置（LSUIElement 菜单栏应用）
├── Sources/MirrorLens/
│   ├── main.swift                    # 应用入口
│   ├── AppDelegate.swift             # 菜单栏、拖入识别、权限、快捷键分发
│   ├── MirrorPanel.swift             # 非激活悬浮面板
│   ├── MirrorWindowController.swift  # 单个镜子（捕获/缩放/透明度/操作模式）
│   ├── MirrorView.swift              # 内容视图（标题栏/画面/缩放把手/交互分流）
│   ├── ScreenCaptureService.swift    # ScreenCaptureKit 捕获服务
│   ├── WindowListService.swift       # 系统窗口列表与落点查询
│   ├── EventForwarder.swift          # CGEvent 事件注入
│   └── HotKeyManager.swift           # Carbon 全局热键
└── 镜内-需求文档.md                    # 产品需求文档（PRD）
```

## 隐私说明

- 捕获画面仅在本机内存中渲染显示，**不上传、不记录、不落盘**
- 应用只读取窗口画面与窗口元信息（标题、位置），不访问窗口内容数据、不采集键盘输入内容（操作模式的按键仅透传给目标窗口）

## Roadmap

- [x] V1.0 MVP：拖入捕获、缩放、透明度、移动、菜单栏管理
- [x] 操作模式：在镜内运行/操作目标程序（画面镜像 + 事件透传）
- [ ] V1.1：`Option+1/2` 角落对齐、`Option+N` 多开镜子、窗口列表管理
- [ ] V1.2：设置面板（快捷键自定义、帧率、对齐位置）、边缘吸附、多显示器
- [ ] V2.0：截图/录制定格导出、内容滤镜、镜子皮肤

## License

MIT
