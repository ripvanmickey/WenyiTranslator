import SwiftUI
import UniformTypeIdentifiers

struct WhisperRecognitionSettingsView: View {
    @Bindable var session: TranslationSessionStore
    @State private var manager = ASRModelManager.shared
    @State private var confirmsDeletion = false
    private var managedID: String { session.localRecognitionEngine == "multitalker" ? "multitalker" : ManagedASRRuntime.modelID(granite: session.graniteRecognitionEnabled, qwen: session.qwenASRModel) }
    private var selectedManagedModel: ASRManagedModel { ASRManagedModel.all.first { $0.id == managedID } ?? ASRManagedModel.all[0] }
    @State private var preparing = false
    @State private var progress: Double = 0
    @State private var message = ""
    @State private var operation: Task<Void, Never>?
    private var locked: Bool { session.isRunning || session.isStarting || preparing || manager.isBusy }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsControlRow(title: "语音识别引擎", detail: "选择本机语音识别引擎，再使用下方配置的引擎翻译；也可选择仅转写。停止后可切换识别引擎。", systemImage: "waveform") {
                Picker("语音识别引擎", selection: $session.localRecognitionEngine) {
                    Text("Nemotron 3.5 · 0.6B（推荐）").tag("nemotron")
                    Text("Granite Speech 5.0 · 2B").tag("granite")
                    Text("Qwen3-ASR（英语试用）").tag("qwen")
                    if PlatformSupport.supportsAppleSpeech { Text("Apple Speech").tag("apple") }
                    Text("Multitalker Parakeet（实验）").tag("multitalker")
                }.labelsHidden().frame(width: 240).disabled(locked)
            }
            if session.whisperRecognitionEnabled && session.nemotronRecognitionEnabled {
                if session.localRecognitionEngine == "qwen" {
                    Picker("Qwen ASR 模型", selection: $session.qwenASRModel) {
                        Text("1.7B · 英语试用").tag("Qwen/Qwen3-ASR-1.7B")
                        Text("0.6B · 轻量试用").tag("Qwen/Qwen3-ASR-0.6B")
                    }.disabled(locked)
                }
                Text(selectedManagedModel.detail).font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    if let bytes = manager.installed[managedID] {
                        Label("已下载 · " + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("尚未下载 · " + selectedManagedModel.downloadSize).foregroundStyle(.secondary)
                    }
                    Button(manager.installed[managedID] == nil ? "下载模型" : "检查与补齐") {
                        let id = managedID
                        Task { await manager.download(id) }
                    }.disabled(locked)
                    if manager.installed[managedID] != nil {
                        Button("删除模型", role: .destructive) { confirmsDeletion = true }.disabled(locked)
                    }
                }
                if !session.nemotronRuntimeFolder.isEmpty,
                   FileManager.default.fileExists(atPath: session.nemotronRuntimeFolder + "/.runtime/models") {
                    Button("导入旧版已下载模型") {
                        let id = managedID; let folder = session.nemotronRuntimeFolder
                        Task { await manager.importOld(id, folder: folder) }
                    }.disabled(locked)
                } else {
                    Button("导入已有模型…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true; panel.canChooseFiles = false
                        panel.message = "选择旧版 NemotronTrial 文件夹。只导入模型文件，不运行旧目录中的程序。"
                        if panel.runModal() == .OK, let folder = panel.url {
                            let id = managedID
                            Task { await manager.importOld(id, folder: folder.path) }
                        }
                    }.disabled(locked)
                }
                HStack {
                    Text("识别组件已内置。首次下载需要联网及磁盘空间；识别在本机进行，不上传音频。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("打开模型文件夹") {
                        try? FileManager.default.createDirectory(at: ManagedASRRuntime.data, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(ManagedASRRuntime.data)
                    }
                }
                if manager.isBusy {
                    if let value = manager.progress { ProgressView(value: value) }
                    else { ProgressView().controlSize(.small) }
                    Button("取消操作") { manager.cancel() }
                }
                if !manager.message.isEmpty { Text(manager.message).font(.caption).textSelection(.enabled) }
            }
            if session.whisperRecognitionEnabled && !session.nemotronRecognitionEnabled {
                HStack {
                    Picker("识别模型", selection: $session.whisperModel) {
                        Text("Tiny · 更轻量").tag("tiny")
                        Text("Base · 均衡试用").tag("base")
                        Text("Small · 更大模型").tag("small")
                    }.frame(width: 250).disabled(locked)
                    Button(session.whisperModelFolder.isEmpty ? "下载并准备模型" : "验证并加载已有模型", action: prepare).disabled(locked)
                    Button("选择模型文件夹…", action: chooseFolder).disabled(locked)
                }
                Text(session.whisperModelFolder.isEmpty ? "尚未准备模型。首次下载从 Hugging Face 获取模型和分词器，需要联网及磁盘空间；不会上传音频。" : "已配置：" + session.whisperModelFolder)
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if preparing {
                    ProgressView(value: progress)
                    Button("取消准备") { operation?.cancel() }
                }
                if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled) }
            }
        }
        .task { manager.refresh() }
        .confirmationDialog("删除所选识别模型？之后需要重新下载才能使用。", isPresented: $confirmsDeletion) {
            Button("删除模型", role: .destructive) {
                let id = managedID
                Task { await manager.delete(id) }
            }
        }
        .onChange(of: session.whisperModel) { _, _ in message = "" }
        .onDisappear { operation?.cancel() }
    }
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "请选择包含 AudioEncoder、TextDecoder 和 MelSpectrogram 的 WhisperKit Core ML 模型文件夹。LM Studio 的 MLX 模型不能用于此处。"
        if panel.runModal() == .OK, let folder = panel.url {
            guard WhisperModelFiles.isUsable(folder: folder, model: session.whisperModel) else {
                message = "该文件夹与当前模型不一致，或模型文件不完整。请选择对应模型文件夹，或下载并准备。"; return
            }
            session.whisperModelFolder = folder.path
            message = "已选择文件夹；开始识别时会验证并加载，分词器首次准备仍可能需要联网。"
        }
    }
    private func prepare() {
        let model = session.whisperModel
        let base = session.whisperModelsDirectory
        preparing = true; session.isPreparingWhisperModel = true; progress = 0; message = "正在下载并准备模型。首次 Core ML 加载可能较慢…"
        operation = Task { @MainActor in
            defer { preparing = false; session.isPreparingWhisperModel = false }
            do {
                let folder = try await WhisperKitSpeechTranscriber.prepare(model: model, base: base) { value in
                    Task { @MainActor in progress = value }
                }
                try Task.checkCancellation()
                guard session.whisperModel == model else { return }
                session.whisperModelFolder = folder
                message = "模型及分词器准备完成，可以开始识别。"
            } catch is CancellationError { message = "已取消准备。" }
            catch { message = "模型准备失败：" + error.localizedDescription }
        }
    }
}
