import AVFoundation
import CoreMedia
import Darwin
import Foundation
import AirTranslateCore

/// A private local worker per preload job: no microphone capture, live queue
/// dropping, credentials, or network requests. Load weights once, then await each
/// phrase and its consumer before advancing the original media timeline.
final class NemotronVideoRecognizer: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private struct Reply: Decodable {
        let type: String
        let id: Int?
        let text: String?
        let message: String?
    }

    static func validate(resources: URL = ManagedASRRuntime.resources, modelData: URL = ManagedASRRuntime.data) throws {
        do { try ManagedASRRuntime.validate("nemotron", resourceRoot: resources, modelData: modelData) }
        catch {
            throw VideoPreloadProblem(message: AppText.ui("请先在设置 → 通用 → 语音识别引擎中下载或导入 Nemotron 模型。", "Download or import Nemotron in Settings → General → Speech Recognition Engine first.", "先に「設定 → 一般 → 音声認識エンジン」で Nemotron モデルをダウンロードまたは読み込んでください。"))
        }
        guard FileManager.default.fileExists(atPath: resources.appendingPathComponent("NemotronFileBridge.py").path) else {
            throw VideoPreloadProblem(message: AppText.ui("应用缺少本地音轨识别组件，请更新完整安装包。", "The local audio-recognition component is missing. Update the complete app package.", "ローカル音声認識コンポーネントがありません。完全なアプリパッケージに更新してください。"))
        }
    }

    init(resources: URL, modelData: URL, language: LanguageOption, directory: URL) throws {
        try Self.validate(resources: resources, modelData: modelData)
        process.executableURL = resources.appendingPathComponent("ASRRuntime/bin/python3.12")
        process.arguments = ["-u", resources.appendingPathComponent("NemotronFileBridge.py").path,
                             "--runtime", modelData.path, "--language", language.id, "--scratch-root", directory.path]
        process.environment = ManagedASRRuntime.environment(engine: "nemotron", resourceRoot: resources, modelData: modelData)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let fd = output.fileHandleForReading.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }
    func start() async throws {
        try process.run()
        let reply = try await readReply(timeout: 120)
        guard reply.type == "ready" else { throw VideoSubtitleError.invalidAudio }
    }
    func stop() {
        if process.isRunning { process.terminate() }
        try? input.fileHandleForWriting.close()
        try? output.fileHandleForReading.close()
    }
    deinit { stop() }

    func transcribe(_ asset: AVAsset, range: VideoAudioRange, index: Int, directory: URL) async throws -> String {
        let file = directory.appendingPathComponent("nemotron-\(UUID().uuidString).f32")
        defer { try? FileManager.default.removeItem(at: file) }
        let pcm = try await Self.readPCM(asset, range: range)
        guard !pcm.isEmpty else { return "" }
        try pcm.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        var request = try JSONSerialization.data(withJSONObject: ["id": index, "file": file.path])
        request.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: request)
        let reply = try await readReply(timeout: 120)
        guard reply.type == "text", reply.id == index, let text = reply.text else { throw VideoSubtitleError.invalidAudio }
        return text
    }

    private func readReply(timeout: TimeInterval) async throws -> Reply {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            try Task.checkCancellation()
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                let reply = try JSONDecoder().decode(Reply.self, from: line)
                if reply.type == "error" {
                    throw VideoPreloadProblem(message: AppText.ui("Nemotron 本地识别失败：", "Nemotron local recognition failed: ", "Nemotron ローカル認識に失敗しました：") + (reply.message ?? ""))
                }
                return reply
            }
            var bytes = [UInt8](repeating: 0, count: 8192)
            let count = bytes.withUnsafeMutableBytes { Darwin.read(output.fileHandleForReading.fileDescriptor, $0.baseAddress!, $0.count) }
            if count > 0 {
                buffer.append(contentsOf: bytes.prefix(count))
                guard buffer.count <= 65536 else { throw VideoSubtitleError.invalidAudio }
                continue
            }
            guard process.isRunning, Date() < deadline else {
                throw VideoPreloadProblem(message: AppText.ui("Nemotron 本地识别超时或进程已退出，请重试。", "Nemotron timed out or exited. Try again.", "Nemotron がタイムアウトしたか終了しました。再試行してください。"))
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    static func readPCM(_ asset: AVAsset, range: VideoAudioRange) async throws -> Data {
        guard range.start.isFinite, range.end.isFinite, range.start >= 0, range.end > range.start, range.end - range.start <= 15.1,
              let track = try await asset.loadTracks(withMediaType: .audio).first else { throw VideoSubtitleError.invalidAudio }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: range.start, preferredTimescale: 16000),
                                      duration: CMTime(seconds: range.end - range.start, preferredTimescale: 16000))
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false
        ])
        guard reader.canAdd(output) else { throw VideoSubtitleError.invalidAudio }
        reader.add(output)
        guard reader.startReading() else { throw VideoSubtitleError.invalidAudio }
        defer { reader.cancelReading() }
        var pcm = Data()
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard pcm.count + length <= 16_000 * 16 * 4 else { throw VideoSubtitleError.invalidAudio }
            var data = Data(count: length)
            let status = data.withUnsafeMutableBytes { CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: $0.baseAddress!) }
            guard status == noErr else { throw VideoSubtitleError.invalidAudio }
            pcm.append(data)
        }
        guard reader.status == .completed else { throw VideoSubtitleError.invalidAudio }
        return pcm
    }
}
