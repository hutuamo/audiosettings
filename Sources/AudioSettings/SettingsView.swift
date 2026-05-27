import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @State private var configPath = ""
    @State private var savedPath = ""
    @State private var defaultPath = ""
    @State private var errorMessage = ""

    private var canSave: Bool {
        configPath != savedPath && ConfigPathPreferences.isValidConfigPath(configPath)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 8) {
                Text("配置文件路径")
                    .font(.headline)

                HStack(spacing: 8) {
                    TextField("配置文件路径", text: $configPath)
                        .textFieldStyle(.roundedBorder)

                    Button("选择...") {
                        chooseConfigPath()
                    }
                }

                Text("默认：\(defaultPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            HStack {
                Button("使用默认路径") {
                    ConfigPathPreferences.resetToDefault()
                    loadPaths()
                }

                Spacer()

                Button("保存") {
                    savePath()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            loadPaths()
        }
    }

    private func loadPaths() {
        do {
            defaultPath = try ConfigPathPreferences.defaultConfigURL().path
            savedPath = try ConfigPathPreferences.currentConfigURL().path
            configPath = savedPath
            errorMessage = ""
        } catch {
            defaultPath = ""
            savedPath = ""
            configPath = ""
            errorMessage = error.localizedDescription
        }
    }

    private func chooseConfigPath() {
        let panel = NSSavePanel()
        panel.title = "选择配置文件路径"
        panel.nameFieldStringValue = "devices.json"
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.json]

        if !configPath.isEmpty {
            let url = URL(fileURLWithPath: configPath.expandingTildeInPath)
            panel.directoryURL = url.deletingLastPathComponent()
            panel.nameFieldStringValue = url.lastPathComponent
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        configPath = url.path
    }

    private func savePath() {
        do {
            try ConfigPathPreferences.saveConfigPath(configPath)
            savedPath = try ConfigPathPreferences.currentConfigURL().path
            configPath = savedPath
            errorMessage = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
