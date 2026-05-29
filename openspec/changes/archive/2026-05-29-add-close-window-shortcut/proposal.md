## Why

当前应用没有 File 菜单，按 Cmd+W 没有任何反应；同时 `applicationShouldTerminateAfterLastWindowClosed` 返回 `true`，关闭最后一个窗口会直接退出进程。这两点合在一起导致：① 不符合 macOS 用户对 Cmd+W 的直觉；② `AppDelegate` 中已有的 `applicationShouldHandleReopen`（"无可见窗口时点 dock 重开主窗"）永远跑不到，是一段死代码。

## What Changes

- 新增 File 菜单，包含"关闭窗口"项，绑定 Cmd+W，使用 `NSWindow.performClose(_:)` 走系统响应链，自动作用于当前 key window（主窗与设置窗都受益）。
- 修改 `applicationShouldTerminateAfterLastWindowClosed` 返回 `false`，使关闭全部窗口后进程仍存活，仍占用 dock 图标。
- 关闭全部窗口后，用户可通过点击 dock 图标触发已有的 `applicationShouldHandleReopen`，重新显示主窗；也可通过应用菜单 Cmd+Q 真正退出。

## Capabilities

### New Capabilities
- `window-lifecycle`: 描述应用窗口的关闭/重开行为、进程存活策略，以及关闭窗口相关的键盘快捷键约束。

### Modified Capabilities
<!-- 仓库目前没有已存在的 spec，无需在此列出修改 -->

## Impact

- 代码：`Sources/AudioSettings/AppDelegate.swift` 的菜单装配（`configureMainMenu`）与 `applicationShouldTerminateAfterLastWindowClosed`。
- 行为：用户关闭最后一个窗口不再触发进程退出，需依赖 Cmd+Q 或菜单"退出 AudioSettings"主动结束进程。
- 不涉及 CoreAudio、配置存储或视图层；无新增依赖。
