import Foundation

extension Notification.Name {
    static let configPathDidChange = Notification.Name("configPathDidChange")
}

enum ConfigPathPreferences {
    private static let customConfigPathKey = "customConfigPath"

    static func defaultConfigURL() throws -> URL {
        try ConfigStore.defaultConfigURL()
    }

    static func currentConfigURL() throws -> URL {
        guard let path = UserDefaults.standard.string(forKey: customConfigPathKey),
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return try defaultConfigURL()
        }

        return URL(fileURLWithPath: path.expandingTildeInPath)
    }

    static func saveConfigPath(_ path: String) throws {
        let defaultPath = try defaultConfigURL().path
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines).expandingTildeInPath
        try validateConfigPath(normalizedPath)

        if normalizedPath == defaultPath {
            UserDefaults.standard.removeObject(forKey: customConfigPathKey)
        } else {
            UserDefaults.standard.set(normalizedPath, forKey: customConfigPathKey)
        }

        NotificationCenter.default.post(name: .configPathDidChange, object: nil)
    }

    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: customConfigPathKey)
        NotificationCenter.default.post(name: .configPathDidChange, object: nil)
    }

    static func isValidConfigPath(_ path: String) -> Bool {
        let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines).expandingTildeInPath
        return (try? validateConfigPath(normalizedPath)) != nil
    }

    private static func validateConfigPath(_ path: String) throws {
        guard !path.isEmpty else {
            throw ConfigPathError.emptyPath
        }

        guard URL(fileURLWithPath: path).pathExtension.lowercased() == "json" else {
            throw ConfigPathError.invalidExtension
        }
    }
}

enum ConfigPathError: LocalizedError {
    case emptyPath
    case invalidExtension

    var errorDescription: String? {
        switch self {
        case .emptyPath:
            return "配置文件路径不能为空"
        case .invalidExtension:
            return "配置文件路径必须以 .json 结尾"
        }
    }
}
