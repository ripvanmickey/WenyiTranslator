import SwiftUI
import UniformTypeIdentifiers

struct WhisperRecognitionSettingsView: View {
    @Bindable var session: TranslationSessionStore
    @State private var manager = ASRModelManager.shared
    @State private var showsModelManagement = false
    @State private var confirmsDeletion = false
    private var managedID: String { session.localRecognitionEngine == "multitalker" ? "multitalker" : ManagedASRRuntime.modelID(qwen: session.qwenASRModel) }
    private var selectedManagedModel: ASRManagedModel { ASRManagedModel.all.first { $0.id == managedID } ?? ASRManagedModel.all[0] }
    @State private var preparing = false
    @State private var progress: Double = 0
    @State private var message = ""
    @State private var operation: Task<Void, Never>?
    private var locked: Bool { session.isRunning || session.isStarting || preparing || manager.isBusy }

    private var usesManagedModel: Bool {
        session.whisperRecognitionEnabled && session.nemotronRecognitionEnabled
    }

    private var modelManagementTitle: String {
        AppText.ui("管理识别模型", "Manage Speech Model", "音声認識モデルの管理")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SettingsControlRow(title: AppText.ui("语音识别引擎", "Speech Recognition Engine", "音声認識エンジン"), detail: AppText.ui("选择本机语音识别引擎，再使用下方配置的引擎翻译；也可选择仅转写。停止后可切换识别引擎。", "Choose an on-device engine for transcription. Stop listening before switching engines.", "端末内で文字起こしを行うエンジンを選びます。エンジンを切り替えるには、先に聞き取りを停止してください。"), systemImage: "waveform", controlBelowLabel: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Picker(AppText.ui("语音识别引擎", "Speech Recognition Engine", "音声認識エンジン"), selection: $session.localRecognitionEngine) {
                            Text(AppText.ui("Nemotron 3.5 · 0.6B（推荐）", "Nemotron 3.5 · 0.6B (Recommended)", "Nemotron 3.5 · 0.6B（推奨）")).tag("nemotron")
                            Text(AppText.ui("Qwen3-ASR（英语试用）", "Qwen3-ASR (English Trial)", "Qwen3-ASR（英語の試用）")).tag("qwen")
                            if PlatformSupport.supportsAppleSpeech { Text("Apple Speech").tag("apple") }
                            Text(AppText.ui("Multitalker Parakeet（实验）", "Multitalker Parakeet (Experimental)", "Multitalker Parakeet（実験的）")).tag("multitalker")
                        }.pickerStyle(.menu).labelsHidden().fixedSize(horizontal: true, vertical: false).disabled(locked)
                        if usesManagedModel {
                            Button {
                                showsModelManagement = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .help(modelManagementTitle)
                            .accessibilityLabel(modelManagementTitle)
                            .accessibilityIdentifier("manageSpeechRecognitionModel")
                        }
                    }
                    if usesManagedModel {
                        if session.localRecognitionEngine == "qwen" {
                            Picker(AppText.ui("Qwen ASR 模型", "Qwen ASR Model", "Qwen ASR モデル"), selection: $session.qwenASRModel) {
                                Text(AppText.ui("1.7B · 英语试用", "1.7B · English Trial", "1.7B · 英語の試用")).tag("Qwen/Qwen3-ASR-1.7B")
                                Text(AppText.ui("0.6B · 轻量试用", "0.6B · Lightweight Trial", "0.6B · 軽量版の試用")).tag("Qwen/Qwen3-ASR-0.6B")
                            }.disabled(locked)
                        }
                        Text(selectedManagedModel.detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        managedModelStatus
                        if manager.isBusy {
                            if let value = manager.progress { ProgressView(value: value) }
                            else { ProgressView().controlSize(.small) }
                            Button(AppText.ui("取消操作", "Cancel Operation", "処理をキャンセル")) { manager.cancel() }
                        }
                        if manager.messageModelID == managedID && !manager.message.isEmpty { Text(manager.message).font(.caption).textSelection(.enabled) }
                    }
                }
            }
            if session.whisperRecognitionEnabled && !session.nemotronRecognitionEnabled {
                HStack {
                    Picker(AppText.ui("识别模型", "Recognition Model", "認識モデル"), selection: $session.whisperModel) {
                        Text(AppText.ui("Tiny · 更轻量", "Tiny · Lightweight", "Tiny · 軽量")).tag("tiny")
                        Text(AppText.ui("Base · 均衡试用", "Base · Balanced Trial", "Base · バランス型")).tag("base")
                        Text(AppText.ui("Small · 更大模型", "Small · Larger Model", "Small · 大きめのモデル")).tag("small")
                    }.frame(width: 250).disabled(locked)
                    Button(session.whisperModelFolder.isEmpty ? AppText.ui("下载并准备模型", "Download and Prepare Model", "モデルをダウンロードして準備") : AppText.ui("验证并加载已有模型", "Verify and Load Existing Model", "既存モデルを確認して読み込む"), action: prepare).disabled(locked)
                    Button(AppText.ui("选择模型文件夹…", "Choose Model Folder…", "モデルフォルダを選択…"), action: chooseFolder).disabled(locked)
                }
                Text(session.whisperModelFolder.isEmpty ? AppText.ui("尚未准备模型。首次下载从 Hugging Face 获取模型和分词器，需要联网及磁盘空间；不会上传音频。", "The model is not ready. The first download retrieves the model and tokenizer from Hugging Face and requires internet access and disk space.", "モデルの準備ができていません。初回は Hugging Face からモデルとトークナイザーを取得するため、ネット接続と空き容量が必要です。") : AppText.ui("已配置：", "Configured: ", "設定済み：") + session.whisperModelFolder)
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if preparing {
                    ProgressView(value: progress)
                    Button(AppText.ui("取消准备", "Cancel Preparation", "準備をキャンセル")) { operation?.cancel() }
                }
                if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled) }
            }
        }
        .task { manager.refresh() }
        .sheet(isPresented: $showsModelManagement) { modelManagementSheet }
        .onChange(of: session.whisperModel) { _, _ in message = "" }
        .onDisappear { operation?.cancel() }
    }

    private var managedModelStatus: some View {
        Group {
            if let bytes = manager.installed[managedID] {
                Label(AppText.ui("已下载 · ", "Downloaded · ", "ダウンロード済み · ") + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text(AppText.ui("尚未下载 · ", "Not downloaded · ", "未ダウンロード · ") + selectedManagedModel.downloadSize)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var modelManagementSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Label(modelManagementTitle, systemImage: "gearshape")
                        .font(.title2.weight(.semibold))
                    Spacer(minLength: 8)
                    Button(action: importExistingModel) {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .disabled(locked)
                    .help(importModelTitle)
                    .accessibilityLabel(importModelTitle)
                    .accessibilityIdentifier("importManagedSpeechModel")
                }
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(selectedManagedModel.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    managedModelStatus
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            Text(AppText.ui("首次下载需要联网及磁盘空间。识别在本机进行，音频留在这台 Mac。", "The initial download needs internet access and disk space. Recognition runs on this Mac, where the audio stays.", "初回のダウンロードにはインターネット接続と空き容量が必要です。音声はこの Mac 内で認識・処理されます。"))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { managedModelActions }
                VStack(alignment: .leading, spacing: 8) { managedModelActions }
            }

            if manager.isBusy {
                if let value = manager.progress { ProgressView(value: value) }
                else { ProgressView().controlSize(.small) }
                Button(AppText.ui("取消操作", "Cancel Operation", "処理をキャンセル")) { manager.cancel() }
            }
            if manager.messageModelID == managedID && !manager.message.isEmpty {
                Text(manager.message).font(.caption).textSelection(.enabled)
            }

            Button(AppText.ui("关闭", "Close", "閉じる")) { showsModelManagement = false }
                .keyboardShortcut(.cancelAction)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(24)
        .frame(width: 460)
        .alert(AppText.ui("删除所选识别模型？之后需要重新下载才能使用。", "Delete the selected recognition model? You will need to download it again to use it.", "選択した認識モデルを削除しますか？再び使うにはダウンロードが必要です。"), isPresented: $confirmsDeletion) {
            Button(AppText.ui("取消", "Cancel", "キャンセル"), role: .cancel) {}
            Button(AppText.ui("删除模型", "Delete Model", "モデルを削除"), role: .destructive) {
                let id = managedID
                Task { await manager.delete(id) }
            }
        }
    }

    @ViewBuilder
    private var managedModelActions: some View {
        let isInstalled = manager.installed[managedID] != nil
        Button(isInstalled ? AppText.ui("检查与补齐", "Verify and Repair", "確認して修復") : AppText.ui("下载模型", "Download Model", "モデルをダウンロード")) {
            let id = managedID
            Task { await manager.download(id) }
        }
        .disabled(locked)

        if isInstalled {
            let deleteTitle = AppText.ui("删除模型", "Delete Model", "モデルを削除")
            Button(role: .destructive) {
                confirmsDeletion = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(AirTranslateDesign.Palette.danger)
            }
            .tint(AirTranslateDesign.Palette.danger)
            .disabled(locked)
            .help(deleteTitle)
            .accessibilityLabel(deleteTitle)

            Button(AppText.ui("打开模型文件夹", "Open Model Folder", "モデルフォルダを開く")) {
                NSWorkspace.shared.open(ManagedASRRuntime.data)
            }
            .accessibilityIdentifier("openManagedSpeechModelFolder")
        }
    }

    private var importModelTitle: String {
        AppText.ui("导入已有模型…", "Import Existing Model…", "既存モデルを読み込む…")
    }

    private func importExistingModel() {
        let id = managedID
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = AppText.ui("导入", "Import", "読み込む")
        panel.message = AppText.ui("选择旧版 NemotronTrial 文件夹。只导入模型文件，不运行旧目录中的程序。", "Choose the previous NemotronTrial folder to import its model files.", "モデルファイルを読み込むには、以前の NemotronTrial フォルダを選択してください。")
        let previousFolder = session.nemotronRuntimeFolder
        if !previousFolder.isEmpty && FileManager.default.fileExists(atPath: previousFolder + "/.runtime/models") {
            panel.directoryURL = URL(fileURLWithPath: previousFolder, isDirectory: true)
        }
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task { await manager.importOld(id, folder: folder.path) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = AppText.ui("请选择包含 AudioEncoder、TextDecoder 和 MelSpectrogram 的 WhisperKit Core ML 模型文件夹。LM Studio 的 MLX 模型不能用于此处。", "Choose a WhisperKit Core ML folder containing AudioEncoder, TextDecoder, and MelSpectrogram.", "AudioEncoder、TextDecoder、MelSpectrogram を含む WhisperKit Core ML モデルのフォルダを選択してください。")
        if panel.runModal() == .OK, let folder = panel.url {
            guard WhisperModelFiles.isUsable(folder: folder, model: session.whisperModel) else {
                message = AppText.ui("该文件夹与当前模型不一致，或模型文件不完整。请选择对应模型文件夹，或下载并准备。", "This folder does not match the selected model or is missing files. Choose the correct folder or download the model.", "フォルダが選択したモデルに対応していないか、必要なファイルがありません。正しいフォルダを選ぶか、モデルをダウンロードしてください。"); return
            }
            session.whisperModelFolder = folder.path
            message = AppText.ui("已选择文件夹；开始识别时会验证并加载，分词器首次准备仍可能需要联网。", "The folder is selected. The model will be verified and loaded when recognition starts. Initial tokenizer setup may need internet access.", "フォルダを選択しました。認識開始時にモデルを検証して読み込みます。初回のトークナイザー準備にはネット接続が必要な場合があります。")
        }
    }
    private func prepare() {
        let model = session.whisperModel
        let base = session.whisperModelsDirectory
        preparing = true; session.isPreparingWhisperModel = true; progress = 0; message = AppText.ui("正在下载并准备模型。首次 Core ML 加载可能较慢…", "Downloading and preparing the model. The first Core ML load may take a while…", "モデルをダウンロードして準備中です。Core ML の初回読み込みには時間がかかる場合があります…")
        operation = Task { @MainActor in
            defer { preparing = false; session.isPreparingWhisperModel = false }
            do {
                let folder = try await WhisperKitSpeechTranscriber.prepare(model: model, base: base) { value in
                    Task { @MainActor in progress = value }
                }
                try Task.checkCancellation()
                guard session.whisperModel == model else { return }
                session.whisperModelFolder = folder
                message = AppText.ui("模型及分词器准备完成，可以开始识别。", "The model and tokenizer are ready.", "モデルとトークナイザーの準備ができました。")
            } catch is CancellationError { message = AppText.ui("已取消准备。", "Preparation cancelled.", "準備をキャンセルしました。") }
            catch { message = AppText.ui("模型准备失败：", "Model preparation failed: ", "モデルの準備に失敗しました：") + error.localizedDescription }
        }
    }
}
