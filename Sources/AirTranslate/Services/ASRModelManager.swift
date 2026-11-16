import Foundation
import Observation

struct ASRManagedModel: Identifiable {
    let id: String
    let title: String
    let detail: String
    let downloadSize: String
    static var all: [Self] {
        [
            .init(id: "nemotron", title: AppText.ui("Nemotron 3.5 · 0.6B（推荐）", "Nemotron 3.5 · 0.6B (Recommended)", "Nemotron 3.5 · 0.6B（推奨）"), detail: AppText.ui("按当前实测，英语和日语的速度、识别效果最好，适合实时字幕。", "Recommended for live English and Japanese captions based on our tests.", "実測では英語と日本語の速度と認識精度が良好で、リアルタイム字幕に適しています。"), downloadSize: AppText.ui("约 1.2 GB", "About 1.2 GB", "約 1.2 GB")),
            .init(id: "qwen17", title: "Qwen3-ASR · 1.7B", detail: AppText.ui("英语识别可用；按当前实测，日语效果不佳，不推荐用于日语。", "Suitable for English. Our tests found weak Japanese recognition.", "英語向けです。実測では日本語の認識精度が十分ではありませんでした。"), downloadSize: AppText.ui("约 4.4 GB", "About 4.4 GB", "約 4.4 GB")),
            .init(id: "qwen06", title: "Qwen3-ASR · 0.6B", detail: AppText.ui("更轻量的对比选项。建议仅用于英语试用，不推荐用于日语。", "A lighter model for English trials.", "英語の試用向けの軽量モデルです。"), downloadSize: AppText.ui("约 1.8 GB", "About 1.8 GB", "約 1.8 GB")),
            .init(id: "multitalker", title: AppText.ui("Multitalker Parakeet（实验）", "Multitalker Parakeet (Experimental)", "Multitalker Parakeet（実験的）"), detail: AppText.ui("仅英语；实时单路草稿，段尾多人校正，不保证比 Nemotron 更快。", "English only. Shows a live draft and corrects speaker turns at the end of each segment.", "英語のみ対応。暫定字幕を表示し、区間の確定時に話者の区切りを修正します。"), downloadSize: AppText.ui("约 833 MB", "About 833 MB", "約 833 MB"))
        ]
    }
}

private final class ASRModelOperation: @unchecked Sendable {
    private let resources: URL
    private let data: URL
    init(resources: URL = ManagedASRRuntime.resources, data: URL = ManagedASRRuntime.data) {
        self.resources = resources; self.data = data
    }
    private let lock = NSLock()
    private var child: Process?
    private var cancelled = false
    func cancel() {
        lock.lock(); cancelled = true; let process = child; lock.unlock()
        if let process, process.isRunning { process.terminate() }
    }
    func run(arguments: [String], progress: @escaping @Sendable (Data) -> Void) throws -> Int32 {
        let process = Process(); let pipe = Pipe()
        process.executableURL = resources.appendingPathComponent("ASRRuntime/bin/python3.12")
        process.arguments = [resources.appendingPathComponent("ASRModels.py").path] + arguments
        process.environment = ManagedASRRuntime.environment(engine: "nemotron", online: true, resourceRoot: resources, modelData: data)
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        child = process
        do { try process.run() } catch { child = nil; lock.unlock(); throw error }
        lock.unlock()
        let input = pipe.fileHandleForReading
        defer { try? input.close() }
        while true {
            let chunk = input.availableData
            if chunk.isEmpty { break }
            progress(chunk)
        }
        process.waitUntilExit()
        lock.lock(); child = nil; let stopped = cancelled; lock.unlock()
        if stopped { throw CancellationError() }
        return process.terminationStatus
    }
}

@MainActor @Observable final class ASRModelManager {
    static let shared = ASRModelManager()
    private(set) var installed: [String: Int64] = [:]
    private(set) var isBusy = false
    private(set) var messageModelID = ""
    private(set) var message = ""
    private(set) var progress: Double?
    private var job: ASRModelOperation?
    private var buffer = Data()
    private var errorMessage: String?

    func refresh() {
        var available: [String: Int64] = [:]
        let catalogData = try? Data(contentsOf: ManagedASRRuntime.resources.appendingPathComponent("ASRModelCatalog.json"))
        let catalog = catalogData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: [String: String]] } ?? [:]
        for model in ASRManagedModel.all {
            let folder = ManagedASRRuntime.data.appendingPathComponent("models/" + model.id)
            if model.id != "multitalker",
               !FileManager.default.fileExists(atPath: ManagedASRRuntime.data.appendingPathComponent("models/vad/ready.json").path) { continue }
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("ready.json")),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  record["revision"] as? String == catalog[model.id]?["revision"],
                  let entries = record["files"] as? [[String: Any]], !entries.isEmpty else { continue }
            let root = folder.appendingPathComponent("files").resolvingSymlinksInPath().path + "/"
            let complete = entries.allSatisfy { entry in
                guard let path = entry["path"] as? String, let size = entry["size"] as? NSNumber else { return false }
                let file = folder.appendingPathComponent("files/" + path).resolvingSymlinksInPath()
                guard file.path.hasPrefix(root), let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                      let actual = attributes[.size] as? NSNumber else { return false }
                return actual.int64Value == size.int64Value
            }
            if complete { available[model.id] = (record["bytes"] as? NSNumber)?.int64Value ?? 0 }
        }
        installed = available
    }
    func cancel() { job?.cancel() }
    func download(_ id: String) async { await perform("download", id: id) }
    func importOld(_ id: String, folder: String) async { await perform("import", id: id, old: folder) }
    func delete(_ id: String) async { await perform("delete", id: id) }
    private func perform(_ action: String, id: String, old: String? = nil) async {
        guard !isBusy, ASRManagedModel.all.contains(where: { $0.id == id }) else { return }
        messageModelID = id
        guard ManagedASRRuntime.available else { message = AppText.ui("应用缺少内置运行环境，请重新安装完整版本。", "The built-in runtime is missing. Reinstall the full app.", "内蔵ランタイムが見つかりません。完全版を再インストールしてください。"); return }
        isBusy = true; progress = nil; errorMessage = nil; buffer.removeAll()
        message = action == "delete" ? AppText.ui("正在删除模型…", "Deleting model…", "モデルを削除中…") : action == "import" ? AppText.ui("正在导入已有模型…", "Importing model…", "モデルを読み込み中…") : AppText.ui("正在准备下载…", "Preparing download…", "ダウンロードを準備中…")
        let operation = ASRModelOperation(); job = operation
        var arguments = [action, "--root", ManagedASRRuntime.data.path, "--model", id]
        if let old { arguments += ["--old", old] }
        do {
            let status = try await Task.detached {
                try operation.run(arguments: arguments) { [weak self] chunk in
                    Task { @MainActor in self?.receive(chunk) }
                }
            }.value
            // Let already queued stdout progress updates run before the terminal status.
            await Task.yield()
            if status == 0 { message = action == "delete" ? AppText.ui("模型已删除。", "Model deleted.", "モデルを削除しました。") : AppText.ui("模型已准备完成，可以开始识别。", "The model is ready for speech recognition.", "モデルの準備ができました。") }
            else { message = errorMessage ?? AppText.ui("模型操作未完成，请检查网络及可用磁盘空间后重试。", "The model operation did not finish. Check your network and free disk space, then retry.", "モデルの処理が完了しませんでした。ネット接続と空き容量を確認して、再試行してください。") }
        } catch is CancellationError { message = AppText.ui("已取消；已下载的部分文件会保留，重新下载时将尝试复用。", "Cancelled. Downloaded files were kept for the next attempt.", "キャンセルしました。取得済みファイルは次回のために保持されています。") }
        catch { message = AppText.ui("模型操作失败：", "Model operation failed: ", "モデルの処理に失敗しました：") + error.localizedDescription }
        isBusy = false; job = nil; progress = nil; refresh()
    }
    private func receive(_ chunk: Data) {
        guard isBusy else { return }
        buffer.append(chunk)
        if buffer.count > 1_000_000 { buffer.removeAll(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if event["type"] as? String == "error" { errorMessage = event["message"] as? String }
            if let text = event["message"] as? String { message = text }
            if let total = event["total"] as? Double, total > 0, let count = event["completed"] as? Double {
                progress = min(1, max(0, count / total))
            } else { progress = nil }
        }
    }
}
