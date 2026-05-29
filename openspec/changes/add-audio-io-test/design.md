## Context

应用现有结构：薄 SwiftUI 视图 + `@MainActor` 的 `AudioSettingsViewModel`，副作用集中在 `CoreAudioDeviceService`（设备元数据/默认设备读写）和 `ConfigStore`（持久化）。本变更新增两条**实时音频 I/O**副作用：向选中输出设备播放测试音、从选中输入设备采集电平。两者都要求**绑定到具体设备而非系统默认**，且都会运行在实时音频回调线程上，需要把结果安全地回送到主线程的 ViewModel。

约束：macOS 13+，仅系统框架，无第三方依赖；输出测试不得改动系统默认输出；输入采集样本仅用于内存内电平计算，不落盘、不上传。

## Goals / Non-Goals

**Goals:**
- 对设备列表中**选中的任意**输出设备播放内置测试音，不改系统默认。
- 对**选中的**输入设备显示实时电平，验证拾音是否正常。
- 把实时音频复杂度封装在一个独立服务里，`CoreAudioDeviceService` 保持原样。
- 麦克风权限的请求/拒绝有清晰的用户可见反馈。

**Non-Goals:**
- 不做频谱、声道分离、回放录音、增益调节等高级音频功能。
- 不做输入测试的"回放监听"（把麦克风声音放到扬声器）——只看电平。
- 不持久化任何测试相关状态。
- 不改动配置存储与窗口生命周期逻辑。

## Decisions

### 决策 1：用 AUHAL（`kAudioUnitSubType_HALOutput`）做按设备路由，而非 AVAudioEngine
输入和输出都需要绑定到**指定 `AudioDeviceID`**。AUHAL output unit 通过 `kAudioOutputUnitProperty_CurrentDevice` 可显式设定目标设备，输出用 render callback 喂入预先解码好的 PCM（系统声音文件，见决策 6），输入开启 unit 的 input scope 后用 input callback 取样。两条通道用同一套机制，心智一致，且全部落在 CoreAudio/AudioToolbox 内。

> 注：input callback 内调用 `AudioUnitRender` 必须显式传 element `1`（input bus），不能用回调传入的 `inBusNumber`——后者可能为 0，会导致 render 失败、电平恒为 0。

- **备选：AVAudioEngine** — API 更友好，但在 macOS 上对"输入/输出绑定到非默认的具体设备"没有干净的公开路径，最终仍要下沉到 AudioUnit 层设 CurrentDevice，反而把两套抽象混在一起。故放弃。

### 决策 2：测试服务接收 `AudioDevice`，复用其 `.id`，不重复 UID→DeviceID 解析
`AudioDevice` 已带 `id`（`AudioDeviceID`）。ViewModel 在每次 `refresh()` 后持有最新设备列表，测试前会先 `refresh()`，故直接把选中的 `AudioDevice` 传给测试服务、用其 `.id` 设 CurrentDevice 即可，无需在新服务里再抄一遍 `CoreAudioDeviceService` 的 UID 查找逻辑。

- **风险**：`AudioDeviceID` 在重插设备后会变。缓解：测试入口触发时设备来自最近一次刷新；若设备已不可用，AudioUnit 启动会返回错误，按"设备不可用"路径提示。

### 决策 3：实时回调与主线程之间用"共享电平 + 定时采样"解耦
音频 input callback 跑在实时线程，**禁止**在其中做 UI / Swift 引用计数等不安全操作。回调里只把计算好的电平（一个 `Float`）写入一个用锁或原子保护的共享存储；ViewModel 侧用一个 ~30Hz 的主线程定时器读取该值并赋给 `@Published var inputLevel`，驱动 SwiftUI 刷新。停止测试时同时停掉定时器并把电平归零。

- **备选：在回调里 `DispatchQueue.main.async` 更新** — 高频派发有开销且违反实时线程纪律，放弃。

### 决策 4：单服务 `AudioTestService`，内部维护"至多一个输出测试 + 至多一个输入测试"的状态机
服务持有当前输出 AudioUnit 与输入 AudioUnit 引用。开始新输出测试前先停旧的；输入同理。输出测试有固定时长（如 ~1s 正弦音），到时在内部停止并通过回调/标志通知 ViewModel 复位按钮态。ViewModel 暴露：`outputTestingDeviceUID: String?`、`isInputTesting: Bool`、`inputLevel: Float`，以及 `startOutputTest/stopOutputTest/startInputTest/stopInputTest`。

### 决策 5：麦克风权限走 `AVCaptureDevice`，打包脚本补 `NSMicrophoneUsageDescription`
用 `AVCaptureDevice.authorizationStatus(for: .audio)` 判定、`requestAccess(for: .audio)` 请求。被拒绝时不启动采集，向 `statusMessage` 写可读提示。`Scripts/build_app.sh` 的 Info.plist heredoc 增加 `NSMicrophoneUsageDescription`（中文用途说明）。注意 `swift run` 裸可执行文件无 Info.plist，TCC 行为可能受限——以 `.app` 包为准验证输入测试。

### 决策 6：测试音用 macOS 系统声音文件，而非合成正弦音
测试音改为播放 `/System/Library/Sounds/<name>.aiff`（默认 `Ping`），比裸正弦音更悦耳、更贴近用户对"提示音"的预期。用 `ExtAudioFile` 一次性解码为单声道 Float32（按设备采样率重采样），全部读入内存后在 render callback 内按帧喂出、扇出到所有声道。回调内用 `position` 在 `[0, frameCount)` 播声音、`[frameCount, frameCount+gapFrames)` 输出静音、到末尾归零，实现**带 2 秒间隔的无限循环**；不自动停止，仅在用户点击停止时由 `stopOutputTest()` 释放 unit。

- **为何下混单声道再扇出**：`ExtAudioFile` 经 `AudioConverter` 可稳定完成 stereo→mono 下混与采样率转换，但到任意 N 声道的上混不可靠。下混单声道、再在回调里复制到每个输出声道，对 2 声道或多声道接口都鲁棒。
- **备选：`NSSound`** — 一行即可播系统声音，但只能播到系统默认输出，无法路由到选中的非默认设备，与既定需求冲突，放弃。

## Risks / Trade-offs

- **隐私边界被突破** → 这是经官家确认的取舍；通过"仅内存电平、不落盘、不上传"的硬约束 + 修订 `CLAUDE.md` 把该例外写明来控制范围。
- **实时音频线程安全** → 回调内零分配、零 UI、仅写共享标量；所有 UI 更新在主线程定时器里做。
- **裸可执行文件无麦克风权限弹窗** → 在 design/tasks 中标注：输入测试必须用 `./Scripts/build_app.sh` 打包后验证，`swift run` 仅验证编译与输出测试。
- **设备热插拔导致 DeviceID 失效** → 启动 AudioUnit 失败即按"设备不可用"提示，不静默吞错。
- **窗口关闭/切设备未停采集** → ViewModel 在设备切换、`refresh()` 重建列表、以及测试视图消失时主动调用 stop，避免麦克风占用指示长亮。
