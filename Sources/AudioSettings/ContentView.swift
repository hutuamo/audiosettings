import SwiftUI

struct ContentView: View {
    @StateObject private var model = AudioSettingsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            HStack(alignment: .top, spacing: 16) {
                DevicePanel(
                    title: "输入设备",
                    currentDevice: model.currentInputDevice,
                    devices: model.inputDevices,
                    selectedDeviceUID: model.selectedInputDeviceUID,
                    onSelect: model.selectInputDevice,
                    test: .input(
                        isTesting: model.isInputTesting,
                        level: model.inputLevel,
                        start: model.startInputTest,
                        stop: model.stopInputTest
                    )
                )

                DevicePanel(
                    title: "输出设备",
                    currentDevice: model.currentOutputDevice,
                    devices: model.outputDevices,
                    selectedDeviceUID: model.selectedOutputDeviceUID,
                    onSelect: model.selectOutputDevice,
                    test: .output(
                        testingDeviceUID: model.outputTestingDeviceUID,
                        start: model.startOutputTest,
                        stop: model.stopOutputTest
                    )
                )
            }

            HStack(spacing: 10) {
                Button("刷新设备") {
                    model.refresh()
                }

                Spacer()

                Button("保存当前配置") {
                    model.saveCurrentConfiguration()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.hasUnsavedConfigurationChanges)

                Button("从配置恢复") {
                    model.applySavedConfiguration()
                }
                .disabled(model.savedConfiguration == nil)
            }
        }
        .padding(24)
        .onAppear {
            model.refresh()
            model.loadSavedConfiguration()
        }
        .onDisappear {
            model.stopAllTests()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("音频设置")
                .font(.largeTitle.bold())

            Text("查看当前系统默认输入与输出设备，保存为配置，并在需要时写回系统。")
                .foregroundStyle(.secondary)
        }
    }
}

private enum DeviceTestConfig {
    case input(isTesting: Bool, level: Float, start: (AudioDevice) -> Void, stop: () -> Void)
    case output(testingDeviceUID: String?, start: (AudioDevice) -> Void, stop: () -> Void)
}

private struct DevicePanel: View {
    let title: String
    let currentDevice: AudioDevice?
    let devices: [AudioDevice]
    let selectedDeviceUID: String?
    let onSelect: (String) -> Void
    let test: DeviceTestConfig

    private var selectedDevice: AudioDevice? {
        devices.first { $0.uid == selectedDeviceUID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("当前默认")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(currentDevice?.name ?? "未检测到")
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
            }

            Divider()

            Text("可用设备")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(devices) { device in
                Button {
                    onSelect(device.uid)
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(device.name)
                                    .foregroundStyle(.primary)

                                if device.uid == currentDevice?.uid {
                                    Text("当前")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Text(device.uid)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if device.uid == selectedDeviceUID {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, 3)
            }
            .listStyle(.inset)

            Divider()

            testControl
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var testControl: some View {
        switch test {
        case .output(let testingDeviceUID, let start, let stop):
            let isTesting = testingDeviceUID != nil
            HStack {
                Button(isTesting ? "停止测试音" : "播放测试音") {
                    if isTesting {
                        stop()
                    } else if let selectedDevice {
                        start(selectedDevice)
                    }
                }
                .disabled(selectedDevice == nil)

                if isTesting {
                    Spacer()
                    Text("播放中…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

        case .input(let isTesting, let level, let start, let stop):
            VStack(alignment: .leading, spacing: 8) {
                Button(isTesting ? "停止测试" : "开始测试") {
                    if isTesting {
                        stop()
                    } else if let selectedDevice {
                        start(selectedDevice)
                    }
                }
                .disabled(selectedDevice == nil)

                if isTesting {
                    SegmentedLevelMeter(level: level)
                }
            }
        }
    }
}

/// 仿 macOS 系统设置「声音 › 输入」的分段电平表。线性峰值经 dBFS 映射后点亮对应段数。
private struct SegmentedLevelMeter: View {
    let level: Float
    private let segmentCount = 16
    /// 电平表本底（dBFS）。低于此视为静音、不点亮；越接近 0 越不灵敏，越负越灵敏。
    private let floorDB: Float = -55

    private var litCount: Int {
        guard level > 0 else { return 0 }
        let db = 20 * log10(level)  // 0 → 0dB，越小越负
        let normalized = max(0, min(1, (db - floorDB) / -floorDB))  // floorDB…0dB 映射到 0…1
        return Int(normalized * Float(segmentCount))
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segmentCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(index < litCount ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(height: 14)
            }
        }
    }
}
