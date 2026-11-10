import Foundation

/// Rename a saved record and its paired files together, without overwriting another record.
struct SavedTranscriptFileRenamer {
    struct Result {
        let id: String
        let sourceFileName: String
        let translationFileName: String?
    }

    static func rename(_ record: SavedTranscript, title: String, directory: URL) throws -> Result {
        let oldKey = key(record.sourceFileName) ?? record.id
        let titleStore = SavedTranscriptTitleStore(directory: directory)
        // Fail before moving anything if metadata cannot be safely read.
        _ = try titleStore.load()
        let original = Result(id: record.id, sourceFileName: record.sourceFileName, translationFileName: record.translationFileName)
        let normalized = SavedTranscriptTitleStore.normalized(title)
        guard !normalized.isEmpty else {
            try titleStore.set("", for: oldKey)
            return original
        }
        let oldNames = [record.sourceFileName] + (record.translationFileName.map { [$0] } ?? [])
        let manager = FileManager.default
        for name in oldNames {
            guard name == (name as NSString).lastPathComponent,
                  manager.fileExists(atPath: directory.appendingPathComponent(name).path) else {
                throw CocoaError(.fileNoSuchFile)
            }
        }
        let stem = safeStem(normalized)
        var candidate = stem, number = 2
        func reservedNames(_ stem: String) -> [String] {
            ["\(stem).txt", "\(stem)_original.txt", "\(stem)_translation.txt", "\(stem)-original.txt", "\(stem)-translation.txt"]
        }
        while reservedNames(candidate).contains(where: {
            !oldNames.contains($0) && manager.fileExists(atPath: directory.appendingPathComponent($0).path)
        }) {
            candidate = "\(stem) (\(number))"; number += 1
        }
        let paired = record.translationFileName != nil
        let part = suffix(record.sourceFileName)
        let sourceName = paired ? "\(candidate)_original.txt" : "\(candidate)\(part).txt"
        let translationName = paired ? "\(candidate)_translation.txt" : nil
        let newKey = "\(candidate).txt"
        let result = Result(id: paired ? newKey : sourceName, sourceFileName: sourceName, translationFileName: translationName)
        var moved: [(URL, URL)] = []
        do {
            for (old, new) in zip(oldNames, [sourceName] + (translationName.map { [$0] } ?? [])) where old != new {
                let from = directory.appendingPathComponent(old), to = directory.appendingPathComponent(new)
                try manager.moveItem(at: from, to: to)
                moved.append((from, to))
            }
            try titleStore.moveTitle(from: oldKey, to: newKey, title: normalized)
        } catch {
            var rollbackFailed = false
            for (from, to) in moved.reversed() {
                do { try manager.moveItem(at: to, to: from) } catch { rollbackFailed = true }
            }
            if rollbackFailed {
                throw NSError(domain: "RecordRename", code: 1, userInfo: [NSLocalizedDescriptionKey: "改名未完成且恢复失败，请打开保存文件夹检查原文和译文文件。"])
            }
            throw error
        }
        return result
    }

    static func safeStem(_ title: String) -> String {
        var value = SavedTranscriptTitleStore.normalized(title)
        for forbidden in ["/", "\\", ":"] { value = value.replacingOccurrences(of: forbidden, with: "_") }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if value.lowercased().hasSuffix(".txt") { value = String(value.dropLast(4)) }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        if value.isEmpty { value = "未命名记录" }
        // These endings are reserved for pairing original and translation files.
        if ["_original", "_translation", "-original", "-translation"].contains(where: { value.hasSuffix($0) }) {
            value += "_记录"
        }
        while value.utf8.count > 200 { value.removeLast() }
        return value
    }

    private static func suffix(_ name: String) -> String {
        for suffix in ["_original", "_translation", "-original", "-translation"] where name.hasSuffix(suffix + ".txt") { return suffix }
        return ""
    }
    private static func key(_ name: String) -> String? {
        let part = suffix(name)
        return part.isEmpty ? nil : String(name.dropLast(part.count + 4)) + ".txt"
    }
}
