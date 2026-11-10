import AVFoundation
import CoreAudio

/// Pure audio capture. Lifecycle calls are serialized by SystemAudioCapture's gate.
/// No screen capture, playback muting, default-device changes, or automatic fallback.
final class CoreAudioTapCapture: @unchecked Sendable {
    struct Failure: LocalizedError {
        let stage: String
        let status: OSStatus
        var errorDescription: String? {
            "纯音频采集失败（\(stage)，\(status)）。请检查系统音频录制权限；也可停止后在 Audio 设置关闭纯音频采集，手动使用兼容方式。不会自动启动屏幕捕获。"
        }
    }
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var ioProc: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "AirTranslate.CoreAudioTap.samples")

    func start(sampleRate: Int, deliver: @escaping @Sendable (CMSampleBuffer) -> Void) throws {
        guard #available(macOS 14.2, *) else {
            throw NSError(domain: "Wenyi.Audio", code: 142, userInfo: [NSLocalizedDescriptionKey: "纯音频采集需要 macOS 14.2或以上。请在音频设置中改用兼容方式，或使用麦克风。"])
        }
        stop()
        do {
            // Exclude our own output so synthesized audio is not re-transcribed.
            // macOS 26 can exclude by bundle ID, including before our process
            // has created an audio device. A silent app may have no process object yet.
            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
            if #available(macOS 26.0, *), let bundleID = Bundle.main.bundleIdentifier { description.bundleIDs = [bundleID] }
            description.name = "AirTranslate audio only"
            description.isPrivate = true
            description.muteBehavior = .unmuted
            try check(AudioHardwareCreateProcessTap(description, &tap), "创建音频 Tap")
            var format = AudioStreamBasicDescription()
            var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), "读取音频格式")
            guard format.mSampleRate > 0, format.mBytesPerFrame > 0 else {
                throw Failure(stage: "无效音频格式", status: -1)
            }
            let composition: [String: Any] = [
                kAudioAggregateDeviceNameKey: "AirTranslate private audio input",
                kAudioAggregateDeviceUIDKey: UUID().uuidString,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString,
                                                  kAudioSubTapDriftCompensationKey: true]]
            ]
            try check(AudioHardwareCreateAggregateDevice(composition as CFDictionary, &device), "创建音频输入")
            let bridge = try PCMBridge(format: format, sampleRate: sampleRate)
            try check(AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, queue) { _, input, _, _, _ in
                if let sample = bridge.convert(input) { deliver(sample) }
            }, "注册音频回调")
            try check(AudioDeviceStart(device, ioProc), "启动音频输入")
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        if device != 0 {
            if let ioProc {
                AudioDeviceStop(device, ioProc)
                AudioDeviceDestroyIOProcID(device, ioProc)
            }
            self.ioProc = nil
            // Drain any already scheduled callbacks before releasing audio objects.
            queue.sync {}
            AudioHardwareDestroyAggregateDevice(device)
            device = 0
        }
        if tap != 0 { if #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tap) }; tap = 0 }
    }
    deinit { stop() }

    private func check(_ status: OSStatus, _ stage: String) throws {
        guard status == noErr else { throw Failure(stage: stage, status: status) }
    }

    /// Runs on the serial audio callback queue. Converts each hardware block directly,
    /// without accumulating a sentence or an additional latency window.
    final class PCMBridge: @unchecked Sendable {
        let source: AVAudioFormat
        let target: AVAudioFormat
        let converter: AVAudioConverter
        init(format: AudioStreamBasicDescription, sampleRate: Int) throws {
            var asbd = format
            guard let source = AVAudioFormat(streamDescription: &asbd),
                  let target = AVAudioFormat(commonFormat: .pcmFormatInt16,
                    sampleRate: Double(sampleRate), channels: 1, interleaved: true),
                  let converter = AVAudioConverter(from: source, to: target) else {
                throw Failure(stage: "创建音频转换器", status: -1)
            }
            self.source = source; self.target = target; self.converter = converter
            converter.primeMethod = .none
        }
        func convert(_ input: UnsafePointer<AudioBufferList>) -> CMSampleBuffer? {
            guard let pcm = AVAudioPCMBuffer(pcmFormat: source, bufferListNoCopy: input, deallocator: nil),
                  pcm.frameLength > 0,
                  let output = AVAudioPCMBuffer(pcmFormat: target,
                    frameCapacity: AVAudioFrameCount(ceil(Double(pcm.frameLength) * target.sampleRate / source.sampleRate)) + 32)
            else { return nil }
            let feed = InputFeed(pcm)
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, state in
                feed.next(state)
            }
            guard status != .error, error == nil, output.frameLength > 0 else { return nil }
            return CoreAudioTapCapture.sampleBuffer(output.audioBufferList, format: target.streamDescription.pointee)
        }
    }

    /// AVAudioConverter pulls synchronously; the lock also enforces single delivery
    /// if the framework changes its callback execution policy.
    private final class InputFeed: @unchecked Sendable {
        let lock = NSLock()
        let buffer: AVAudioPCMBuffer
        var supplied = false
        init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
        func next(_ state: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
            lock.lock(); defer { lock.unlock() }
            guard !supplied else { state.pointee = .noDataNow; return nil }
            supplied = true; state.pointee = .haveData
            return buffer
        }
    }

    /// Copies callback-owned PCM into an owned CMSampleBuffer.
    static func sampleBuffer(_ input: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription) -> CMSampleBuffer? {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        guard let first = buffers.first, first.mData != nil, format.mBytesPerFrame > 0 else { return nil }
        let frames = Int(first.mDataByteSize / format.mBytesPerFrame)
        guard frames > 0 else { return nil }
        var asbd = format
        var description: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &description) == noErr, let description else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: CMTimeScale(format.mSampleRate)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: description, sampleCount: frames,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0,
            sampleSizeArray: nil, sampleBufferOut: &sample) == noErr, let sample else { return nil }
        guard CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: input) == noErr,
            CMSampleBufferSetDataReady(sample) == noErr else { return nil }
        return sample
    }
}
