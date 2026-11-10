import Foundation
@main struct Checks {
    static func main() throws {
        func check(_ value: Bool) { precondition(value) }
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("文译标题检查-"+UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = SavedTranscriptTitleStore(directory: root)
        try store.set("音乐创作与歌手成长", for: "paired-record")
        try store.set(" 自定义\n标题 \t测试 ", for: "second")
        let reopened = SavedTranscriptTitleStore(directory: root)
        check(try reopened.load()["paired-record"] == "音乐创作与歌手成长")
        check(try reopened.load()["second"] == "自定义 标题 测试")
        try reopened.set("", for: "second")
        let retained = try store.load()
        precondition(retained.count == 1 && retained["paired-record"] != nil)
        let transcript = root.appendingPathComponent("original.txt")
        try "原文正文，保持不变。".write(to: transcript, atomically: true, encoding: .utf8)
        try store.set(String(repeating: "长", count: 100), for: "paired-record")
        check(try store.load()["paired-record"]?.count == 80)
        check(try String(contentsOf: transcript, encoding: .utf8) == "原文正文，保持不变。")
        let metadata = root.appendingPathComponent(".record-titles.json")
        let damaged = Data("broken metadata".utf8);try damaged.write(to: metadata)
        do { try store.set("新标题", for: "third");preconditionFailure("Must not overwrite unreadable metadata") } catch {}
        check(try Data(contentsOf: metadata) == damaged)
        try store.clear();check(try store.load().isEmpty)
        print("PASS title persistence, normalization, independent entries, body preservation, length cap, corrupt metadata preservation and clear")
    }
}
