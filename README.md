<p align="center">
  <img src="Assets/AppIcon-1024.png" width="128" height="128" alt="Pastecap Logo">
</p>

<h1 align="center">Pastecap</h1>

<p align="center">
  <strong>轻巧纯粹的 macOS 原生剪贴板历史与强大区域截图工具</strong><br>
  原生 Swift & SwiftUI 构建 · 极速响应 · 数据本地保存 · 深浅色无缝自适应
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14.0%2B-blue?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange?logo=swift" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/License-MIT-green" alt="License">
</p>

---

## 📸 应用预览与主要截图

<p align="center">
  <img src="Assets/AppIcon-1024.png" width="560" alt="Pastecap 主界面预览">
</p>

---

## ✨ 核心功能亮点

### 📋 1. 现代优雅的剪贴板管理 (Clipboard History)
- **卡片式精致排版**：自适应深浅色模式（Dark / Light Mode），搭配细腻磨砂玻璃背景与微光悬停质感。
- **智能内容识别**：
  - 🔗 **链接识别**：自动标记并以等宽代码字体高亮。
  - 🎨 **HEX 颜色**：自动解析 `#HEX` 颜色值，并内嵌实时颜色圆点预览。
  - 📝 **多行文本与代码**：智能显示行数与字符数角标，舒适自然换行排版。
  - 🖼️ **图片与截图**：高质量居中缩略图，智能标注图片格式与文件大小。
- **分类筛选胶囊栏**：一键在 `全部`、`文本`、`图片` 之间无缝切换，并支持毫秒级混合关键词搜索。
- **全键盘高效操作**：打开即聚焦搜索框，直接打字筛选；<kbd>↑</kbd><kbd>↓</kbd> 在卡片间移动高亮，<kbd>↵ Enter</kbd> 复制选中项并收起窗口，<kbd>⌘ Cmd</kbd>+<kbd>1-9</kbd> 直取第 N 条复制，<kbd>⌦</kbd> 删除选中项，<kbd>⎋ Esc</kbd> 关闭窗口——全程双手不离键盘。
- **轻量零抖动复制**：点击整行即刻复制，卡片微光脉冲反馈后自动收起窗口并把焦点还给之前的应用，直接 <kbd>⌘ Cmd</kbd> + <kbd>V</kbd> 粘贴。

---

### ✂️ 2. 像素级微信风格区域截图与屏幕贴图 (Screen Capture & Pin)
- **微信式智能选区（鼠标移动按块高亮）**：截图启动后移动鼠标，自动识别并高亮光标下的区域——菜单栏、菜单栏下方的整块桌面、任意应用窗口或弹框（前台到后台精确命中）；单击即选中该区域，按住拖动则自由框选，悬停高亮时按 <kbd>↵ Enter</kbd> 亦可直接完成截图。
- **自由选区与八向手柄调整**：选区创建后支持拖拽内部整体移动、拖动 8 个控点精细缩放微调（对角智能切换双向箭头光标）。
- **放大镜与 RGB 取色器**：拖动选区时实时展示 4x 放大镜、选区尺寸与当前像素点的十六进制 HEX 颜色。
- **🎯 截图前实时取色**：进入截图尚未框选时，光标所到之处即显示 4x 放大镜与像素色值，按 <kbd>C</kbd> 立即复制 `#HEX` 到剪贴板，会话保持打开可连续取色。
- **📌 屏幕贴图 / 大头针置顶 (Pin to Screen)**：一键将截图无缝转化为桌面最上层置顶悬浮窗，任意位置可拖拽，双击或 <kbd>Esc</kbd> 快速关闭，支持右键复制或保存。
- **丰富标注工具箱**：
  - 🔲 矩形 (<kbd>R</kbd>) / ⭕ 椭圆 (<kbd>O</kbd>) / ↗️ 箭头 (<kbd>A</kbd>) / ✏️ 自由画笔 (<kbd>P</kbd>) / 🏁 像素马赛克 (<kbd>M</kbd>) / 🔤 纯净文字标注 (<kbd>T</kbd>)。
- **沉浸式文本输入**：无多余边框干扰，支持小号/中号/大号字阶切换，光标颜色与当前选中色实时同步。
- **键盘流高效闭环**：<kbd>↵ Enter</kbd> 复制完成，<kbd>F</kbd> / <kbd>⌘P</kbd> 钉在屏幕上，<kbd>⌘Z</kbd> 撤销上一笔，<kbd>⌘S</kbd> 保存到文件，<kbd>⎋ Esc</kbd> 随时取消退出。

---

### 🔒 3. 隐私保护与本地安全
- **零网络上传**：所有剪贴板历史与图片均保存在本地 `~/Library/Application Support/Pastecap`。
- **机密数据保护**：1Password、Bitwarden、KeePass 等密码管理器标记为 `Concealed` 或 `Transient` 的敏感复制内容**绝不记录**。

---

## 💻 安装要求

- **操作系统**：macOS 14.0（Sonoma）或更高版本。
- **处理器**：Apple Silicon（M 系列）选择 `Pastecap-arm64.dmg`；64 位 Intel 选择 `Pastecap-x86_64.dmg`。从 v0.2.4 开始提供两种架构的独立安装包。
- **屏幕录制权限**：剪贴板历史无需额外权限；区域截图首次使用时，需要在「系统设置 › 隐私与安全性 › 屏幕录制」中允许 Pastecap。
- **网络与账号**：不需要网络连接或账号，剪贴板历史和截图均保存在本机。

### 安装方式

打开 Release 中与你的处理器对应的 DMG，将 **Pastecap** 拖入 **Applications** 文件夹即可。当前安装包使用 ad-hoc 签名（未经过 Apple 公证）；首次打开若提示“无法验证开发者”，请按住 Control 点按应用并选择「打开」，或在「系统设置 › 隐私与安全性」中允许打开。

## ⌨️ 默认快捷键

| 功能 | 默认快捷键 | 说明 |
| :--- | :--- | :--- |
| **打开剪贴板** | <kbd>⇧ Shift</kbd> + <kbd>⌘ Cmd</kbd> + <kbd>V</kbd> | 呼出/隐藏剪贴板主窗口 |
| **列表导航** | <kbd>↑</kbd> <kbd>↓</kbd> | 在历史卡片间移动高亮 |
| **复制选中项** | <kbd>↵ Enter</kbd> | 复制高亮条目并收起窗口 |
| **直取第 N 条** | <kbd>⌘ Cmd</kbd> + <kbd>1-9</kbd> | 无需移动高亮，直接复制对应条目 |
| **删除选中项** | <kbd>⌦ Fn+Delete</kbd> | 删除当前高亮的历史记录 |
| **区域截图** | <kbd>⌃ Control</kbd> + <kbd>⌘ Cmd</kbd> + <kbd>C</kbd> | 立即进入全屏选区截图模式 |
| **完成并复制** | <kbd>↵ Enter</kbd> / <kbd>⌘ Cmd</kbd> + <kbd>C</kbd> | 截图完成后复制到剪贴板 |
| **复制像素色值** | <kbd>C</kbd> | 截图过程中把光标下像素的 `#HEX` 色值复制到剪贴板 |
| **钉在屏幕上 (贴图)** | <kbd>F</kbd> / <kbd>⌘ Cmd</kbd> + <kbd>P</kbd> | 截图区域转为最上层置顶悬浮窗 |
| **取消截图** | <kbd>⎋ Esc</kbd> | 退出截图或放弃当前文本输入 |

*(支持在「偏好设置 › 快捷键」中一键自定义修改)*

---

## 📦 编译与打包

日常开发请打开 **`Pastecap.xcodeproj`**，选择 **Pastecap → My Mac**，按 **⌘R**。这是标准 macOS App target，Xcode 直接完成编译、资源打包、签名及 LLDB 调试，无需 Scheme 打包脚本。

Debug 使用本机的 `Pastecap Local` 证书，开发包固定输出到 `.build/xcode-dev/Pastecap.app`，沿用 `com.wwm.Pastecap` 标识符。开发 entitlements 允许断点调试，Release 禁止调试器附加。首次在新电脑开发时，可运行 `./scripts/sign-dev.sh` 创建本地证书；不要每次构建重新创建证书。

```sh
# 命令行构建并启动同一个开发应用
./scripts/run-dev.sh

# 执行已有的自动化测试
./scripts/run-tests.sh

# 构建当前机器架构的 Release 安装包
./scripts/build-dmg.sh

# 分别构建 Apple Silicon / 64 位 Intel，或一次生成两份
./scripts/build-dmg.sh arm64
./scripts/build-dmg.sh x86_64
./scripts/build-dmg.sh all
# 输出：dist/Pastecap-arm64.dmg、dist/Pastecap-x86_64.dmg
# App 分别保存在 dist/arm64/ 和 dist/x86_64/，两份产物互不覆盖。

# 测试默认使用本机架构；Apple Silicon 上测试 Intel 版本需已安装 Rosetta 2
./scripts/run-tests.sh
./scripts/run-tests.sh x86_64
```

屏幕录制授权后，在 Xcode 停止并再次运行即可。文件选择窗口中可按 ⌘⇧G 输入项目的 `.build/xcode-dev` 完整路径。切换证书或另一份应用时，系统可能要求重新授权。

`Package.swift` 保留用于 SwiftPM 命令行兼容；直接打开它运行仍是裸可执行程序。需要应用打包与权限支持时，请使用 `Pastecap.xcodeproj`。项目配置使用相对路径，移动项目后无需修改 Scheme。

---

## v0.2.4 更新

- 新增 64 位 Intel（x86_64）独立 DMG，保留 Apple Silicon（arm64）独立 DMG，两者均要求 macOS 14 或更新版本。
- 图片缩略图改为后台降采样加载并缓存，减少首次打开时的主线程工作。
- 长文本预览限长，缓存显示信息；复制和保存仍保留全文。
- 历史记录改为后台串行保存，退出时等待写入完成；历史未变化时启动不再重复写盘。
- 减少重复焦点设置和日期格式化开销，剪贴板检查延后至弹窗展示调用之后。

完整说明见 [v0.2.4 发布说明](docs/releases/v0.2.4.md)。

## 🚀 GitHub Release 自动发布

向仓库推送一个 `v*` 格式的 tag，GitHub Actions 会自动编译 `Pastecap-arm64.dmg` 和 `Pastecap-x86_64.dmg` 并挂载发布到 [Releases](https://github.com/nogeo/Pastecap/releases)：

发布前更新 `Packaging/Info.plist` 的版本号，并添加与标签同名的 `docs/releases/<tag>.md`；自动发布会使用该文件作为 Release 说明。

```sh
git tag -a v0.2.4 -m "Release v0.2.4"
git push origin main v0.2.4
```

---

## 🛡️ 屏幕录制权限说明 (Screen Recording)

截图功能依赖 macOS 系统的**屏幕录制权限**（系统设置 › 隐私与安全性 › 屏幕录制）。首次启动时如遇权限提示，请勾选允许 Pastecap 访问屏幕录制权限。
