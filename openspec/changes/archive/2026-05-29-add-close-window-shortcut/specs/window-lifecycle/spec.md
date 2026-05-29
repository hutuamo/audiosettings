## ADDED Requirements

### Requirement: 关闭窗口快捷键
应用 SHALL 提供菜单驱动的"关闭窗口"动作，绑定 Cmd+W 快捷键，使用系统响应链作用于当前 key window。该动作 MUST 同时适用于主窗与设置窗。

#### Scenario: 主窗为 key window 时按 Cmd+W
- **WHEN** 主窗处于前台并是 key window
- **AND** 用户按下 Cmd+W
- **THEN** 主窗被关闭
- **AND** 应用进程继续运行

#### Scenario: 设置窗为 key window 时按 Cmd+W
- **WHEN** 设置窗处于前台并是 key window
- **AND** 用户按下 Cmd+W
- **THEN** 设置窗被关闭
- **AND** 主窗（若存在）与应用进程继续运行

#### Scenario: 没有 key window 时按 Cmd+W
- **WHEN** 应用激活但当前没有 key window
- **AND** 用户按下 Cmd+W
- **THEN** "关闭窗口"菜单项处于禁用状态
- **AND** 没有任何窗口或进程被关闭

### Requirement: 关闭窗口后进程存活
应用 MUST 在所有窗口被关闭之后保持进程存活，dock 图标常驻可见。进程退出 SHALL 仅通过应用菜单"退出 AudioSettings"或 Cmd+Q 触发。

#### Scenario: 关闭最后一个窗口
- **WHEN** 用户关闭应用最后一个可见窗口（无论通过红叉、Cmd+W 还是其他方式）
- **THEN** 应用进程继续运行
- **AND** dock 中的 AudioSettings 图标依然可见

#### Scenario: 通过 Cmd+Q 退出
- **WHEN** 用户按下 Cmd+Q 或选择应用菜单"退出 AudioSettings"
- **THEN** 应用进程退出
- **AND** dock 图标消失

### Requirement: 从 dock 重新打开主窗
当应用进程存活但无可见窗口时，应用 SHALL 在用户点击 dock 图标后重新显示主窗。

#### Scenario: 点击 dock 图标恢复主窗
- **WHEN** 应用进程存活
- **AND** 当前没有任何可见窗口
- **AND** 用户点击 dock 中的 AudioSettings 图标
- **THEN** 主窗被重新显示并成为 key window

#### Scenario: 已有可见窗口时点击 dock 图标
- **WHEN** 应用进程存活
- **AND** 至少有一个可见窗口
- **AND** 用户点击 dock 中的 AudioSettings 图标
- **THEN** 应用被激活到前台
- **AND** 不会新建或重复打开主窗
