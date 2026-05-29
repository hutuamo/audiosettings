## 1. 进程存活

- [x] 1.1 将 `Sources/AudioSettings/AppDelegate.swift` 中 `applicationShouldTerminateAfterLastWindowClosed` 的返回值由 `true` 改为 `false`。

## 2. 菜单与快捷键

- [x] 2.1 在 `configureMainMenu()` 中追加一级菜单项 "文件"（`NSMenuItem` + `NSMenu`），插入位置位于应用菜单之后。
- [x] 2.2 在 "文件" 子菜单中添加 "关闭窗口" 项，`action: #selector(NSWindow.performClose(_:))`、`keyEquivalent: "w"`、`target: nil`（依赖响应链自动定位 key window）。

## 3. 手工验证

- [x] 3.1 执行 `swift build` 确保编译通过。
- [x] 3.2 通过 `./Scripts/build_app.sh` 打包，运行 `open dist/AudioSettings.app`。
- [x] 3.3 主窗 key 时按 Cmd+W：主窗关闭、dock 图标保留、进程未退出（用 Activity Monitor 或 `pgrep AudioSettings` 验证）。
- [x] 3.4 打开"设置..."后设置窗 key 时按 Cmd+W：设置窗关闭、主窗与进程不受影响。
- [x] 3.5 关闭全部窗口后点击 dock 图标：主窗重新出现并成为 key window。
- [x] 3.6 关闭全部窗口后按 Cmd+Q（或菜单"退出 AudioSettings"）：进程退出，dock 图标消失。
- [x] 3.7 没有 key window（例如所有窗口已关闭、应用尚未通过 dock 唤回）时，应用菜单栏中的"文件 → 关闭窗口"项处于 disabled 状态。
