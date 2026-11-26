import CryptoKit
import Foundation
import AirTranslateCore

struct VideoSubtitleHistoryEntry: Identifiable, Sendable {
    let id: String
    let title: String
    let sourceLanguage: String
    let targetLanguage: String
    let input: String
    let provider: String
    let updatedAt: Date
    let completed: Bool

    fileprivate init(file: URL, document: VideoSubtitleDocument) {
        id = file.lastPathComponent
        let title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.isEmpty ? document.videoID : title
        sourceLanguage = document.sourceLanguage
        targetLanguage = document.targetLanguage
        input = document.input
        provider = document.provider
        updatedAt = document.updatedAt
        completed = document.completed
    }
}

actor VideoSubtitleCache {
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Wenyi/VideoSubtitles", isDirectory: true)
    }
    func load(videoID: String, source: String, target: String, provider: String, input: String) throws -> VideoSubtitleDocument? {
        let file = url(videoID, source, target, provider, input)
        guard let result = try read(file),
              result.videoID == videoID, result.sourceLanguage == source, result.targetLanguage == target,
              result.provider == provider, result.input == input else { return nil }
        return result
    }

    /// List previously cached videos without depending on the current browser or model selection.
    func history() throws -> [VideoSubtitleHistoryEntry] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        let files = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        var entries: [VideoSubtitleHistoryEntry] = []
        for file in files where file.pathExtension == "json" {
            try Task.checkCancellation()
            if let document = try? readHistoryDocument(file) {
                entries.append(.init(file: file, document: document))
            }
        }
        return entries
    }

    func load(_ entry: VideoSubtitleHistoryEntry) throws -> VideoSubtitleDocument? {
        try readHistoryDocument(root.appendingPathComponent(entry.id, isDirectory: false))
    }

    func save(_ document: VideoSubtitleDocument) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = url(for: document)
        try JSONEncoder().encode(document).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func readHistoryDocument(_ file: URL) throws -> VideoSubtitleDocument? {
        guard let document = try read(file), !document.cues.isEmpty,
              file.lastPathComponent == url(for: document).lastPathComponent else { return nil }
        return document
    }

    private func read(_ file: URL) throws -> VideoSubtitleDocument? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 30_000_000 else { return nil }
        let data = try Data(contentsOf: file)
        guard data.count <= 30_000_000 else { return nil }
        return try JSONDecoder().decode(VideoSubtitleDocument.self, from: data)
    }

    private func url(for document: VideoSubtitleDocument) -> URL {
        url(document.videoID, document.sourceLanguage, document.targetLanguage, document.provider, document.input)
    }

    private func url(_ parts: String...) -> URL {
        let key = SHA256.hash(data: Data((["v1"] + parts).joined(separator: "\u{0}").utf8))
            .map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(key + ".json")
    }
}
