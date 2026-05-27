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
                    onSelect: model.selectInputDevice
                )

                DevicePanel(
                    title: "输出设备",
                    currentDevice: model.currentOutputDevice,
                    devices: model.outputDevices,
                    selectedDeviceUID: model.selectedOutputDeviceUID,
                    onSelect: model.selectOutputDevice
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

private struct DevicePanel: View {
    let title: String
    let currentDevice: AudioDevice?
    let devices: [AudioDevice]
    let selectedDeviceUID: String?
    let onSelect: (String) -> Void

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
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
