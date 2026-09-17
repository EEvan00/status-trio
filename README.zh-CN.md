<p align="center">
  <img src="screenshots/status-style.png" width="288" alt="不同设置下呈现的四种 Status Trio 菜单栏图标样式">
</p>

# Status Trio

<p align="center">
  <img src="Support/AppIcon.svg" width="112" alt="Status Trio 应用图标">
</p>

<p align="center"><strong>三个系统状态，一个原生 macOS 菜单栏图标。</strong></p>

<p align="center">
  <a href="README.md">English</a>
</p>

<p align="center">
  <img src="screenshots/normal.png" width="494" alt="Status Trio 菜单栏图标，Wi-Fi、电池和音量一目了然">
</p>

<p align="center">
  <img src="screenshots/popup.png" width="360" alt="Status Trio 状态弹层，展示 macOS 菜单栏中的电池、Wi-Fi 和音量">
</p>

Status Trio 是一个原生 macOS 菜单栏（menubar）应用，将 Wi-Fi、电池和音量整合进一个紧凑、可配置的菜单栏图标。灵感源自 iPhone Duo 将 Wi-Fi、Battery 和 Cellular Data 合并展示的 status bar icon，并在 Mac 上以音量替代 Cellular Data。

> Status Trio 是独立项目，与 Apple 无隶属关系。

## 主要特性

- **三合一状态图标**：电池、Wi-Fi 和音量共用一个菜单栏项目。
- **可配置渲染尺寸**：图标大小为 16–36 pt，默认 28 pt。
- **可选连接图标**：可有线连接、个人热点、临时连接或互联网共享改用普通 Wi‑Fi 信号图标。
- **完整电池状态**：电量百分比、充电闪电、充满预计时间、低电量模式和电池设置快捷入口。
- **可选 MagSafe 指示灯控制**：进入电池详情后，可让接头指示灯跟随系统，或保持熄灭。只有设置变化、Mac 唤醒或电源状态切换时才会按需运行 helper，不进行常驻轮询。
- **Wi-Fi 状态识别**：信号强度、当前网络名称和常见连接状态。
- **音量一目了然**：显示输出音量和静音状态，并可从弹层快速控制。
- **原生 macOS 交互**：左键打开状态弹层，右键显示标准菜单。
- **高效状态更新**：事件驱动监控，并提供低频轮询兜底。
- **十二种语言**：跟随系统语言或手动选择，修改后立即生效。
- **登录时启动**：可选开机登录启动，并在 macOS 需要批准时提供引导。

## 系统要求

- macOS 15 或更高版本
- Swift 6 工具链（Xcode 16 或更高版本）

## 从源码运行

```bash
git clone https://github.com/404404/status-trio.git
cd status-trio
bash scripts/build-app.sh release
```

Wi-Fi 名称和扫描需要定位权限。请使用上述方式启动完整应用；`swift run` 启动的是裸可执行文件，不包含应用的隐私权限配置。

## 构建本地应用

构建 ad-hoc 签名的应用包并启动：

```bash
bash scripts/build-app.sh release
```

应用包位于 `dist/StatusTrio.app`。如果只想构建，不退出或启动现有实例：

```bash
bash scripts/build-app.sh release no-open
```

ad-hoc 签名的应用包适合本地个人使用。如果应用包携带 quarantine 元数据后转移，可能会被 Gatekeeper 拦截。

## 安装 GitHub Release

从 [GitHub Releases](https://github.com/404404/status-trio/releases) 下载最新的 `StatusTrio-*.dmg`，打开后将 `Status Trio.app` 拖入 `/Applications`。

当前公开版本使用 ad-hoc 签名，尚未经过 Apple notarization。macOS 首次启动时可能提示：

> Apple 无法验证“Status Trio”是否包含可能危害 Mac 安全或泄漏隐私的恶意软件。

这是 Gatekeeper 因缺少 Developer ID 签名和 Apple 公证而显示的警告，并不代表应用一定包含恶意软件。只有在 DMG 来自官方 GitHub Releases 页面，并且发布的 SHA-256 校验值匹配时，才应绕过此警告。

将应用复制到 `/Applications` 后，移除 quarantine 属性并启动：

```bash
xattr -dr com.apple.quarantine "/Applications/Status Trio.app"
open "/Applications/Status Trio.app"
```

也可以先尝试打开一次应用，然后前往 **系统设置 → 隐私与安全性**，选择 **仍要打开**。

不要全局关闭 Gatekeeper。本 fork 当前只通过 GitHub Releases 发布；在配置本 fork 自己匹配的签名密钥对前，Sparkle 自动更新保持关闭。

## 使用方法

- **左键点击**菜单栏图标，打开状态弹层。
- **右键点击**图标，显示原生菜单，其中包含版本和退出操作。
- 在**设置**中调整图标大小、连接图标样式、电池显示、语言、更新检查和登录时启动。
- 如需显示当前 Wi-Fi 网络名称，请按提示启用定位权限；这是可选功能。

## 支持的语言

Status Trio 默认跟随 macOS 首选语言，支持 English、简体中文、繁体中文、日本語、한국어、Español、Français、Deutsch、Italiano、Português (Brasil)、Русский 和 العربية。

## 隐私

Status Trio 的常规状态信息通过 macOS 公开框架读取，不使用 App Sandbox，也不需要网络权限，且不包含遥测或分析功能。定位权限为可选项，仅在用户选择显示当前 Wi-Fi 网络名称时请求。

MagSafe 指示灯控制是一个可选的例外：Apple 没有为它提供公开 API，因此该功能会在受支持的硬件上使用 AppleSMC 私有 `ACLC` 键。首次启用会通过 macOS Service Management 注册用途受限的 launch daemon，并需要用户批准。App 通过仅允许同一 App 精确代码签名要求的 XPC 连接按需调用 Mach service；helper 只接受 `system` 或 `off` 两种命令，关灯时会在约一秒内有限重试回读确认（不重复写入），然后直接回复 SMC 结果，并在空闲 30 秒后退出；只有先把指示灯成功恢复为跟随系统，才会注销 helper。

## 开发

运行完整测试：

```bash
swift test
```

通过测试辅助脚本运行指定的 XCTest：

```bash
bash scripts/test.sh BatteryMonitorTests
```

在主应用之外运行 worktree 构建：

```bash
bash scripts/build-worktree.sh release
```

该脚本会根据当前分支生成开发版 bundle identifier 和显示名称，也可以通过环境变量覆盖：

```bash
BUNDLE_ID=io.github.404404.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

单实例锁按 bundle identifier 隔离，因此不同标识的构建可以同时运行。

## 技术基线

- Swift 6
- SwiftUI + AppKit
- macOS 15+
- `LSUIElement` 菜单栏应用
- 使用 Sparkle 检查更新

## 文档

- [GitHub Actions 自动发布](docs/github-actions-release.md)
- [Status Trio 设计规格](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [菜单栏图标 SVG](status-menubar.svg)
- [数据驱动图标演示](status-menubar-demo.html)

## 许可证

Copyright 2026 lingyired。

本项目采用 Apache License 2.0 许可。详见 [LICENSE](LICENSE) 和 [NOTICE](NOTICE)。

## 作者

由 [lingyired](https://github.com/lingyired) 创建并维护。<br>
主页：[https://statustrio.lingai.net/](https://statustrio.lingai.net/)
