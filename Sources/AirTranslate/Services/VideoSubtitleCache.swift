import CryptoKit
import Foundation
import AirTranslateCore

actor VideoSubtitleCache {
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wenyi/VideoSubtitles", isDirectory: true)
    }
    func load(videoID: String, source: String, target: String, provider: String, input: String) throws -> VideoSubtitleDocument? {
        let file = url(videoID, source, target, provider, input)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let data = try Data(contentsOf: file)
        guard data.count <= 30_000_000 else { return nil }
        let result = try JSONDecoder().decode(VideoSubtitleDocument.self, from: data)
        guard result.videoID == videoID, result.sourceLanguage == source, result.targetLanguage == target,
              result.provider == provider, result.input == input else { return nil }
        return result
    }
    func save(_ document: VideoSubtitleDocument) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = url(document.videoID, document.sourceLanguage, document.targetLanguage, document.provider, document.input)
        try JSONEncoder().encode(document).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
    private func url(_ parts: String...) -> URL {
        let key = SHA256.hash(data: Data((["v1"] + parts).joined(separator: "\u{0}").utf8))
            .map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(key + ".json")
    }
}
