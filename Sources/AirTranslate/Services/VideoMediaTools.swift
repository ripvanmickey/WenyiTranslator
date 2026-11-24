import CryptoKit
import Foundation
import AirTranslateCore

struct VideoPreloadProblem: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

enum VideoProcess {
    static func run(_ executable: URL, arguments: [String], environment: [String: String]? = nil,
                    directory: URL, timeout: TimeInterval = 180) async throws -> Data {
        try Task.checkCancellation()
        let output = directory.appendingPathComponent(UUID().uuidString + ".stdout")
        let errors = directory.appendingPathComponent(UUID().uuidString + ".stderr")
        FileManager.default.createFile(atPath: output.path, contents: nil)
        FileManager.default.createFile(atPath: errors.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: output), stderr = try FileHandle(forWritingTo: errors)
        let process = Process()
        process.executableURL = executable; process.arguments = arguments
        process.environment = environment
        process.standardOutput = stdout; process.standardError = stderr
        defer {
            if process.isRunning { process.terminate() }
            try? stdout.close(); try? stderr.close()
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: errors)
        }
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            try Task.checkCancellation()
            guard Date() < deadline else { throw VideoPreloadProblem(message: "视频处理超时，请重试。") }
            try await Task.sleep(for: .milliseconds(100))
        }
        guard process.terminationStatus == 0 else {
            throw VideoPreloadProblem(message: "无法获取此视频的公开音轨或字幕。请确认视频可公开访问，或导入已有的 SRT／VTT 字幕。")
        }
        try stdout.close(); try stderr.close()
        let size = (try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= 20_000_000 else { throw VideoPreloadProblem(message: "视频信息过大。") }
        return try Data(contentsOf: output)
    }
}

/// Downloads fixed, checksum-verified official releases into the app's own data folder.
/// No browser cookies, shell profile, user Python packages or saved credentials are inherited.
actor VideoMediaTools {
    static let shared = VideoMediaTools()
    static let downloaderURL = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/download/2026.11.23/yt-dlp")!
    static let downloaderSHA = "e8665ed64d6b9172773e812f891fb707a0cb1ee8d9ef4fc1acb00cabee4c5256"
    static let denoURL = URL(string: "https://github.com/denoland/deno/releases/download/v2.9.8/deno-aarch64-apple-darwin.zip")!
    static let denoSHA = "9f0bf660393da2eaff044cdc7444cb08c73f235849b61d224d825a194ce7c98e"
    let root: URL
    private let python: URL
    private let environment: [String: String]
    private let session: URLSession

    init(root: URL? = nil, python: URL? = nil, environment: [String: String]? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wenyi/VideoTools/2026.11.23-2.9.8", isDirectory: true)
        self.python = python ?? ManagedASRRuntime.runtime.appendingPathComponent("bin/python3.12")
        self.environment = environment ?? ManagedASRRuntime.environment(engine: "nemotron", online: true)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60; configuration.timeoutIntervalForResource = 300
        session = URLSession(configuration: configuration)
    }

    func prepare() async throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            throw VideoPreloadProblem(message: "应用缺少内置视频处理运行组件，请使用完整测试安装包。")
        }
        let downloader = root.appendingPathComponent("yt-dlp")
        if !validFile(downloader, hash: Self.downloaderSHA) {
            try await download(Self.downloaderURL, hash: Self.downloaderSHA, to: downloader)
        }
        let archive = root.appendingPathComponent("deno.zip")
        let deno = root.appendingPathComponent("deno")
        let marker = root.appendingPathComponent("deno.sha256")
        let installedHash = try? String(contentsOf: marker, encoding: .utf8)
        if !FileManager.default.isExecutableFile(atPath: deno.path) || installedHash == nil || !validFile(deno, hash: installedHash!) {
            if !validFile(archive, hash: Self.denoSHA) { try await download(Self.denoURL, hash: Self.denoSHA, to: archive) }
            _ = try await VideoProcess.run(URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", archive.path, root.path], directory: root)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: deno.path)
            try digest(deno).write(to: marker, atomically: true, encoding: .utf8)
        }
    }

    func subtitles(for video: YouTubeVideoReference, language: String, directory: URL) async throws -> (title: String, cues: [VideoSubtitleCue]) {
        try await prepare()
        let result = try await execute(video, extra: ["--skip-download", "--write-subs", "--write-auto-subs",
            "--sub-langs", language + ".*", "--sub-format", "vtt", "--write-info-json"], directory: directory)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let file = files.filter({ $0.pathExtension == "vtt" }).sorted(by: {
            func rank(_ file: URL) -> Int {
                if file.lastPathComponent == "media.\(language).vtt" { return 0 }
                if file.lastPathComponent == "media.\(language)-orig.vtt" { return 1 }
                return 2
            }
            return rank($0) == rank($1) ? $0.lastPathComponent < $1.lastPathComponent : rank($0) < rank($1)
        }).first else {
            throw VideoPreloadProblem(message: "此视频没有所选原文语言的字幕。可导入 SRT／VTT，或选择 OpenAI 音轨识别。")
        }
        return (result, try VideoSubtitleTimeline.parse(Data(contentsOf: file)))
    }

    func audio(for video: YouTubeVideoReference, directory: URL) async throws -> (title: String, url: URL) {
        try await prepare()
        let title = try await execute(video, extra: ["-f", "bestaudio[ext=m4a]", "--write-info-json", "--max-filesize", "600M"], directory: directory)
        let file = directory.appendingPathComponent("media.m4a")
        guard FileManager.default.fileExists(atPath: file.path) else { throw VideoSubtitleError.invalidAudio }
        return (title, file)
    }

    private func execute(_ video: YouTubeVideoReference, extra: [String], directory: URL) async throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let args = [root.appendingPathComponent("yt-dlp").path,
            "--ignore-config", "--no-playlist", "--no-progress", "--no-warnings", "--no-cache-dir",
            "--socket-timeout", "30", "--retries", "2", "--match-filter", "!is_live & duration <= 10800", "--js-runtimes", "deno:" + root.appendingPathComponent("deno").path,
            "--paths", directory.path, "-o", "media.%(ext)s"] + extra + ["--", video.url.absoluteString]
        _ = try await VideoProcess.run(python, arguments: args, environment: environment, directory: directory, timeout: 900)
        if let data = try? Data(contentsOf: directory.appendingPathComponent("media.info.json")),
           let info = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if info["is_live"] as? Bool == true { throw VideoPreloadProblem(message: "直播暂不支持提前生成完整字幕，请使用实时聆听。") }
            return info["title"] as? String ?? video.id
        }
        return video.id
    }

    private func download(_ url: URL, hash: String, to destination: URL) async throws {
        let (temporary, response) = try await session.download(from: url)
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              try digest(temporary) == hash else { throw VideoPreloadProblem(message: "视频组件下载或完整性校验失败，请重试。") }
        if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
        try FileManager.default.moveItem(at: temporary, to: destination)
    }
    private func validFile(_ file: URL, hash: String) -> Bool { (try? digest(file)) == hash }
    private func digest(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url); defer { try? file.close() }
        var hasher = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
