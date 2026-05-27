import AudioToolbox
import CoreAudio
import Foundation

final class CoreAudioDeviceService {
    func inputDevices() throws -> [AudioDevice] {
        try allDevices().filter { try hasStreams(deviceID: $0.id, scope: kAudioDevicePropertyScopeInput) }
    }

    func outputDevices() throws -> [AudioDevice] {
        try allDevices().filter { try hasStreams(deviceID: $0.id, scope: kAudioDevicePropertyScopeOutput) }
    }

    func defaultInputDevice() throws -> AudioDevice? {
        let deviceID = try defaultDeviceID(selector: kAudioHardwarePropertyDefaultInputDevice)
        return try device(id: deviceID)
    }

    func defaultOutputDevice() throws -> AudioDevice? {
        let deviceID = try defaultDeviceID(selector: kAudioHardwarePropertyDefaultOutputDevice)
        return try device(id: deviceID)
    }

    func setDefaultInputDevice(uid: String) throws {
        let deviceID = try deviceID(forUID: uid)
        try setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    func setDefaultOutputDevice(uid: String) throws {
        let deviceID = try deviceID(forUID: uid)
        try setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultOutputDevice)
        try setDefaultDevice(deviceID, selector: kAudioHardwarePropertyDefaultSystemOutputDevice)
    }

    private func allDevices() throws -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize))

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = Array(repeating: AudioDeviceID(), count: count)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceIDs))

        return try deviceIDs.compactMap { try device(id: $0) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func device(id deviceID: AudioDeviceID) throws -> AudioDevice? {
        let uid = try stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
        guard !uid.isEmpty else {
            return nil
        }

        let name = try stringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName)
        return AudioDevice(id: deviceID, uid: uid, name: name.isEmpty ? uid : name)
    }

    private func deviceID(forUID uid: String) throws -> AudioDeviceID {
        let devices = try allDevices()
        guard let device = devices.first(where: { $0.uid == uid }) else {
            throw AudioDeviceServiceError.deviceNotFound(uid)
        }
        return device.id
    }

    private func defaultDeviceID(selector: AudioObjectPropertySelector) throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID()
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &deviceID))

        guard deviceID != kAudioObjectUnknown else {
            throw AudioDeviceServiceError.defaultDeviceUnavailable
        }
        return deviceID
    }

    private func setDefaultDevice(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var mutableDeviceID = deviceID
        let dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        try check(AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, dataSize, &mutableDeviceID))
    }

    private func hasStreams(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize))
        return dataSize > 0
    }

    private func stringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let value = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        value.initialize(to: nil)
        defer {
            value.deinitialize(count: 1)
            value.deallocate()
        }

        var dataSize = UInt32(MemoryLayout<CFString?>.size)

        try check(AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, UnsafeMutableRawPointer(value)))
        return value.pointee as String? ?? ""
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw AudioDeviceServiceError.coreAudio(status)
        }
    }
}

enum AudioDeviceServiceError: LocalizedError {
    case coreAudio(OSStatus)
    case defaultDeviceUnavailable
    case deviceNotFound(String)

    var errorDescription: String? {
        switch self {
        case .coreAudio(let status):
            return "CoreAudio 调用失败，状态码：\(status)"
        case .defaultDeviceUnavailable:
            return "当前默认音频设备不可用"
        case .deviceNotFound(let uid):
            return "配置中的音频设备不存在或未连接：\(uid)"
        }
    }
}
