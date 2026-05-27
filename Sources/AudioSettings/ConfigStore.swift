import Foundation

struct ConfigStore {
    let configURL: URL

    static func defaultConfigURL(fileManager: FileManager = .default) throws -> URL {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("AudioSettings", isDirectory: true)

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("devices.json")
    }

    init(configURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.configURL = try configURL ?? Self.defaultConfigURL(fileManager: fileManager)
        try fileManager.createDirectory(
            at: self.configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func save(_ configuration: AudioDeviceConfiguration) throws {
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(configuration)
        try data.write(to: configURL, options: .atomic)
    }

    func load() throws -> AudioDeviceConfiguration {
        let data = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AudioDeviceConfiguration.self, from: data)
    }
}
