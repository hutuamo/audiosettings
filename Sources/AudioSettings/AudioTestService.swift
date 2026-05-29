import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// 系统声音回放上下文。仅在实时渲染线程内通过裸指针读写，避免 Swift 引用计数。
/// `samples` 为单声道 PCM，回放时扇出到所有输出声道。
/// `position` 在 `0..<(frameCount + gapFrames)` 间循环：前段播声音、后段静音间隔，到末尾归零重播。
private struct PlaybackContext {
    var samples: UnsafeMutablePointer<Float>
    var frameCount: Int
    var gapFrames: Int
    var position: Int
}

/// 输入采集上下文。callback 内通过 `takeUnretainedValue()` 访问，不改变引用计数。
private final class InputTapContext {
    let audioUnit: AudioUnit
    let bufferList: UnsafeMutableAudioBufferListPointer
    let maxFrames: Int
    private var lock = os_unfair_lock_s()
    private var level: Float = 0

    init(audioUnit: AudioUnit, channels: Int, maxFrames: Int) {
        self.audioUnit = audioUnit
        self.maxFrames = maxFrames
        bufferList = AudioBufferList.allocate(maximumBuffers: max(channels, 1))
        for index in 0..<bufferList.count {
            bufferList[index] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(maxFrames * MemoryLayout<Float>.size),
                mData: malloc(maxFrames * MemoryLayout<Float>.size)
            )
        }
    }

    deinit {
        for buffer in bufferList {
            free(buffer.mData)
        }
        free(bufferList.unsafeMutablePointer)
    }

    func storeLevel(_ value: Float) {
        os_unfair_lock_lock(&lock)
        level = value
        os_unfair_lock_unlock(&lock)
    }

    func readLevel() -> Float {
        os_unfair_lock_lock(&lock)
        let value = level
        os_unfair_lock_unlock(&lock)
        return value
    }
}

/// 应用内的音频 I/O 测试：对指定输出设备播放测试音、对指定输入设备实时测量电平。
/// 与 `CoreAudioDeviceService` 平级，封装所有实时音频（AUHAL）相关复杂度。
final class AudioTestService {
    // 输出测试状态
    private var outputUnit: AudioUnit?
    private var playbackPointer: UnsafeMutablePointer<PlaybackContext>?

    // 输入测试状态
    private var inputUnit: AudioUnit?
    private var inputContext: InputTapContext?

    /// 输出测试播放的 macOS 系统声音名（`/System/Library/Sounds/<name>.aiff`）。
    private let systemSoundName = "Ping"
    /// 循环播放时每遍之间的静音间隔。
    private let outputGap: TimeInterval = 1.0
    private let inputMaxFrames = 4096

    deinit {
        stopOutputTest()
        stopInputTest()
    }

    // MARK: - 输出测试

    /// 对选中输出设备循环播放系统声音作为测试音：每播一遍后静音间隔 `outputGap`，再重播，
    /// 直到调用 `stopOutputTest()`。不改变系统默认输出设备。开始前先停止任何正在进行的输出测试。
    func startOutputTest(on device: AudioDevice) throws {
        stopOutputTest()

        let unit = try makeHALUnit()
        do {
            try setCurrentDevice(unit, deviceID: device.id)

            // 读取硬件实际采样率与声道数，按其构造非交错 Float32 客户端格式。
            let hardwareFormat = try streamFormat(unit, scope: kAudioUnitScope_Output, bus: 0)
            let sampleRate = hardwareFormat.mSampleRate > 0 ? hardwareFormat.mSampleRate : 44_100
            let channels = max(Int(hardwareFormat.mChannelsPerFrame), 1)
            var clientFormat = makeFloat32Format(sampleRate: sampleRate, channels: channels)
            try setProperty(
                unit,
                selector: kAudioUnitProperty_StreamFormat,
                scope: kAudioUnitScope_Input,
                bus: 0,
                value: &clientFormat
            )

            // 解码系统声音为单声道 PCM（按设备采样率重采样），扇出到所有声道循环播放。
            let (samples, frameCount) = try loadSystemSound(
                named: systemSoundName, sampleRate: sampleRate)
            let gapFrames = Int(outputGap * sampleRate)
            let playback = UnsafeMutablePointer<PlaybackContext>.allocate(capacity: 1)
            playback.initialize(
                to: PlaybackContext(
                    samples: samples, frameCount: frameCount, gapFrames: gapFrames, position: 0))

            var callback = AURenderCallbackStruct(
                inputProc: outputRenderCallback,
                inputProcRefCon: UnsafeMutableRawPointer(playback)
            )
            try setProperty(
                unit,
                selector: kAudioUnitProperty_SetRenderCallback,
                scope: kAudioUnitScope_Input,
                bus: 0,
                value: &callback
            )

            try check(AudioUnitInitialize(unit), .startFailed)
            try check(AudioOutputUnitStart(unit), .startFailed)

            outputUnit = unit
            playbackPointer = playback
        } catch {
            AudioComponentInstanceDispose(unit)
            throw error
        }
    }

    func stopOutputTest() {
        if let unit = outputUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            outputUnit = nil
        }
        if let playback = playbackPointer {
            playback.pointee.samples.deallocate()
            playback.deinitialize(count: 1)
            playback.deallocate()
            playbackPointer = nil
        }
    }

    // MARK: - 输入测试

    /// 当前麦克风授权状态。
    func microphoneAuthorizationStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// 请求麦克风授权，结果回调在主线程。
    func requestMicrophoneAccess(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            DispatchQueue.main.async { completion(granted) }
        }
    }

    /// 开启对选中输入设备的实时电平采集。调用前应确保已获得麦克风授权。
    /// 开始前先停止任何正在进行的输入测试。
    func startInputTest(on device: AudioDevice) throws {
        guard microphoneAuthorizationStatus() == .authorized else {
            throw AudioTestError.microphonePermissionDenied
        }
        stopInputTest()

        let unit = try makeHALUnit()
        do {
            // 关闭输出（bus 0）、开启输入（bus 1）。
            var disable: UInt32 = 0
            try setProperty(
                unit, selector: kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Output,
                bus: 0, value: &disable)
            var enable: UInt32 = 1
            try setProperty(
                unit, selector: kAudioOutputUnitProperty_EnableIO, scope: kAudioUnitScope_Input,
                bus: 1, value: &enable)

            try setCurrentDevice(unit, deviceID: device.id)

            let hardwareFormat = try streamFormat(unit, scope: kAudioUnitScope_Input, bus: 1)
            let sampleRate = hardwareFormat.mSampleRate > 0 ? hardwareFormat.mSampleRate : 44_100
            let channels = max(Int(hardwareFormat.mChannelsPerFrame), 1)
            var clientFormat = makeFloat32Format(sampleRate: sampleRate, channels: channels)
            try setProperty(
                unit, selector: kAudioUnitProperty_StreamFormat, scope: kAudioUnitScope_Output,
                bus: 1, value: &clientFormat)

            let context = InputTapContext(
                audioUnit: unit, channels: channels, maxFrames: inputMaxFrames)
            var callback = AURenderCallbackStruct(
                inputProc: inputRenderCallback,
                inputProcRefCon: Unmanaged.passUnretained(context).toOpaque()
            )
            try setProperty(
                unit, selector: kAudioOutputUnitProperty_SetInputCallback,
                scope: kAudioUnitScope_Global, bus: 0, value: &callback)

            try check(AudioUnitInitialize(unit), .startFailed)
            try check(AudioOutputUnitStart(unit), .startFailed)

            inputUnit = unit
            inputContext = context
        } catch {
            AudioComponentInstanceDispose(unit)
            throw error
        }
    }

    func stopInputTest() {
        if let unit = inputUnit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            inputUnit = nil
        }
        inputContext = nil
    }

    /// 主线程定时器轮询当前电平（0...1，峰值）。无测试进行时返回 0。
    func currentInputLevel() -> Float {
        inputContext?.readLevel() ?? 0
    }

    // MARK: - AUHAL 辅助

    private func makeHALUnit() throws -> AudioUnit {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw AudioTestError.startFailed(-1)
        }
        var unit: AudioUnit?
        try check(AudioComponentInstanceNew(component, &unit), .startFailed)
        guard let unit else {
            throw AudioTestError.startFailed(-1)
        }
        return unit
    }

    private func setCurrentDevice(_ unit: AudioUnit, deviceID: AudioDeviceID) throws {
        var mutableID = deviceID
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &mutableID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        guard status == noErr else {
            throw AudioTestError.deviceUnavailable
        }
    }

    private func streamFormat(_ unit: AudioUnit, scope: AudioUnitScope, bus: AudioUnitElement)
        throws -> AudioStreamBasicDescription
    {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try check(
            AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, scope, bus, &format, &size),
            .startFailed)
        return format
    }

    /// 用 ExtAudioFile 把系统声音解码为单声道 Float32 PCM（按 `sampleRate` 重采样）。
    /// 返回的指针由调用方负责 `deallocate()`。
    private func loadSystemSound(named name: String, sampleRate: Float64) throws -> (
        UnsafeMutablePointer<Float>, Int
    ) {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        var fileRef: ExtAudioFileRef?
        guard ExtAudioFileOpenURL(url as CFURL, &fileRef) == noErr, let fileRef else {
            throw AudioTestError.soundUnavailable(name)
        }
        defer { ExtAudioFileDispose(fileRef) }

        var clientFormat = makeFloat32Format(sampleRate: sampleRate, channels: 1)
        try check(
            ExtAudioFileSetProperty(
                fileRef,
                kExtAudioFileProperty_ClientDataFormat,
                UInt32(MemoryLayout<AudioStreamBasicDescription>.size),
                &clientFormat
            ),
            .startFailed
        )

        let chunk = 4096
        var scratch = [Float](repeating: 0, count: chunk)
        var pcm = [Float]()
        while true {
            var frames = UInt32(chunk)
            var readStatus: OSStatus = noErr
            scratch.withUnsafeMutableBytes { raw in
                var bufferList = AudioBufferList(
                    mNumberBuffers: 1,
                    mBuffers: AudioBuffer(
                        mNumberChannels: 1,
                        mDataByteSize: UInt32(chunk * MemoryLayout<Float>.size),
                        mData: raw.baseAddress
                    )
                )
                readStatus = ExtAudioFileRead(fileRef, &frames, &bufferList)
            }
            try check(readStatus, .startFailed)
            if frames == 0 { break }
            pcm.append(contentsOf: scratch[0..<Int(frames)])
        }

        guard !pcm.isEmpty else {
            throw AudioTestError.soundUnavailable(name)
        }

        let buffer = UnsafeMutablePointer<Float>.allocate(capacity: pcm.count)
        pcm.withUnsafeBufferPointer { source in
            buffer.initialize(from: source.baseAddress!, count: pcm.count)
        }
        return (buffer, pcm.count)
    }

    private func makeFloat32Format(sampleRate: Float64, channels: Int)
        -> AudioStreamBasicDescription
    {
        let bytesPerSample = UInt32(MemoryLayout<Float>.size)
        return AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
                | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: bytesPerSample,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerSample,
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
    }

    private func setProperty<T>(
        _ unit: AudioUnit, selector: AudioUnitPropertyID, scope: AudioUnitScope,
        bus: AudioUnitElement, value: inout T
    ) throws {
        let size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeBytes(of: &value) { buffer in
            AudioUnitSetProperty(unit, selector, scope, bus, buffer.baseAddress, size)
        }
        try check(status, .startFailed)
    }

    private func check(_ status: OSStatus, _ kind: AudioTestErrorKind) throws {
        guard status == noErr else {
            switch kind {
            case .startFailed:
                throw AudioTestError.startFailed(status)
            }
        }
    }
}

private enum AudioTestErrorKind {
    case startFailed
}

// MARK: - 实时回调（文件级，避免捕获 Swift 闭包上下文）

private let outputRenderCallback: AURenderCallback = { inRefCon, _, _, _, inNumberFrames, ioData in
    guard let ioData = ioData else { return noErr }
    let context = inRefCon.assumingMemoryBound(to: PlaybackContext.self)
    let buffers = UnsafeMutableAudioBufferListPointer(ioData)
    let samples = context.pointee.samples
    let frameCount = context.pointee.frameCount
    let total = frameCount + context.pointee.gapFrames
    var position = context.pointee.position

    for frame in 0..<Int(inNumberFrames) {
        // position 在 [0, frameCount) 播声音，[frameCount, total) 为静音间隔，到末尾归零循环。
        let sample = position < frameCount ? samples[position] : 0
        position += 1
        if position >= total { position = 0 }
        for buffer in buffers {
            guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            data[frame] = sample
        }
    }
    context.pointee.position = position
    return noErr
}

private let inputRenderCallback: AURenderCallback = {
    inRefCon, ioActionFlags, inTimeStamp, _, inNumberFrames, _ in
    let context = Unmanaged<InputTapContext>.fromOpaque(inRefCon).takeUnretainedValue()
    let frames = min(Int(inNumberFrames), context.maxFrames)
    let byteSize = UInt32(frames * MemoryLayout<Float>.size)
    for index in 0..<context.bufferList.count {
        context.bufferList[index].mDataByteSize = byteSize
    }

    // 输入数据位于 element 1（input bus），必须显式渲染该 element。
    let status = AudioUnitRender(
        context.audioUnit,
        ioActionFlags,
        inTimeStamp,
        1,
        inNumberFrames,
        context.bufferList.unsafeMutablePointer
    )
    guard status == noErr else { return status }

    // 用 RMS（均方根）近似响度，比瞬时峰值更平滑，对底噪尖峰不敏感。
    var sumSquares: Float = 0
    var sampleCount = 0
    for buffer in context.bufferList {
        guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
        for frame in 0..<frames {
            let sample = data[frame]
            sumSquares += sample * sample
            sampleCount += 1
        }
    }
    let rms = sampleCount > 0 ? (sumSquares / Float(sampleCount)).squareRoot() : 0
    context.storeLevel(min(rms, 1))
    return noErr
}

enum AudioTestError: LocalizedError {
    case deviceUnavailable
    case startFailed(OSStatus)
    case microphonePermissionDenied
    case soundUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable:
            return "选中的音频设备不可用或已断开"
        case .startFailed(let status):
            return "无法启动音频测试，状态码：\(status)"
        case .microphonePermissionDenied:
            return "麦克风权限被拒绝，请在系统设置 › 隐私与安全性 › 麦克风中授予权限后重试"
        case .soundUnavailable(let name):
            return "无法加载系统声音：\(name)"
        }
    }
}
