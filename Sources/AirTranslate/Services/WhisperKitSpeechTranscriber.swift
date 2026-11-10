import AVFoundation
import CoreML
@preconcurrency import WhisperKit

protocol LocalSpeechTranscriber: AnyObject, Sendable {
    func append(_ sample: CMSampleBuffer)
    func stop()
    func setPaused(_ value: Bool)
    func diagnosticsSummary() -> String
}

/// WhisperKit is confined to one serial decoding task. The lock protects audio
/// ingestion, pause/stop and generation validation, never model inference.
final class WhisperKitSpeechTranscriber: LocalSpeechTranscriber, @unchecked Sendable {
    typealias Update = @MainActor @Sendable (String, AppleSpeechRecognitionMetadata) -> Void
    typealias Failure = @Sendable (Error) -> Void
    struct Problem: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    private final class Engine: @unchecked Sendable {
        let kit: WhisperKit
        init(_ kit: WhisperKit) { self.kit = kit }
    }
    private let lock = NSLock()
    private var active = false
    private var paused = false
    private var token = UUID()
    private var window = WhisperCaptionWindow()
    private var task: Task<Void, Never>?
    private var onFailure: Failure?
    private var onRecovery: (@Sendable () -> Void)?
    private var statistics = WhisperDecodeStatistics()

    static func prepare(model: String, base: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> String {
        let cached = WhisperModelFiles.defaultFolder(base: base, model: model)
        let folder: URL
        if WhisperModelFiles.isUsable(folder: cached, model: model) {
            folder = cached; progress(1)
        } else {
            folder = try await WhisperKit.download(variant: "openai_whisper-" + model,
                downloadBase: base, progressCallback: { progress($0.fractionCompleted) })
        }
        try Task.checkCancellation()
        // Validate model and tokenizer preparation before reporting Ready.
        let engine = try await load(folder: folder.path, base: base, model: model)
        _ = engine
        return folder.path
    }
    private static func load(folder: String, base: URL, model: String? = nil) async throws -> Engine {
        guard !folder.isEmpty else { throw Problem(message: "请先在 General 中准备 WhisperKit 模型。") }
        if let model, !WhisperModelFiles.isUsable(folder: URL(fileURLWithPath: folder), model: model) {
            throw Problem(message: "所选 WhisperKit 模型文件不完整，或文件夹与所选模型不一致。请在 General 中重新准备对应模型。")
        }
        let config = WhisperKitConfig(downloadBase: base, modelFolder: folder,
            tokenizerFolder: base,
            computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine,
                                                textDecoderCompute: .cpuAndNeuralEngine),
            verbose: false, prewarm: false, load: true, download: false)
        let engine = try await Engine(WhisperKit(config))
        if let model, engine.kit.modelVariant.description != model {
            throw Problem(message: "实际加载的模型与所选模型不一致，已取消启动。")
        }
        return engine
    }
    func start(folder: String, base: URL, model: String? = nil, language: LanguageOption,
               update: @escaping Update, recovery: (@Sendable () -> Void)? = nil, failure: @escaping Failure) async throws {
        stop()
        let session = lock.withLock { token }
        let engine = try await Self.load(folder: folder, base: base, model: model)
        try Task.checkCancellation()
        let enabled = lock.withLock { () -> Bool in
            guard token == session else { return false }
            active = true; paused = false; window = WhisperCaptionWindow(); window.usesSilero = true; window.prioritizesRealtime = true; window.contextFrames = WhisperCaptionWindow.rate * 6; onRecovery = recovery; statistics = WhisperDecodeStatistics(); onFailure = failure
            return true
        }
        guard enabled else { throw CancellationError() }
        let languageCode = language.id.components(separatedBy: "-").first ?? "en"
        let running = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            var lastText = ""
            var lastID = -1
            var hypotheses = WhisperStreamingHypothesis()
            do {
                let detector = try SileroSpeechDetector()
                var vadEpoch: UInt64? = nil
                while !Task.isCancelled {
                    guard self.lock.withLock({ self.active && self.token == session }) else { return }
                    if let input = self.lock.withLock({ self.paused ? nil : self.window.vadInput() }) {
                        if vadEpoch != input.epoch { detector.reset(); vadEpoch = input.epoch }
                        var probabilities: [Float] = []
                        for offset in stride(from: 0, to: input.audio.count, by: 512) {
                            try Task.checkCancellation()
                            probabilities.append(try detector.probability(Array(input.audio[offset..<(offset + 512)])))
                        }
                        self.lock.withLock {
                            if self.active, !self.paused, self.token == session {
                                self.window.applyVAD(start: input.start, probabilities: probabilities, epoch: input.epoch)
                            }
                        }
                    }
                    let snapshot = self.lock.withLock { () -> WhisperCaptionWindow.Snapshot? in
                        guard !self.paused else { return nil }
                        return self.window.snapshot()
                    }
                    guard let snapshot else {
                        try await Task.sleep(for: .milliseconds(40)); continue
                    }
                    let options = Self.decodingOptions(languageCode: languageCode)
                    let decodeStarted = ProcessInfo.processInfo.systemUptime
                    self.lock.withLock { if self.token == session { self.statistics.inFlightSince = decodeStarted } }
                    let results = try await engine.kit.transcribe(audioArray: snapshot.audio, decodeOptions: options)
                    try Task.checkCancellation()
                    let valid = self.lock.withLock {
                        if self.token == session { self.statistics.inFlightSince = nil }
                        return self.active && !self.paused && self.token == session && self.window.epoch == snapshot.epoch
                    }
                    guard valid else { continue }
                    let elapsed = ProcessInfo.processInfo.systemUptime - decodeStarted
                    let rawSegments = results.flatMap(\.segments)
                    let segments = rawSegments.filter { $0.noSpeechProb < 0.8 }.map {
                        WhisperStreamingHypothesis.Segment(text: $0.text, start: Double($0.start), end: Double($0.end))
                    }
                    let decision = hypotheses.decide(segments: segments, snapshot: snapshot)
                    let fullText = segments.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                    var events: [(String, AppleSpeechRecognitionMetadata)] = []
                    self.lock.withLock {
                        guard self.active, !self.paused, self.token == session, self.window.epoch == snapshot.epoch else { return }
                        self.window.adapt(toDecodeSeconds: elapsed)
                        let before = self.window.startFrame
                        func event(_ text: String, id: Int, start: Int, end: Int, final: Bool, revision: Int) {
                            guard !text.isEmpty else { return }
                            var metadata = AppleSpeechRecognitionMetadata(segmentID: "whisper:\(session):\(id)",
                                revision: revision, isFinal: final,
                                audioRange: CMTimeRange(start: CMTime(value: Int64(start), timescale: 16000),
                                    duration: CMTime(value: Int64(max(1, end - start)), timescale: 16000)),
                                sourceText: text, emittedAt: Date())
                            metadata.audioEndUptime = snapshot.audioEndUptime - Double(snapshot.speechEndFrame - end) / 16000
                            events.append((text, metadata))
                        }
                        if rawSegments.isEmpty { self.statistics.noSegmentResults += 1 }
                        if !fullText.isEmpty && snapshot.isFinal && decision.confirmedEnd == 0 {
                            self.statistics.invalidFinalResults += 1
                        }
                        if fullText.isEmpty {
                            self.statistics.emptyResults += 1
                            if snapshot.isFinal && WhisperCaptionWindow.isNonSpeech(rawSegments.map(\.noSpeechProb)) {
                                self.window.complete(snapshot)
                            } else { self.window.retryAfterNewAudio(snapshot) }
                        } else if decision.confirmedEnd > 0 {
                            let frames = snapshot.isFinal
                                ? WhisperCaptionWindow.consumedFrames(snapshot, recognizedEndSeconds: decision.confirmedEnd)
                                : min(snapshot.audio.count, Int((decision.confirmedEnd * 16000).rounded(.down)))
                            if self.window.advance(snapshot, frames: frames) {
                                let confirmed = decision.confirmed.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                                event(confirmed, id: snapshot.id, start: snapshot.startFrame,
                                    end: min(snapshot.speechEndFrame, snapshot.startFrame + frames), final: true, revision: snapshot.revision)
                                if !snapshot.isFinal { self.statistics.stableCommits += 1 }
                                let tail = decision.provisional.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
                                if !tail.isEmpty {
                                    event(tail, id: self.window.id, start: self.window.startFrame,
                                        end: snapshot.speechEndFrame, final: false, revision: 0)
                                    lastText = tail; lastID = self.window.id
                                } else { lastText = ""; lastID = -1 }
                            }
                        } else {
                            if fullText != lastText || snapshot.id != lastID {
                                event(fullText, id: snapshot.id, start: snapshot.startFrame,
                                    end: snapshot.speechEndFrame, final: false, revision: snapshot.revision)
                                lastText = fullText; lastID = snapshot.id
                            }
                            if snapshot.isFinal { self.window.retryAfterNewAudio(snapshot) }
                        }
                        self.statistics.record(seconds: elapsed, audioSeconds: Double(snapshot.audio.count) / 16000,
                            bufferSeconds: Double(self.window.samples.count) / 16000, advanced: self.window.startFrame > before)
                    }
                    // Ordered MainActor delivery: confirmed prefix precedes the new tail.
                    for (text, metadata) in events {
                        guard self.lock.withLock({ self.active && !self.paused && self.token == session && self.window.epoch == snapshot.epoch }) else { break }
                        await update(text, metadata)
                    }

                }
            } catch is CancellationError { }
            catch {
                if self.lock.withLock({ self.active && self.token == session }) { failure(error) }
            }
        }
        lock.withLock {
            if active && token == session { task = running } else { running.cancel() }
        }
    }
    static func decodingOptions(languageCode: String) -> DecodingOptions {
        DecodingOptions(task: .transcribe, language: languageCode,
            temperatureFallbackCount: 0, sampleLength: 224, detectLanguage: false,
            skipSpecialTokens: true, withoutTimestamps: false, windowClipTime: 0,
            // Preserve explicit no-speech probabilities for the caller to classify.
            noSpeechThreshold: nil, concurrentWorkerCount: 1)
    }
    private var stoppedReport: String? = nil
    func diagnosticsSummary() -> String {
        lock.withLock { active ? statistics.summary(window: window) : (stoppedReport ?? "WhisperKit 尚未开始本次识别。") }
    }
    func stop() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            if active || statistics.count > 0 { stoppedReport = statistics.summary(window: window) }
            active = false; token = UUID(); window = WhisperCaptionWindow(); onFailure = nil; onRecovery = nil
            let old = self.task; self.task = nil
            return old
        }
        task?.cancel()
    }
    func setPaused(_ value: Bool) {
        lock.withLock { paused = value; if value { window.discardForPause() } }
    }
    func append(_ sample: CMSampleBuffer) {
        guard lock.withLock({ active && !paused }), let floats = Self.floats(sample) else { return }
        var recoveryNotice: (@Sendable () -> Void)?
        let failure = lock.withLock { () -> Failure? in
            let recoveries = window.realtimeRecoveries
            guard active && !paused else { return nil }
            guard window.append(floats, now: ProcessInfo.processInfo.systemUptime) else {
                stoppedReport = statistics.summary(window: window)
                active = false
                return onFailure
            }
            if window.realtimeRecoveries != recoveries { recoveryNotice = onRecovery }
            statistics.maximumBufferSeconds = max(statistics.maximumBufferSeconds, Double(window.samples.count) / 16000)
            return nil
        }
        recoveryNotice?()
        failure?(Problem(message: "WhisperKit 收到过大的音频批次，已停止。请复制延迟诊断报告。"))
    }

    static func floats(_ sample: CMSampleBuffer) -> [Float]? {
        guard let description = CMSampleBufferGetFormatDescription(sample),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee,
              asbd.mSampleRate == 16000, asbd.mChannelsPerFrame == 1,
              let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        let frames = CMSampleBufferGetNumSamples(sample)
        let bytes = CMBlockBufferGetDataLength(block)
        guard frames > 0, bytes >= frames * Int(asbd.mBytesPerFrame) else { return nil }
        var data = Data(count: bytes)
        let status = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes, destination: $0.baseAddress!) }
        guard status == noErr else { return nil }
        return data.withUnsafeBytes { raw in
            if asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.mBitsPerChannel == 32 {
                return Array(raw.bindMemory(to: Float.self).prefix(frames))
            }
            if asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger != 0, asbd.mBitsPerChannel == 16 {
                return raw.bindMemory(to: Int16.self).prefix(frames).map { Float($0) / 32768 }
            }
            return nil
        }
    }
}
