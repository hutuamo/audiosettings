import Foundation

struct AudioDevice: Identifiable, Codable, Equatable {
    let id: UInt32
    let uid: String
    let name: String
}

struct AudioDeviceConfiguration: Codable, Equatable {
    let inputDeviceUID: String
    let inputDeviceName: String
    let outputDeviceUID: String
    let outputDeviceName: String
    let savedAt: Date
}
