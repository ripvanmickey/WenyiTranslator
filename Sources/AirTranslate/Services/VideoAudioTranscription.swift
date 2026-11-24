import AVFoundation
import CoreMedia
import Foundation
import AirTranslateCore

actor VideoAudioTranscription {
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        return URLSession(configuration: configuration)
    }()

    /// Upload is called only by the user-started, explicitly selected audio-recognition job.
    /// Each cue uses the media interval, never HTTP completion time. This is phrase-level timing.
    func transcribe(_ file: URL, language: LanguageOption,
                    progress: @MainActor @Sendable ([VideoSubtitleCue], Int, Int) -> Void) async throws -> [VideoSubtitleCue] {
        guard let key = try OpenAIAPIKeyStore.readAPIKey(), !key.isEmpty else {
            throw VideoPreloadProblem(message: "请先在设置 → API 密钥中配置 OpenAI。")
        }
        let asset = AVURLAsset(url: file)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0, duration <= 10_800 else {
            throw VideoPreloadProblem(message: "音轨需在 3 小时以内。")
        }
        let ranges = try await speechRanges(asset, duration: duration)
        var cues: [VideoSubtitleCue] = []
        for (index, range) in ranges.enumerated() {
            try Task.checkCancellation()
            let clip = file.deletingLastPathComponent().appendingPathComponent("clip-\(UUID().uuidString).m4a")
            defer { try? FileManager.default.removeItem(at: clip) }
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw VideoSubtitleError.invalidAudio
            }
            exporter.outputURL = clip; exporter.outputFileType = .m4a
            exporter.timeRange = CMTimeRange(start: CMTime(seconds: range.lowerBound, preferredTimescale: 600),
                end: CMTime(seconds: range.upperBound, preferredTimescale: 600))
            try await VideoAudioExport(exporter).run()
            try Task.checkCancellation()
            guard exporter.status == .completed else { throw VideoSubtitleError.invalidAudio }
            let text = try await request(clip, language: language, key: key)
            if !text.isEmpty { cues.append(.init(id: cues.count, start: range.lowerBound, end: range.upperBound, source: text)) }
            await progress(cues, index + 1, ranges.count)
        }
        guard !cues.isEmpty else { throw VideoPreloadProblem(message: "音轨中未识别到可用语音。") }
        return cues
    }

    private func request(_ file: URL, language: LanguageOption, key: String) async throws -> String {
        let audio = try Data(contentsOf: file)
        guard audio.count < 24_000_000 else { throw VideoPreloadProblem(message: "音轨片段超过上传上限。") }
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
            throw VideoPreloadProblem(message: "OpenAI 音轨识别失败（\(http.statusCode)）。请检查 API 密钥、额度和网络。")
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
