import Foundation
import Observation

struct ASRManagedModel: Identifiable {
    let id: String
    let title: String
    let detail: String
    let downloadSize: String
    static let all: [Self] = [
        .init(id: "nemotron", title: "Nemotron 3.5 · 0.6B（推荐）", detail: "按当前实测，英语和日语的速度、识别效果最好，适合实时字幕。", downloadSize: "约 1.2 GB"),
        .init(id: "granite", title: "Granite Speech 5.0 · 2B", detail: "第二推荐。英语和日语可用，分段识别会有一定延迟。", downloadSize: "约 5 GB"),
        .init(id: "qwen17", title: "Qwen3-ASR · 1.7B", detail: "英语识别可用；按当前实测，日语效果不佳，不推荐用于日语。", downloadSize: "约 4.4 GB"),
        .init(id: "qwen06", title: "Qwen3-ASR · 0.6B", detail: "更轻量的对比选项。建议仅用于英语试用，不推荐用于日语。", downloadSize: "约 1.8 GB"),
        .init(id: "multitalker", title: "Multitalker Parakeet（实验）", detail: "仅英语；实时单路草稿，段尾多人校正，不保证比 Nemotron 更快。", downloadSize: "约 833 MB")
    ]
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
        process.environment = ManagedASRRuntime.environment(engine: "granite", online: true, resourceRoot: resources, modelData: data)
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
    private(set) var activeID = ""
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
            if !["granite", "multitalker"].contains(model.id),
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
        guard ManagedASRRuntime.available else { message = "应用缺少内置运行环境，请重新安装完整版本。"; return }
        isBusy = true; activeID = id; progress = nil; errorMessage = nil; buffer.removeAll()
        message = action == "delete" ? "正在删除模型…" : action == "import" ? "正在导入已有模型…" : "正在准备下载…"
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
            if status == 0 { message = action == "delete" ? "模型已删除。" : "模型已准备完成，可以开始识别。" }
            else { message = errorMessage ?? "模型操作未完成，请检查网络及可用磁盘空间后重试。" }
        } catch is CancellationError { message = "已取消；已下载的部分文件会保留，重新下载时将尝试复用。" }
        catch { message = "模型操作失败：" + error.localizedDescription }
        isBusy = false; activeID = ""; job = nil; progress = nil; refresh()
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
