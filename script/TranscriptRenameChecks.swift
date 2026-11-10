import Foundation
@main struct Checks {
    static func main() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("wenyi-rename-" + UUID().uuidString)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        func write(_ name: String, _ value: String) throws { try Data(value.utf8).write(to: dir.appendingPathComponent(name)) }
        func read(_ name: String) throws -> String { try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) }
        try write("old-original.txt", "原文\n\n正文"); try write("old-translation.txt", "译文正文")
        let date = Date(timeIntervalSince1970: 1000000)
        try fm.setAttributes([.modificationDate: date], ofItemAtPath: dir.appendingPathComponent("old-original.txt").path)
        try SavedTranscriptTitleStore(directory: dir).set("旧标题", for: "old.txt")
        let record = SavedTranscript(id: "old.txt", sourceFileName: "old-original.txt", translationFileName: "old-translation.txt", sourceText: "原文", translatedText: "译文", updatedAt: date)
        try write("访谈.txt", "别人的记录")
        let renamed = try SavedTranscriptFileRenamer.rename(record, title: "访谈", directory: dir)
        precondition(renamed.id == "访谈 (2).txt" && renamed.sourceFileName == "访谈 (2)_original.txt")
        precondition(tryRead(dir, renamed.sourceFileName) == "原文\n\n正文")
        precondition(tryRead(dir, renamed.translationFileName!) == "译文正文")
        precondition(tryRead(dir, "访谈.txt") == "别人的记录")
        let attrs = try fm.attributesOfItem(atPath: dir.appendingPathComponent(renamed.sourceFileName).path)
        precondition(abs((attrs[.modificationDate] as! Date).timeIntervalSince(date)) < 1)
        let titles = try SavedTranscriptTitleStore(directory: dir).load()
        precondition(titles["old.txt"] == nil && titles[renamed.id] == "访谈")
        let missing = SavedTranscript(id: "missing.txt", sourceFileName: renamed.sourceFileName, translationFileName: "missing_translation.txt", sourceText: "", translatedText: "", updatedAt: date)
        do { _ = try SavedTranscriptFileRenamer.rename(missing, title: "失败", directory: dir); preconditionFailure() } catch {}
        precondition(fm.fileExists(atPath: dir.appendingPathComponent(renamed.sourceFileName).path))
        try write("single.txt", "正文")
        let single = SavedTranscript(fileName: "single.txt", sourceText: "正文", updatedAt: date)
        let safe = try SavedTranscriptFileRenamer.rename(single, title: "../../foo:bar\\baz", directory: dir)
        precondition(!safe.sourceFileName.contains("/") && !safe.sourceFileName.contains(":") && !safe.sourceFileName.contains("\\"))
        precondition(tryRead(dir, safe.sourceFileName) == "正文")
        precondition(SavedTranscriptFileRenamer.safeStem("test_original.txt") == "test_original_记录")
        try write("p_original.txt", "P"); try write("p_translation.txt", "T")
        let pair = SavedTranscript(id: "p.txt", sourceFileName: "p_original.txt", translationFileName: "p_translation.txt", sourceText: "P", translatedText: "T", updatedAt: date)
        precondition(SavedTranscriptFileRenamer.safeStem(String(repeating: "文", count: 80)).utf8.count <= 200)
        // Metadata errors must be detected before touching source files.
        try Data("invalid".utf8).write(to: dir.appendingPathComponent(".record-titles.json"))
        do { _ = try SavedTranscriptFileRenamer.rename(pair, title: "新标题", directory: dir); preconditionFailure() } catch {}
        precondition(tryRead(dir, "p_original.txt") == "P" && tryRead(dir, "p_translation.txt") == "T")
        print("PASS paired rename, collision suffix, exact bodies/timestamps, title migration, missing files, path sanitization and corrupt metadata preservation")
    }
    static func tryRead(_ directory: URL, _ name: String) -> String { try! String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8) }
}
