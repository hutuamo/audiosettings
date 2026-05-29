import Foundation

@MainActor
final class AudioSettingsViewModel: ObservableObject {
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var currentInputDevice: AudioDevice?
    @Published private(set) var currentOutputDevice: AudioDevice?
    @Published private(set) var savedConfiguration: AudioDeviceConfiguration?
    @Published private(set) var statusMessage = ""
    @Published private(set) var isError = false
    @Published private(set) var selectedInputDeviceUID: String?
    @Published private(set) var selectedOutputDeviceUID: String?
    @Published private(set) var outputTestingDeviceUID: String?
    @Published private(set) var isInputTesting = false
    @Published private(set) var inputLevel: Float = 0

    private let deviceService = CoreAudioDeviceService()
    private let testService = AudioTestService()
    private var levelTimer: Timer?
    private var configStore: ConfigStore
    private var configPathObserver: NSObjectProtocol?

    var configPath: String {
        configStore.configURL.path
    }

    var hasUnsavedConfigurationChanges: Bool {
        guard let inputDeviceUID = currentInputDevice?.uid,
              let outputDeviceUID = currentOutputDevice?.uid else {
            return false
        }

        guard let savedConfiguration else {
            return true
        }

        return savedConfiguration.inputDeviceUID != inputDeviceUID
            || savedConfiguration.outputDeviceUID != outputDeviceUID
    }

    init() {
        do {
            configStore = try ConfigStore(configURL: ConfigPathPreferences.currentConfigURL())
        } catch {
            fatalError("无法初始化配置目录：\(error.localizedDescription)")
        }

        configPathObserver = NotificationCenter.default.addObserver(
            forName: .configPathDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reloadConfigStore()
            }
        }
    }

    deinit {
        if let configPathObserver {
            NotificationCenter.default.removeObserver(configPathObserver)
        }
    }

    func refresh() {
        stopAllTests()
        do {
            inputDevices = try deviceService.inputDevices()
            outputDevices = try deviceService.outputDevices()
            currentInputDevice = try deviceService.defaultInputDevice()
            currentOutputDevice = try deviceService.defaultOutputDevice()
            selectedInputDeviceUID = currentInputDevice?.uid
            selectedOutputDeviceUID = currentOutputDevice?.uid
        } catch {
            setError(error)
        }
    }

    func loadSavedConfiguration() {
        do {
            savedConfiguration = try configStore.load()
        } catch CocoaError.fileReadNoSuchFile {
            savedConfiguration = nil
        } catch {
            setError(error)
        }
    }

    private func reloadConfigStore() {
        do {
            configStore = try ConfigStore(configURL: ConfigPathPreferences.currentConfigURL())
            loadSavedConfiguration()
        } catch {
            setError(error)
        }
    }

    func saveCurrentConfiguration() {
        guard let inputDevice = currentInputDevice, let outputDevice = currentOutputDevice else {
            setStatus("当前输入或输出设备为空，无法保存", isError: true)
            return
        }

        let configuration = AudioDeviceConfiguration(
            inputDeviceUID: inputDevice.uid,
            inputDeviceName: inputDevice.name,
            outputDeviceUID: outputDevice.uid,
            outputDeviceName: outputDevice.name,
            savedAt: Date()
        )

        do {
            try configStore.save(configuration)
            savedConfiguration = configuration
        } catch {
            setError(error)
        }
    }

    func applySavedConfiguration() {
        do {
            let configuration = try configStore.load()
            try deviceService.setDefaultInputDevice(uid: configuration.inputDeviceUID)
            try deviceService.setDefaultOutputDevice(uid: configuration.outputDeviceUID)
            savedConfiguration = configuration
            refresh()
        } catch {
            setError(error)
        }
    }

    func selectInputDevice(uid: String) {
        do {
            selectedInputDeviceUID = uid
            try deviceService.setDefaultInputDevice(uid: uid)
            refresh()
        } catch {
            setError(error)
        }
    }

    func selectOutputDevice(uid: String) {
        do {
            selectedOutputDeviceUID = uid
            try deviceService.setDefaultOutputDevice(uid: uid)
            refresh()
        } catch {
            setError(error)
        }
    }

    // MARK: - 音频测试

    func startOutputTest(device: AudioDevice) {
        do {
            try testService.startOutputTest(on: device)
            outputTestingDeviceUID = device.uid
        } catch {
            setError(error)
        }
    }

    func stopOutputTest() {
        testService.stopOutputTest()
        outputTestingDeviceUID = nil
    }

    func startInputTest(device: AudioDevice) {
        switch testService.microphoneAuthorizationStatus() {
        case .authorized:
            beginInputTest(device)
        case .notDetermined:
            testService.requestMicrophoneAccess { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted {
                        self.beginInputTest(device)
                    } else {
                        self.setStatus(AudioTestError.microphonePermissionDenied.localizedDescription, isError: true)
                    }
                }
            }
        case .denied, .restricted:
            setStatus(AudioTestError.microphonePermissionDenied.localizedDescription, isError: true)
        @unknown default:
            setStatus("无法确定麦克风权限状态", isError: true)
        }
    }

    func stopInputTest() {
        testService.stopInputTest()
        levelTimer?.invalidate()
        levelTimer = nil
        isInputTesting = false
        inputLevel = 0
    }

    func stopAllTests() {
        stopOutputTest()
        stopInputTest()
    }

    private func beginInputTest(_ device: AudioDevice) {
        do {
            try testService.startInputTest(on: device)
            isInputTesting = true
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.inputLevel = self?.testService.currentInputLevel() ?? 0
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            levelTimer = timer
        } catch {
            setError(error)
        }
    }

    private func setError(_ error: Error) {
        setStatus(error.localizedDescription, isError: true)
    }

    private func setStatus(_ message: String, isError: Bool = false) {
        statusMessage = message
        self.isError = isError
    }
}
