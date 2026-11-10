import Foundation

/// Display titles are separate from transcript text; keys follow explicit file renames.
struct SavedTranscriptTitleStore {
    let directory: URL
    private var url: URL { directory.appendingPathComponent(".record-titles.json") }
    static func normalized(_ value: String) -> String {
        let clean = value.components(separatedBy: .controlCharacters).joined(separator: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(clean.prefix(80))
    }
    func load() throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }
    func set(_ title: String, for key: String) throws {
        var values = try load()
        let value = Self.normalized(title)
        if value.isEmpty { values.removeValue(forKey: key) } else { values[key] = value }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: url, options: .atomic)
    }
    func moveTitle(from oldKey: String, to newKey: String, title: String) throws {
        var values = try load()
        values.removeValue(forKey: oldKey)
        let value = Self.normalized(title)
        if value.isEmpty { values.removeValue(forKey: newKey) } else { values[newKey] = value }
        try JSONEncoder().encode(values).write(to: url, options: .atomic)
    }
    func clear() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}
