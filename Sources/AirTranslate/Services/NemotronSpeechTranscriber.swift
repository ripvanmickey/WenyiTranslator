import Foundation
import AVFoundation
import Darwin

final class NemotronSpeechTranscriber: LocalSpeechTranscriber, @unchecked Sendable {
    typealias Update = WhisperKitSpeechTranscriber.Update
    typealias Failure = WhisperKitSpeechTranscriber.Failure
    private let lock = NSLock()
    private let writer = DispatchQueue(label: "Wenyi.Nemotron.input")
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var errors: FileHandle?
    private var active = false
    private var paused = false
    private var session = UUID()
    private var epoch = 0
    private var frames = 0
    private var pending: [Data] = []
    private var pendingFrames = 0
    private var draining = false
    private var buffer = Data()
    private var startup: CheckedContinuation<Void, Error>?
    private var update: Update?
    private var failure: Failure?
    private var recovery: (@Sendable () -> Void)?
    private var textCount = 0
    private var processedFrame = 0
    private var skippedFrames = 0
    private var resets = 0
    private var computeSeconds = 0.0
    private var ready = false
    private var deliveryTask: Task<Void, Never>?
    private let resources: URL
    private let modelData: URL
    private let granite: Bool
    private let multitalker: Bool
    private let qwenModel: String
    init(resources: URL? = nil, qwenModel: String = "", multitalker: Bool = false, granite: Bool = false, modelData: URL? = nil) { self.modelData = modelData ?? ManagedASRRuntime.data; self.granite = granite; self.multitalker = multitalker; self.resources = resources ?? Bundle.main.resourceURL ?? Bundle.main.bundleURL; self.qwenModel = qwenModel }


    static var defaultRuntimeFolder: String { "" }
    // Legacy folder arguments remain only for loading older preferences; production always uses managed data.
    static func validate(folder: String) throws { try ManagedASRRuntime.validate("nemotron") }
    static func multitalkerFolder(nemotronFolder: String) -> URL { ManagedASRRuntime.data }
    static func validateMultitalker(folder: String) throws { try ManagedASRRuntime.validate("multitalker") }
    static func validateGranite(folder: String) throws { try ManagedASRRuntime.validate("granite") }
    func start(folder: String, language: LanguageOption, update: @escaping Update,
               recovery: (@Sendable () -> Void)?, failure: @escaping Failure) async throws {
        stop()
        try ManagedASRRuntime.validate(multitalker ? "multitalker" : ManagedASRRuntime.modelID(granite: granite, qwen: qwenModel), resourceRoot: resources, modelData: modelData)
        let script = resources.appendingPathComponent(granite ? "GraniteBridge.py" : multitalker ? "MultitalkerBridge.py" : "NemotronBridge.py")
        guard FileManager.default.fileExists(atPath: script.path) else {
            throw WhisperKitSpeechTranscriber.Problem(message: "应用缺少 Nemotron 桥接组件，请重新解压安装。")
        }
        let root = modelData
        let child = Process(); let stdin = Pipe(); let stdout = Pipe(); let stderr = Pipe()
        child.executableURL = resources.appendingPathComponent("ASRRuntime/bin/python3.12")
        child.arguments = ["-u", script.path, "--runtime", root.path, "--language", language.id]
        if !qwenModel.isEmpty { child.arguments! += ["--qwen-model", qwenModel] }
        child.environment = ManagedASRRuntime.environment(engine: granite ? "granite" : qwenModel.isEmpty ? "nemotron" : "qwen", resourceRoot: resources, modelData: root)
        child.standardInput = stdin; child.standardOutput = stdout; child.standardError = stderr
        let token = UUID()
        lock.withLock {
            session = token; active = true; paused = false; ready = false
            epoch = 0; frames = 0; pendingFrames = 0; draining = false; pending.removeAll(); buffer.removeAll()
            textCount = 0; processedFrame = 0; skippedFrames = 0; resets = 0; computeSeconds = 0
            self.update = update; self.failure = failure; self.recovery = recovery
            process = child; input = stdin.fileHandleForWriting; output = stdout.fileHandleForReading; errors = stderr.fileHandleForReading
        }
        let stdoutFD = stdout.fileHandleForReading.fileDescriptor
        let stderrFD = stderr.fileHandleForReading.fileDescriptor
        _ = fcntl(stdoutFD, F_SETFL, fcntl(stdoutFD, F_GETFL) | O_NONBLOCK)
        _ = fcntl(stderrFD, F_SETFL, fcntl(stderrFD, F_GETFL) | O_NONBLOCK)
        stdout.fileHandleForReading.readabilityHandler = { [weak self] _ in
            guard let self else { return }
            let data = self.lock.withLock { () -> Data in
                guard self.active, self.session == token else { return Data() }
                return Self.readAvailable(stdoutFD)
            }
            if !data.isEmpty { self.receive(data, token: token) }
        }
        // Read only currently available bytes. A fixed-length FileHandle read can
        // otherwise wait for more bytes and deadlock the startup ready handshake.
        stderr.fileHandleForReading.readabilityHandler = { [weak self] _ in
            guard let self else { return }
            self.lock.withLock {
                if self.active, self.session == token { _ = Self.readAvailable(stderrFD) }
            }
        }
        child.terminationHandler = { [weak self] process in
            self?.fail("本地识别后台进程已退出（\(process.terminationStatus)），请重新开始。", token: token)
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let valid = lock.withLock { () -> Bool in
                    guard active, session == token else { return false }
                    startup = continuation; return true
                }
                guard valid else { continuation.resume(throwing: CancellationError()); return }
                _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
                do {
                    try child.run()
                    if !lock.withLock({ active && session == token }), child.isRunning { child.terminate() }
                }
                catch { fail("无法启动本地识别：" + error.localizedDescription, token: token) }
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(90))
                    if let self, self.lock.withLock({ self.session == token && self.active && !self.ready }) {
                        self.fail("本地识别加载超时，请确认独立试用仍可运行。", token: token)
                    }
                }
            }
        } onCancel: { [weak self] in self?.stop() }
    }
    private static func readAvailable(_ fd: Int32) -> Data {
        var bytes = [UInt8](repeating: 0, count: 65536)
        let count = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!, $0.count) }
        return count > 0 ? Data(bytes.prefix(count)) : Data()
    }
    private func fail(_ message: String, token: UUID) {
        let state = lock.withLock { () -> (CheckedContinuation<Void, Error>?, Failure?) in
            guard active, session == token else { return (nil, nil) }
            let continuation = startup; startup = nil; active = false
            return (continuation, continuation == nil ? failure : nil)
        }
        guard state.0 != nil || state.1 != nil else { return }
        stop()
        let error = WhisperKitSpeechTranscriber.Problem(message: message)
        state.0?.resume(throwing: error); state.1?(error)
    }
    private func receive(_ data: Data, token: UUID) {
        let lines = lock.withLock { () -> [Data] in
            guard active, session == token else { return [] }
            buffer.append(data)
            guard buffer.count <= 1_048_576 else { buffer.removeAll(); return [] }
            var lines: [Data] = []
            while let newline = buffer.firstIndex(of: 10) {
                lines.append(Data(buffer.prefix(upTo: newline))); buffer.removeSubrange(...newline)
            }
            return lines
        }
        for line in lines {
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any], let type = json["type"] as? String else { continue }
            if type == "ready" {
                let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
                    guard active, session == token else { return nil }
                    ready = true; let result = startup; startup = nil; return result
                }
                continuation?.resume()
            } else if type == "error" {
                fail("本地识别：" + (json["message"] as? String ?? "识别失败"), token: token)
            } else if type == "stats" {
                lock.withLock {
                    guard active, session == token, json["epoch"] as? Int == epoch else { return }
                    processedFrame = json["end_frame"] as? Int ?? processedFrame
                    computeSeconds = json["compute_seconds"] as? Double ?? computeSeconds
                }
            } else if type == "text", let text = json["text"] as? String, !text.isEmpty,
                      let resultEpoch = json["epoch"] as? Int,
                      let utterance = json["utterance"] as? Int,
                      let start = json["start_frame"] as? Int, let end = json["end_frame"] as? Int, end >= start {
                let callback = lock.withLock { () -> Update? in
                    guard active, !paused, session == token, epoch == resultEpoch else { return nil }
                    textCount += 1; processedFrame = max(processedFrame, end); return update
                }
                guard let callback else { continue }
                var metadata = AppleSpeechRecognitionMetadata(segmentID: "nemotron:\(token):\(resultEpoch):\(utterance)",
                    revision: json["revision"] as? Int ?? 0, isFinal: json["final"] as? Bool ?? false,
                    audioRange: CMTimeRange(start: CMTime(value: Int64(start), timescale: 16000), duration: CMTime(value: Int64(max(1, end-start)), timescale: 16000)), sourceText: text, emittedAt: Date())
                metadata.audioEndUptime = json["end_uptime"] as? Double
                let delivered = metadata
                lock.withLock {
                    let previous = deliveryTask
                    deliveryTask = Task { @MainActor [weak self] in
                        await previous?.value
                        guard let self, self.lock.withLock({ self.active && !self.paused && self.session == token && self.epoch == resultEpoch }) else { return }
                        callback(text, delivered)
                    }
                }
            }
        }
    }
    func append(_ sample: CMSampleBuffer) {
        guard let values = WhisperKitSpeechTranscriber.floats(sample), !values.isEmpty else { return }
        let pcm = values.map { Int16(max(-32767, min(32767, ($0.isFinite ? $0 : 0) * 32767))) }
        let raw = pcm.withUnsafeBytes { Data($0) }
        var notice: (@Sendable () -> Void)?
        let begin = lock.withLock { () -> UUID? in
            guard active, ready, !paused else { return nil }
            frames += values.count
            if pendingFrames + values.count > 16000 * 3 {
                skippedFrames += pendingFrames; pending.removeAll(); pendingFrames = 0; epoch += 1; resets += 1
                notice = recovery
            }
            let payload: [String: Any] = ["type":"audio", "epoch":epoch, "pcm":raw.base64EncodedString(), "end_frame":frames, "end_uptime":ProcessInfo.processInfo.systemUptime]
            guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
            data.append(10); pending.append(data); pendingFrames += values.count
            if draining { return nil }; draining = true; return session
        }
        notice?()
        if let begin { writer.async { [weak self] in self?.drain(token: begin) } }
    }
    private func drain(token: UUID) {
        while true {
            let next = lock.withLock { () -> (Data, FileHandle)? in
                guard session == token else { return nil }
                guard active else { draining = false; return nil }
                guard !pending.isEmpty, let input else { draining = false; return nil }
                let data = pending.removeFirst()
                // Use the packet's decoded byte count, not JSON/base64 overhead.
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let b64 = json["pcm"] as? String, let pcm = Data(base64Encoded: b64) { pendingFrames = max(0, pendingFrames - pcm.count/2) }
                return (data,input)
            }
            guard let next else { return }
            do { try next.1.write(contentsOf: next.0) }
            catch { fail("本地识别音频连接中断，请重新开始。", token: token); return }
        }
    }
    func setPaused(_ value: Bool) {
        lock.withLock {
            paused = value
            if value { epoch += 1; pending.removeAll(); pendingFrames = 0 }
        }
    }
    func stop() {
        let state = lock.withLock { () -> (Process?, FileHandle?, FileHandle?, FileHandle?, CheckedContinuation<Void, Error>?) in
            active = false; ready = false; session = UUID(); pending.removeAll(); pendingFrames = 0
            deliveryTask?.cancel(); deliveryTask = nil
            let result = (process,input,output,errors,startup)
            process = nil; input = nil; output = nil; errors = nil; startup = nil; update = nil; failure = nil; recovery = nil
            return result
        }
        state.2?.readabilityHandler = nil; state.3?.readabilityHandler = nil
        if state.0?.isRunning == true { state.0?.terminate() }
        try? state.1?.close(); try? state.2?.close(); try? state.3?.close()
        state.4?.resume(throwing: CancellationError())
    }
    func diagnosticsSummary() -> String {
        lock.withLock {
            String(format: (granite ? "Granite Speech 5.0 · 2B（分段）" : multitalker ? "Multitalker Parakeet · 实时草稿＋段尾多人校正" : (qwenModel.isEmpty ? "Nemotron 3.5" : "Qwen3-ASR")) + " 本地流式识别\n已接收 %.2f 秒 · 已处理至 %.2f 秒 · 写入队列 %.2f 秒\n累计识别计算 %.2f 秒 · 字幕更新 %d 次\n音频队列恢复 %d 次 · 跳过 %.2f 秒\n识别时序按输入块末端估算，不包含准确的词级声学对齐。", Double(frames)/16000, Double(processedFrame)/16000, Double(pendingFrames)/16000, computeSeconds, textCount, resets, Double(skippedFrames)/16000)
        }
    }
}
