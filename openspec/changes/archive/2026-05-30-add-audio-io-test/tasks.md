## 1. 音频测试服务（输出）

- [x] 1.1 新增 `Sources/AudioSettings/AudioTestService.swift`，定义服务骨架与错误类型（`AudioTestError`，含设备不可用、AudioUnit 启动失败、麦克风权限被拒）。
- [x] 1.2 实现输出测试：以 `kAudioUnitSubType_HALOutput` 创建 output unit，通过 `kAudioOutputUnitProperty_CurrentDevice` 绑定传入 `AudioDevice` 的 `.id`，render callback 喂入 `ExtAudioFile` 解码的系统声音（默认 Ping）PCM；提供 `startOutputTest(on:)` / `stopOutputTest()`。
- [x] 1.3 输出测试循环播放（每遍间隔约 2 秒），直到 `stopOutputTest()`；开始新输出测试前先停旧的（单输出状态机）。

## 2. 音频测试服务（输入电平 + 权限）

- [x] 2.1 实现麦克风权限：用 `AVCaptureDevice.authorizationStatus(for: .audio)` 判定、`requestAccess(for: .audio)` 请求；被拒绝时抛 `AudioTestError`。
- [x] 2.2 实现输入电平采集：HAL output unit 开启 input scope 并绑定选中输入设备，input callback 计算 RMS/峰值电平，写入加锁保护的共享标量；提供 `startInputTest(on:)` / `stopInputTest()`，停止时释放 unit。
- [x] 2.3 提供线程安全的电平读取接口（供主线程定时器轮询）；确保 callback 内零分配、零 UI、零 Swift 引用计数风险。

## 3. ViewModel 接入

- [x] 3.1 在 `AudioSettingsViewModel` 持有 `AudioTestService`，新增 `@Published` 状态：`outputTestingDeviceUID: String?`、`isInputTesting: Bool`、`inputLevel: Float`。
- [x] 3.2 新增方法 `startOutputTest(device:)` / `stopOutputTest()` / `startInputTest(device:)` / `stopInputTest()`，把服务错误转成 `statusMessage`（复用现有 `setError`）。
- [x] 3.3 输入测试运行期间用 ~30Hz 主线程定时器轮询服务电平并赋给 `inputLevel`；停止时停定时器并归零。
- [x] 3.4 在设备切换（`selectInputDevice`/`selectOutputDevice`）与 `refresh()` 重建列表时主动停止相关测试，避免悬挂的采集/播放。

## 4. 视图接入

- [x] 4.1 在 `DevicePanel` 增加测试入口：输出面板显示"测试/停止"按钮（针对选中设备），输入面板显示"开始/停止测试"按钮 + 实时电平条。
- [x] 4.2 电平条用 `inputLevel` 驱动（如 `ProgressView` 或自绘条），仅在 `isInputTesting` 时显示。
- [x] 4.3 按钮状态与 `outputTestingDeviceUID` / `isInputTesting` 联动（播放中显示"停止"，避免重复触发）。

## 5. 权限声明与打包

- [x] 5.1 在 `Scripts/build_app.sh` 的 Info.plist heredoc 增加 `NSMicrophoneUsageDescription`（中文用途说明：用于实时输入电平测试，不录音、不上传）。

## 6. 隐私边界文档修订

- [x] 6.1 修订 `CLAUDE.md` 的"隐私边界"条款：把"输入测试的实时电平测量（仅本机内存计算、不落盘、不上传）"列为显式受控例外，并记录需要麦克风权限。

## 7. 验证

- [x] 7.1 `swift build` 编译通过。
- [x] 7.2 `./Scripts/build_app.sh` 打包并 `open dist/AudioSettings.app`。
- [ ] 7.3 输出测试：选中非默认输出设备点测试，声音从该设备发出，系统默认输出未改变；循环播放（每遍间隔约 2 秒）持续到点停止；切换设备测试时前一个停止。
- [ ] 7.4 输入测试：首次点击触发麦克风授权弹窗；授权后对麦克风发声电平跳动；停止后菜单栏录音指示消失。
- [ ] 7.5 权限被拒绝场景：状态区给出可读提示且不崩溃；仅用输出测试时不触发麦克风授权。
- [ ] 7.6 选中设备拔出后触发测试：给出"设备不可用"提示而非静默失败。
