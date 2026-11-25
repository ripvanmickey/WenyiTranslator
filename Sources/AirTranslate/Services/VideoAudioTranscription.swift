import AVFoundation
import CoreMedia
import Foundation
import AirTranslateCore

enum VideoAudioRecognitionEngine: Sendable { case openAI, gemini, nemotron }

actor VideoAudioTranscription {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()

    func prepareRanges(_ file: URL) async throws -> [VideoAudioRange] {
        let asset = AVURLAsset(url: file)
        let duration = try await validatedDuration(asset)
        let ranges = try await speechRanges(asset, duration: duration)
        guard !ranges.isEmpty else { throw VideoPreloadProblem(message: AppText.ui("音轨中未检测到可用语音。", "No usable speech was detected in the audio.", "音声に認識できる発話がありません。")) }
        return ranges.map { .init(start: $0.lowerBound, end: $0.upperBound) }
    }

    /// Each completed phrase is delivered immediately; media intervals stay fixed on resume.
    func transcribe(_ file: URL, language: LanguageOption, ranges: [VideoAudioRange], from startIndex: Int,
                    engine: VideoAudioRecognitionEngine = .openAI, geminiAPIKey: String? = nil,
                    resources: URL = ManagedASRRuntime.resources, modelData: URL = ManagedASRRuntime.data,
                    progress: @MainActor @Sendable (VideoSubtitleCue?, Int, Int) async throws -> Void) async throws {
        let key: String
        if engine == .openAI {
            guard let savedKey = try OpenAIAPIKeyStore.readAPIKey(), !savedKey.isEmpty else {
                throw VideoPreloadProblem(message: AppText.ui("请先在设置 → API 密钥中配置 OpenAI。", "Configure OpenAI in Settings → API Keys first.", "先に「設定 → API キー」で OpenAI を設定してください。"))
            }
            key = savedKey
        } else if engine == .gemini {
            guard let savedKey = try (geminiAPIKey ?? GeminiAPIKeyStore.readAPIKey()), !savedKey.isEmpty else {
                throw VideoPreloadProblem(message: AppText.ui("请先在设置 → API 密钥中配置 Gemini。", "Configure Gemini in Settings → API Keys first.", "先に「設定 → API キー」で Gemini を設定してください。"))
            }
            key = savedKey
        } else { key = "" }
        let asset = AVURLAsset(url: file)
        let duration = try await validatedDuration(asset)
        guard ranges.count <= 30_000, ranges.enumerated().allSatisfy({ index, range in
            range.start.isFinite && range.end.isFinite && range.start >= 0 && range.end > range.start
                && range.end <= duration + 0.1 && range.end - range.start <= 15.1
                && (index == 0 || range.start >= ranges[index - 1].end)
        }) else { throw VideoSubtitleError.invalidAudio }
        let worker: NemotronVideoRecognizer?
        if engine == .nemotron {
            worker = try NemotronVideoRecognizer(resources: resources, modelData: modelData, language: language, directory: file.deletingLastPathComponent())
        } else { worker = nil }
        defer { worker?.stop() }
        if let worker { try await worker.start() }
        try await VideoSubtitleProgressivePipeline.run(ranges: ranges, from: startIndex) { index, range in
            if let worker {
                return try await worker.transcribe(asset, range: range, index: index, directory: file.deletingLastPathComponent())
            }
            let clip = file.deletingLastPathComponent().appendingPathComponent("clip-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: clip) }
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw VideoSubtitleError.invalidAudio
            }
            exporter.outputURL = clip; exporter.outputFileType = .m4a
            exporter.timeRange = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 600),
                end: CMTime(seconds: range.end, preferredTimescale: 600))
            try await VideoAudioExport(exporter).run()
            try Task.checkCancellation()
            guard exporter.status == .completed else { throw VideoSubtitleError.invalidAudio }
            if engine == .gemini {
                return try await GeminiVideoTranscription.transcribe(clip, language: language, key: key, session: self.session)
            }
            return try await self.request(clip, language: language, key: key)
        } consume: { cue, done, total in
            try await progress(cue, done, total)
        }
    }

    private func validatedDuration(_ asset: AVAsset) async throws -> Double {
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 10_800 else {
            throw VideoPreloadProblem(message: AppText.ui("音轨需在 3 小时以内。", "The audio must be no longer than 3 hours.", "音声の長さは 3 時間以内にしてください。"))
        }
        return duration
    }

    private func request(_ file: URL, language: LanguageOption, key: String) async throws -> String {
        let audio = try Data(contentsOf: file)
        guard audio.count < 24_000_000 else { throw VideoPreloadProblem(message: AppText.ui("音轨片段超过上传上限。", "The audio segment exceeds the upload limit.", "音声区間がアップロード上限を超えています。")) }
        let boundary = "Wenyi-" + UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", "gpt-transcribe")
        field("languages[]", String(language.id.prefix(2)))
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"speech.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
        body.append(audio); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"; request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=" + boundary, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VideoSubtitleError.invalidAudio }
        guard (200..<300).contains(http.statusCode) else {
            throw VideoPreloadProblem(message: AppText.ui("OpenAI 音轨识别失败（\(http.statusCode)）。请检查 API 密钥、额度和网络。", "OpenAI audio recognition failed (\(http.statusCode)). Check your API key, quota, and network.", "OpenAI 音声認識に失敗しました（\(http.statusCode)）。API キー、利用枠、ネットワークを確認してください。"))
        }
        struct Response: Decodable { let text: String }
        return try JSONDecoder().decode(Response.self, from: data).text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func speechRanges(_ asset: AVAsset, duration: Double) async throws -> [ClosedRange<Double>] {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw VideoSubtitleError.invalidAudio }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
        ])
        reader.add(output)
        guard reader.startReading() else { throw VideoSubtitleError.invalidAudio }
        defer { reader.cancelReading() }
        var energies: [Double] = [], sum = 0.0, count = 0
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let buffer = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(buffer)
            var data = Data(count: length)
            let status = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(buffer, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            guard status == noErr else { throw VideoSubtitleError.invalidAudio }
            data.withUnsafeBytes { bytes in
                for index in 0..<(length / 4) {
                    let sample = bytes.loadUnaligned(fromByteOffset: index * 4, as: Float.self)
                    sum += Double(sample * sample); count += 1
                    if count == 320 { energies.append(sqrt(sum / 320)); sum = 0; count = 0 }
                }
            }
        }
        guard reader.status == .completed else { throw VideoSubtitleError.invalidAudio }
        if count > 0 { energies.append(sqrt(sum / Double(count))) }
        return VideoSpeechSegmentation.ranges(energies: energies, frameDuration: 0.02, duration: duration)
    }
}

// AVAssetExportSession supports cancellation from another thread. Keep this single-use
// handle outside the transcription actor while the export callback is outstanding.
private final class VideoAudioExport: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
    func run() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                session.exportAsynchronously { [self] in
                    if session.status == .completed { continuation.resume() }
                    else { continuation.resume(throwing: session.error ?? VideoSubtitleError.invalidAudio) }
                }
            }
        } onCancel: { self.session.cancelExport() }
    }
}
