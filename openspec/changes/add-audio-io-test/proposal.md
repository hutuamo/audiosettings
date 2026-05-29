## Why

当前应用只能查看/切换默认输入输出设备并保存配置，但用户无法在切换设备后**当场确认设备是否真的能用**——输出有没有声、输入有没有拾到音。每次都要切到其他 App（如系统设置或播放器）去验证，体验割裂。在本应用内直接提供输入/输出测试，能让"选设备 → 验证设备"形成闭环。

## What Changes

- 输出测试：对设备列表中**选中的任意输出设备**循环播放一段 macOS 系统提示音（默认 Ping）作为测试音，每遍之间静音间隔约 2 秒，循环直到用户手动停止；过程中**不改变系统默认输出设备**。
- 输入测试：对**选中的输入设备**显示**实时电平表**（捕获该设备音频流计算电平），用户对着麦克风说话即可看到电平跳动；可手动开始/停止。
- 视图层在现有输入/输出 `DevicePanel` 中各增加一个测试入口（按钮 + 电平/播放状态展示）。
- **BREAKING（隐私边界）**：输入电平表需要捕获麦克风音频流，这突破了项目原有"不读取麦克风音频内容"的隐私边界。配套需要：① 申请麦克风权限（TCC）；② 打包脚本写入 `NSMicrophoneUsageDescription`；③ 修订 `CLAUDE.md` 的"隐私边界"条款，把"实时电平测量（仅本机、不落盘、不上传）"列为显式例外。

## Capabilities

### New Capabilities
- `audio-io-test`: 描述应用内对选中输出设备的测试音播放、对选中输入设备的实时电平测试，以及输入测试涉及的麦克风权限与隐私约束（仅本机内存计算、不落盘、不上传）。

### Modified Capabilities
<!-- window-lifecycle 与本变更无关；隐私边界写在 CLAUDE.md 而非 spec，故不在此列出 spec 级修改 -->

## Impact

- 代码：
  - 新增音频测试服务（输出播放 + 输入电平），封装 AudioToolbox/AVFoundation 调用，与现有 `CoreAudioDeviceService` 平级，互不污染。
  - `AudioSettingsViewModel` 新增测试相关状态（是否正在播放/采集、当前电平）与开始/停止方法。
  - `ContentView` 的 `DevicePanel` 增加测试入口控件。
- 权限与打包：`Scripts/build_app.sh` 的 `Info.plist` heredoc 增加 `NSMicrophoneUsageDescription`；首次输入测试会触发系统麦克风授权弹窗。
- 文档：修订 `CLAUDE.md` 隐私边界条款，记录"实时电平"这一受控例外。
- 不涉及配置存储（`ConfigStore`/`ConfigPathPreferences`）与窗口生命周期；无新增第三方依赖（仅系统框架）。
