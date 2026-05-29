# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 常用命令

- 调试构建：`swift build`
- 调试运行：`swift run AudioSettings`（直接以裸可执行文件方式启动，无 App 包/图标/Info.plist）
- 生成可分发的 macOS App 包：`./Scripts/build_app.sh`，产物在 `dist/AudioSettings.app`
- 启动打包后的 App：`open dist/AudioSettings.app`
- 清理构建产物：`rm -rf .build dist`

仓库当前没有自动化测试，也没有 lint/format 配置；`swift build` 即为唯一的正确性检查。

## 工具链

- SwiftPM 单 target（`Sources/AudioSettings`），通过 `Package.swift` 管理，swift-tools 5.9。
- 最低系统：macOS 13。无任何第三方依赖，全部使用系统框架（SwiftUI、AppKit、CoreAudio、AudioToolbox）。
- 入口是 `main.swift` 中的 `NSApplication` 手动启动 + `AppDelegate`，**不是** SwiftUI `@main App` 结构。新增窗口需走 `AppDelegate` 里的 `NSWindow + NSHostingController` 模式。

## 架构

应用是一层很薄的 SwiftUI 视图 + 一个 `@MainActor` ViewModel，承接两条互相独立的副作用通道：

1. **CoreAudio 设备通道** — `CoreAudioDeviceService`
   - 唯一封装 CoreAudio C API 的位置；其余代码不应再出现 `AudioObjectGetPropertyData` 等调用。
   - 通过 `kAudioDevicePropertyStreams` 在 input/output scope 上判断设备能力（同一个物理设备可能同时具备输入与输出）。
   - **设置默认输出设备时必须同时写入 `kAudioHardwarePropertyDefaultOutputDevice` 和 `kAudioHardwarePropertyDefaultSystemOutputDevice`**（见 `setDefaultOutputDevice`）——只设置其一会导致系统提示音与应用音频走到不同设备。
   - 设备的稳定标识是 UID（字符串），不是 `AudioDeviceID`（重启后会变）。配置文件、UI 选择都用 UID。

2. **持久化通道** — `ConfigStore` + `ConfigPathPreferences`
   - `ConfigStore` 只负责对一个 `configURL` 做 JSON 读写，ISO8601 日期，原子写入。
   - `ConfigPathPreferences` 在 `UserDefaults` 里保存"自定义配置路径"（仅存路径字符串），并维护一条约束：路径必须以 `.json` 结尾，防止误覆盖其他文件。默认路径为 `~/Library/Application Support/AudioSettings/devices.json`。
   - 自定义路径变更后通过 `Notification.Name.configPathDidChange` 广播；`AudioSettingsViewModel` 监听并重建 `ConfigStore`。设置窗与主窗之间没有直接耦合，全靠这条通知。

`AudioSettingsViewModel`（`@MainActor`、`ObservableObject`）是两条通道的汇合点，把 service 抛出的错误转成 `statusMessage`。视图层（`ContentView`、`SettingsView`）只读 ViewModel 状态、调用其方法，不直接接触 service 或 store。

### 窗口与菜单

- `AppDelegate` 手工持有 `mainWindow` 和 `settingsWindowController`，并自己装配主菜单（应用菜单只包含 About / 设置 / 退出）。不要把窗口逻辑迁到 SwiftUI `Scene`，会和 `setActivationPolicy(.regular)` + 手动 `NSApplication.shared.run()` 的启动方式冲突。
- 设置窗口固定 560×220、不可缩放；主窗口默认 720×520、最小 640×420。

## 打包脚本要点

`Scripts/build_app.sh` 在 `dist/` 下手工组装 `.app` 包：跑 `swift build -c release` → 复制可执行文件与 `.icns` → 写入 `Info.plist`（含 `LSMinimumSystemVersion 13.0`、`CFBundleShortVersionString` 与版本号）→ 用 `codesign --force --sign -` 做 ad-hoc 签名。修改 App 元数据（版本、Bundle ID、最低系统）请直接改脚本里的变量与 heredoc，不要新建 plist 文件。

ad-hoc 签名只适合本机/可信环境运行；若要分发需自行接入 Developer ID 签名与 notarization。

## OpenSpec 工作流

仓库使用 [openspec](./openspec) 进行 spec-driven 变更管理。新的功能或修改通常先以 change proposal 形式进入 `openspec/changes/`，实现完成后归档到 `openspec/changes/archive/` 并落到 `openspec/specs/`。如果用户提到 propose/apply/archive 等动作，优先使用对应的 `openspec-*` 或 `opsx:*` skill。

## 隐私边界（不要破坏）

应用刻意保持的边界，新增功能时请保留：

- 不访问网络；只通过 CoreAudio 读写设备元数据与默认设备。
- 配置文件只写本机 JSON；`UserDefaults` 只保存自定义路径字符串。
- 设备 UID 可能包含厂商/型号/序列信息，不要把 `devices.json`（已在 `.gitignore`）提交进仓库。

### 受控例外：输入测试的实时电平

`AudioTestService` 的输入测试会捕获所选输入设备的音频流。这是对"不读取麦克风音频内容"的**唯一、显式例外**，约束如下，新增功能时不得放宽：

- 采集到的样本**仅用于本机内存中的电平计算**，用完即弃；**不落盘、不通过网络传输、不回放**。
- 需要麦克风权限（TCC）：通过 `AVCaptureDevice` 请求；打包脚本的 `Info.plist` 含 `NSMicrophoneUsageDescription`。
- 仅在用户主动点击"开始测试"时采集；停止测试即释放采集会话。纯输出测试不触发麦克风授权。
