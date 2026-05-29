## Context

应用入口走的是 `main.swift` 中手工启动的 `NSApplication.shared.run()` + `AppDelegate` 模式（不是 SwiftUI `@main App`），所有窗口、菜单都在 `AppDelegate` 里以 `NSWindow + NSHostingController` 装配。

当前主菜单只有应用菜单（About / 设置 / 退出 Cmd+Q），没有 File/Window 菜单，因此 Cmd+W 既无菜单项也无快捷键绑定，按下毫无反应。

`applicationShouldTerminateAfterLastWindowClosed` 返回 `true`，关闭最后一个窗口即退出进程；与此同时 `applicationShouldHandleReopen` 又实现了"无可见窗口时点 dock 重开主窗"，这两段意图互斥，后者目前是死代码。

## Goals / Non-Goals

**Goals:**
- 按下 Cmd+W 关闭当前 key window，主窗与设置窗都遵守 macOS 惯例。
- 关闭全部窗口后进程仍存活，dock 图标常驻，用户点击 dock 图标可恢复主窗。
- 保留 Cmd+Q（"退出 AudioSettings"）作为唯一的进程退出入口。

**Non-Goals:**
- 不把应用改成 menu bar / accessory 形态（不动 `setActivationPolicy`）。
- 不新增 Window 菜单或多窗管理能力，不对设置窗的关闭行为做特殊处理。
- 不引入状态栏图标。
- 不改变 CoreAudio、配置存储、视图层任何逻辑。

## Decisions

### 决策 1：用系统 `performClose:` 走响应链，而非自己拦截快捷键

**选择**：新菜单项的 `action` 设为 `#selector(NSWindow.performClose(_:))`，`target` 留 `nil`。

**理由**：`performClose:` 会自动作用于当前 key window，并经过 `NSWindowDelegate.windowShouldClose(_:)`，行为与点击窗口左上角红叉完全一致。主窗与设置窗都已设置 `isReleasedWhenClosed = false`，关闭后窗口对象仍可复用（`showMainWindow` / `showSettingsWindow` 里都有 "已存在则复用" 的分支）。

**备选**：在 `AppDelegate` 加自定义 `@objc` 方法 `closeKeyWindow()`，自己取 `NSApp.keyWindow?.close()`。被否，因为绕过 `windowShouldClose` 钩子，未来若给窗口加未保存提示等需求会很别扭，且不是 mac 惯例。

### 决策 2：菜单结构——加 File 菜单，而非把"关闭窗口"塞进应用菜单

**选择**：在 `configureMainMenu()` 中追加一级菜单项 "File"，子菜单包含"关闭窗口" (Cmd+W)。

**理由**：mac 用户对 File > Close 的肌肉记忆极强；放在应用菜单里反而别扭。File 菜单当前只有这一项也没关系，未来可顺势放"导入/导出配置"等动作。菜单标题用本地化中文"文件"以与现有"设置..."/"退出 AudioSettings"风格一致。

**备选**：放进应用菜单。被否，违反 macOS HIG。

### 决策 3：进程存活——`applicationShouldTerminateAfterLastWindowClosed` 返回 `false`

**选择**：直接改返回值为 `false`。

**理由**：这是 AppKit 提供的标准钩子，返回 `false` 即可让进程在所有窗口关闭后继续运行。此举同时让 `applicationShouldHandleReopen` 从死代码变为有效路径——点 dock 图标会触发它，恢复主窗。无需任何额外状态管理。

**备选**：保留 `true`，改为在关闭最后一个窗口前拦截。被否，复杂且不符合 AppKit 设计意图。

### 决策 4：dock 点击行为复用现有 `applicationShouldHandleReopen`

`AppDelegate.swift:19-24` 已有的实现 `if !flag { showMainWindow() }` 正是本次想要的行为，不需要改动。决策 3 让它从死代码变为生效路径。

## Risks / Trade-offs

- [用户在关闭所有窗口后忘记还有进程存在] → dock 图标依然常驻可见，且菜单栏在应用激活时也仍是 AudioSettings 的，视觉上不会消失；用户随时可 Cmd+Q 退出。
- [设置窗关闭后再次打开是同一实例] → `settingsWindowController` 当前持久持有；`isReleasedWhenClosed = false` 已生效，行为与之前一致。无需变动。
- [Cmd+W 在没有 key window 时按下] → 系统会让菜单项自动 disabled（响应链找不到能响应 `performClose:` 的对象），符合预期，不需要额外处理。
- [将来要做"关闭主窗即真正退出"等差异化行为] → 本次刻意不做窗口区分；若以后有需求，可在主窗的 `NSWindowDelegate` 里实现，不影响本次设计。
