import SwiftUI

private let indexTranslateModelID = "index-translate-9b"
private let indexTranslateModelName = "Index-Translate 9B"

struct LocalTranslationSettingsView: View {
    @Bindable var session: TranslationSessionStore
    let isOnlineIndex: Bool
    let onManageSpeechModel: () -> Void
    @State private var showingConfiguration = false
    @State private var showingDiagnostics = false
    @State private var replayMessage = ""
    @State private var message = ""
    @State private var isWorking = false
    @State private var operation: Task<Void, Never>?
    private var locked: Bool { session.isRunning || session.isStarting || isWorking }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WhisperRecognitionSettingsView(session: session, isOnlineIndex: isOnlineIndex, onManageModel: onManageSpeechModel)
            if !isOnlineIndex {
                SettingsControlRow(title: AppText.ui("本体模型 · 翻译引擎", "Local Mode · Translation Engine", "ローカルモード・翻訳エンジン"), detail: AppText.ui("先由选定的本地引擎识别语音，再选择译文的处理方式。", "The selected local engine recognizes speech. Choose how to translate it.", "選択したローカルエンジンで音声を認識します。翻訳方法を選んでください。"), systemImage: "character.bubble", controlBelowLabel: true) {
                    Picker(AppText.ui("翻译引擎", "Translation Engine", "翻訳エンジン"), selection: Binding(
                        get: { session.localTranslation.enabled },
                        set: { enabled in
                            message = ""
                            if enabled { showingConfiguration = true }
                            else { session.enableLocalTranslation(false) }
                        }
                    )) {
                        if PlatformSupport.supportsAppleSpeech { Text(AppText.ui("Apple 翻译", "Apple Translation", "Apple 翻訳")).tag(false) }
                        Text(AppText.ui("本地模型翻译", "Local Model Translation", "ローカルモデル翻訳")).tag(true)
                    }
                    .pickerStyle(.menu).labelsHidden().fixedSize(horizontal: true, vertical: false).disabled(locked)
                }
            }
            if isOnlineIndex || session.localTranslation.enabled {
                if isOnlineIndex {
                    Text(AppText.localized(
                        english: "Translation Model",
                        korean: "번역 모델",
                        japanese: "翻訳モデル",
                        chineseSimplified: "翻译模型"
                    ))
                    .font(AirTranslateDesign.Typography.sectionLabel)
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.leading, settingsLabelIndent)
                    .padding(.top, 10)
                } else {
                    let correctionTitle = AppText.ui("跨段回看纠错", "Correct earlier captions", "前の字幕を文脈で修正")
                    SettingsControlRow(
                        title: correctionTitle,
                        detail: AppText.ui("翻译空闲时用后文纠正近期字幕中的同音词。", "Use later context to correct homophones in recent captions while translation is idle.", "翻訳の待機中に、後続の文脈から直近の字幕の同音異義語を修正します。"),
                        systemImage: "text.badge.checkmark",
                        showsSeparator: false,
                        controlBelowLabel: true
                    ) {
                        Toggle(correctionTitle, isOn: $session.contextualCaptionCorrectionEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .tint(AirTranslateDesign.Palette.accent)
                            .disabled(locked)
                            .accessibilityLabel(correctionTitle)
                            .accessibilityIdentifier("contextualCaptionCorrectionToggle")
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(activeModelName)
                                .font(.headline).textSelection(.enabled)
                            Text(session.localTranslation.activeBaseURL).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            if isOnlineIndex {
                                Text(AppText.ui("语音在本机识别，待译字幕文字发送到哔哩哔哩。", "Speech is recognized on this Mac. Caption text is sent to Bilibili for translation.", "音声認識はこの Mac で行い、翻訳対象の字幕テキストは Bilibili に送信します。"))
                                    .font(.caption).foregroundStyle(.secondary)
                                if session.localRecognitionEngine == "whisper" {
                                    Text(AppText.ui("WhisperKit 模型在「本体模型」下载和管理。",
                                        "Manage WhisperKit models in Local Mode.",
                                        "WhisperKit モデルは「ローカルモード」で管理します。"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Text(LocalTranslationAPIKeyStore.hasAPIKey() ? AppText.ui("本地服务密钥：已保存", "Local service key: Saved", "ローカルサービスのキー：保存済み") : AppText.ui("本地服务密钥：未配置（无认证）", "Local service key: None", "ローカルサービスのキー：未設定"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if !isOnlineIndex {
                            Button(AppText.ui("配置…", "Configure…", "設定…")) { showingConfiguration = true }.disabled(locked)
                        }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) {
                            diagnosticActions
                            Spacer(minLength: 16)
                            languageSummary
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            ViewThatFits(in: .horizontal) {
                                diagnosticActions
                                VStack(alignment: .leading, spacing: 8) {
                                    diagnosticButtons
                                }
                            }
                            languageSummary
                        }
                    }
                    .disabled(locked || session.localTranslation.activeModelID.isEmpty || session.sourceLanguage == session.targetLanguage)
                    if !message.isEmpty {
                        Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .padding(.leading, settingsLabelIndent)
                .padding(.top, isOnlineIndex ? 0 : 10)
                .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showingConfiguration) {
            LocalTranslationConfigurationSheet(session: session)
        }
        .sheet(isPresented: $showingDiagnostics) {
            VStack(alignment: .leading, spacing: 18) {
                Text(AppText.ui("实际播放延迟诊断", "Caption Latency Diagnostics", "字幕の遅延診断")).font(.title2.bold())
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(session.latencySummary()).font(.callout.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(maxHeight: 420)
                if !replayMessage.isEmpty { Text(replayMessage).font(.callout).textSelection(.enabled) }
                HStack {
                    Button(AppText.ui("文字增量回放", "Text Update Replay", "テキスト更新を再生"), action: runReplay).disabled(isWorking || session.isRunning || session.isStarting)
                    Button(AppText.ui("清空样本", "Clear Samples", "サンプルを消去")) { session.captionLatencyReadings.removeAll() }
                    Button(AppText.ui("复制报告", "Copy Report", "レポートをコピー")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.latencySummary(), forType: .string)
                    }
                    Spacer()
                    Button(AppText.ui("关闭", "Close", "閉じる")) { operation?.cancel(); showingDiagnostics = false }
                }
            }.padding(24).frame(width: 640)
        }
        .onChange(of: session.localTranslation) { _, _ in message = "" }
        .onChange(of: session.sourceLanguage) { _, _ in message = "" }
        .onChange(of: session.targetLanguage) { _, _ in message = "" }
        .onDisappear { operation?.cancel() }
    }

    private var diagnosticActions: some View {
        HStack(spacing: 8) {
            diagnosticButtons
        }
    }

    @ViewBuilder
    private var diagnosticButtons: some View {
        Button(AppText.ui("测试翻译", "Test Translation", "翻訳をテスト")) { run(longSample: false) }
        Button(AppText.ui("测试长句翻译", "Test Long Text", "長文翻訳をテスト")) { run(longSample: true) }
        Button(AppText.ui("延迟诊断", "Latency Diagnostics", "遅延診断")) { showingDiagnostics = true }
        if isWorking { ProgressView().controlSize(.small) }
    }

    private var languageSummary: some View {
        Text(session.languageSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var activeModelName: String {
        let modelID = session.localTranslation.activeModelID
        if modelID == indexTranslateModelID { return indexTranslateModelName }
        return modelID.isEmpty ? AppText.ui("尚未配置本地模型", "No local model configured", "ローカルモデルが未設定です") : modelID
    }

    private func runReplay() {
        guard !locked else { return }
        let configuration = session.localTranslation
        isWorking = true; replayMessage = AppText.ui("正在进行固定文字回放（不含音频识别）…", "Replaying sample text updates…", "サンプルテキストの更新を再生中…")
        operation = Task { @MainActor in
            defer { isWorking = false }
            do {
                let key = configuration.usesOnlineIndex ? nil : try LocalTranslationAPIKeyStore.readAPIKey()
                let fixtures: [(String, [String])] = [
                    ("en-US", ["Today we discuss live captions.", "Today we discuss live captions. They should",
                               "Today we discuss live captions. They should appear while the speaker continues.",
                               "Today we discuss live captions. They should appear while the speaker continues. Earlier sentences must remain visible."]),
                    ("ja-JP", ["今日は字幕の表示について話します。", "今日は字幕の表示について話します。話している途中でも",
                               "今日は字幕の表示について話します。話している途中でも、言葉をすぐに表示することが大切です。",
                               "今日は字幕の表示について話します。話している途中でも、言葉をすぐに表示することが大切です。前の文章は残し、新しい部分だけを翻訳します。"])
                ]
                var reports: [String] = []
                for (language, updates) in fixtures {
                    let identity = "replay:" + UUID().uuidString
                    let started = ProcessInfo.processInfo.systemUptime
                    var first: TimeInterval?
                    var final = ""
                    let previousReports = reports
                    for update in updates {
                        try Task.checkCancellation()
                        final = try await IncrementalLocalTranslator.shared.translate(update, identity: identity,
                            source: language, target: "zh-CN", configuration: configuration, apiKey: key,
                            progress: { partial in
                                if !partial.isEmpty && first == nil { first = ProcessInfo.processInfo.systemUptime }
                                replayMessage = previousReports.joined(separator: "\n") + "\n" + language + AppText.ui(" 回放中：\n", " replaying:\n", " 再生中：\n") + partial
                            })
                    }
                    let stats = await IncrementalLocalTranslator.shared.statistics(identity: identity,
                        source: language, target: "zh-CN", configuration: configuration)
                    let baseline = updates.reduce(0) { $0 + $1.count }
                    let ended = ProcessInfo.processInfo.systemUptime
                    reports.append(String(format: AppText.ui("%@ · 首译 %.2f 秒 · 4 次修订完成 %.2f 秒 · 源文字提交 %d/%d 字 · 复用 %d 个前缀片段\n%@", "%@ · First translation %.2f s · 4 updates in %.2f s · Sent %d/%d source characters · Reused %d chunks\n%@", "%@ · 初回訳文 %.2f 秒 · 4 回の更新を %.2f 秒で完了 · 原文 %d/%d 文字を送信 · %d 区間を再利用\n%@"), language, (first ?? ended) - started, ended - started, stats.0, baseline, stats.1, final))
                }
                replayMessage = reports.joined(separator: "\n\n") + AppText.ui("\n\n仅为文字修订回放。字符统计不含额外参考上下文，不代表模型 token 或真实音频延迟。", "\n\nText replay only. Character counts exclude reference context and do not measure tokens or audio latency.", "\n\nテキストの更新のみ再生します。文字数に参照情報は含まれず、トークン数や音声遅延とは異なります。")
            } catch is CancellationError { replayMessage = AppText.ui("已取消回放。", "Replay cancelled.", "再生をキャンセルしました。") }
            catch { replayMessage = error.localizedDescription }
        }
    }

    private func run(longSample: Bool) {
        let configuration = session.localTranslation
        let source = session.sourceLanguage
        let target = session.targetLanguage
        isWorking = true
        message = AppText.ui("正在测试 \(source.localizedTitle) → \(target.localizedTitle)…", "Testing \(source.localizedTitle) → \(target.localizedTitle)…", "\(source.localizedTitle) → \(target.localizedTitle) をテスト中…")
        operation = Task { @MainActor in
            defer { isWorking = false }
            do {
                let startedAt = ProcessInfo.processInfo.systemUptime
                var firstTextAt: TimeInterval?
                let result = try await LocalTranslationService.shared.translate(
                    LocalTranslationTestText.sample(languageID: source.id, long: longSample),
                    source: source.id, target: target.id, configuration: configuration,
                    apiKey: configuration.usesOnlineIndex ? nil : LocalTranslationAPIKeyStore.readAPIKey(),
                    progress: { partial in
                        guard !partial.isEmpty else { return }
                        if firstTextAt == nil { firstTextAt = ProcessInfo.processInfo.systemUptime }
                        message = AppText.ui("正在翻译（流式）：\n\(partial)", "Translating (streaming):\n\(partial)", "翻訳中（ストリーミング）：\n\(partial)")
                    }
                )
                guard !Task.isCancelled, configuration == session.localTranslation,
                      source == session.sourceLanguage, target == session.targetLanguage else { return }
                let completedAt = ProcessInfo.processInfo.systemUptime
                let firstSeconds = (firstTextAt ?? completedAt) - startedAt
                message = String(format: AppText.ui("测试成功 · 首段译文 %.2f 秒 · 全部完成 %.2f 秒\n", "Test passed · First translation %.2f s · Complete %.2f s\n", "テスト成功 · 初回訳文 %.2f 秒 · 完了 %.2f 秒\n"), firstSeconds, completedAt - startedAt) + result
            } catch is CancellationError { message = AppText.ui("已取消。", "Cancelled.", "キャンセルしました。") }
            catch { message = error.localizedDescription }
        }
    }
}

private struct LocalTranslationConfigurationSheet: View {
    @Bindable var session: TranslationSessionStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: LocalTranslationConfiguration
    @State private var models: [String] = []
    @State private var keyText = ""
    @State private var pendingKey: KeyChange = .unchanged
    @State private var message = ""
    @State private var isReading = false
    @State private var operation: Task<Void, Never>?
    private enum KeyChange { case unchanged, save(String), delete }
    private var locked: Bool { session.isRunning || session.isStarting || isReading }

    init(session: TranslationSessionStore) {
        self.session = session
        var configuration = session.localTranslation
        configuration.onlineIndex = nil
        _draft = State(initialValue: configuration)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppText.ui("配置本地模型翻译", "Configure Local Model Translation", "ローカルモデル翻訳の設定")).font(.title2.bold())
                Text(AppText.ui("选定的本地引擎识别语音，本机服务负责翻译。配置和密钥更改在点击「保存配置」后生效。", "The selected engine recognizes speech, and the local server translates it. Save the configuration to apply your changes.", "選択したエンジンで音声を認識し、ローカルサービスで翻訳します。「設定を保存」で変更を適用します。"))
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(AppText.ui("服务地址", "Server Address", "サーバーアドレス")).font(.headline)
                TextField("http://localhost:1235/v1", text: $draft.baseURL).textFieldStyle(.roundedBorder)
                    .onChange(of: draft.baseURL) { _, _ in models = []; message = "" }
            }.disabled(locked)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(AppText.ui("模型", "Model", "モデル")).font(.headline)
                    Spacer()
                    Button(AppText.ui("读取模型列表", "Fetch Models", "モデル一覧を取得"), action: readModels)
                    if isReading { ProgressView().controlSize(.small) }
                }
                Picker(AppText.ui("选择模型", "Select Model", "モデルを選択"), selection: $draft.modelID) {
                    Text(AppText.ui("请选择模型", "Choose a model", "モデルを選んでください")).tag("")
                    Text(indexTranslateModelName).tag(indexTranslateModelID)
                    if !draft.modelID.isEmpty && draft.modelID != indexTranslateModelID && !models.contains(draft.modelID) {
                        Text(draft.modelID).tag(draft.modelID)
                    }
                    ForEach(models.filter { $0 != indexTranslateModelID }, id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                TextField(AppText.ui("模型 ID", "Model ID", "モデル ID"), text: $draft.modelID).textFieldStyle(.roundedBorder)
                if draft.modelID == indexTranslateModelID {
                    Text(AppText.ui("需要在 LM Studio 下载此模型并开启本地 API。", "Download this model and enable the local API in LM Studio.", "LM Studio でモデルをダウンロードし、ローカル API を有効にしてください。"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.disabled(locked)
            VStack(alignment: .leading, spacing: 8) {
                Text(AppText.ui("本地服务密钥（可选）", "Local Service Key (Optional)", "ローカルサービスのキー（任意）")).font(.headline)
                SecureField(AppText.ui("无认证时留空；已保存的密钥不会回显", "Leave blank if authentication is disabled", "認証が不要な場合は空欄のままにします"), text: $keyText).textFieldStyle(.roundedBorder)
                HStack {
                    Button(AppText.ui("保存密钥", "Save Key", "キーを保存")) {
                        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty, key.utf8.count <= 16_384,
                              key.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7e }) else {
                            message = AppText.ui("请输入有效的本地服务密钥。", "Enter a valid local service key.", "有効なローカルサービスのキーを入力してください。"); return
                        }
                        pendingKey = .save(key); keyText = ""
                        message = AppText.ui("密钥已暂存，保存配置后生效。", "The key will be applied when you save the configuration.", "設定を保存するとキーが適用されます。")
                    }.disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button(AppText.ui("删除密钥", "Delete Key", "キーを削除")) { pendingKey = .delete; keyText = ""; message = AppText.ui("已标记删除密钥，保存配置后生效。", "The key will be removed when you save the configuration.", "設定を保存するとキーが削除されます。") }
                    Spacer()
                    Text(keyStatus).font(.caption).foregroundStyle(.secondary)
                }
            }.disabled(locked)
            if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Button(AppText.ui("取消", "Cancel", "キャンセル")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(AppText.ui("保存配置", "Save Configuration", "設定を保存"), action: save).keyboardShortcut(.defaultAction).disabled(locked)
            }
        }
        .padding(24).frame(width: 560)
        .onDisappear { operation?.cancel() }
    }

    private var keyStatus: String {
        switch pendingKey {
        case .unchanged: LocalTranslationAPIKeyStore.hasAPIKey() ? AppText.ui("已保存", "Saved", "保存済み") : AppText.ui("无认证", "No authentication", "認証なし")
        case .save: AppText.ui("待保存", "Pending save", "保存待ち")
        case .delete: AppText.ui("待删除", "Pending deletion", "削除待ち")
        }
    }
    private func effectiveKey() throws -> String? {
        switch pendingKey {
        case .unchanged: try LocalTranslationAPIKeyStore.readAPIKey()
        case let .save(key): key
        case .delete: nil
        }
    }
    private func readModels() {
        let configuration = draft
        isReading = true; message = AppText.ui("正在读取模型列表…", "Fetching models…", "モデル一覧を取得中…")
        operation = Task { @MainActor in
            defer { isReading = false }
            do {
                models = try await LocalTranslationService.shared.models(configuration: configuration, apiKey: effectiveKey())
                message = models.isEmpty ? AppText.ui("服务没有返回模型。", "The server returned no models.", "サーバーからモデルが返されませんでした。") : AppText.ui("请选择用于翻译的聊天模型。", "Choose a chat model for translation.", "翻訳に使うチャットモデルを選んでください。")
            } catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }
    private func save() {
        guard !locked else { return }
        do {
            _ = try draft.validatedBaseURL(); try draft.validateModel()
            if !keyText.isEmpty { message = AppText.ui("请先点击「保存密钥」，或清空未保存的密钥输入。", "Click Save Key or clear the unsaved key.", "「キーを保存」を押すか、未保存の入力を消去してください。"); return }
            switch pendingKey {
            case .unchanged: break
            case let .save(key): try LocalTranslationAPIKeyStore.saveAPIKey(key)
            case .delete: try LocalTranslationAPIKeyStore.deleteAPIKey()
            }
            session.localTranslation = draft
            session.enableLocalTranslation(true)
            dismiss()
        } catch { message = error.localizedDescription }
    }
}

private enum LocalTranslationTestText {
    static func sample(languageID: String, long: Bool) -> String {
        let texts: (String, String)
        switch languageID {
        case "ja-JP": texts = ("今日はいい天気ですね。", "音楽を作るときには、歌詞の意味だけでなく言葉のリズムも大切です。自然な響きになるよう何度も声に出して確かめます。新しい表現を試すときは、いつもの歌い方にこだわりすぎないようにしています。録音を聴き直すと、小さな違いに気づくことがあります。最後に曲全体の流れを確認して、聴く人に気持ちが伝わる形に仕上げます。")
        case "zh-CN": texts = ("今天天气真好。", "创作音乐时，除了歌词的含义，语言的节奏也很重要。我会反复朗读，确认声音是否自然。尝试新的表达时，我尽量不局限于平时的唱法。重新听录音时，常常能发现细微的差别。最后还要检查整首歌的结构，让情感自然地传达给听众。")
        case "ko-KR": texts = ("오늘은 날씨가 좋네요.", "음악을 만들 때는 가사의 뜻뿐 아니라 말의 리듬도 중요합니다. 자연스럽게 들리는지 여러 번 소리 내어 확인합니다. 새로운 표현을 시도할 때는 익숙한 방식에만 머물지 않으려고 합니다. 녹음을 다시 들으면 작은 차이를 발견할 수 있습니다. 마지막으로 곡 전체의 흐름을 확인합니다.")
        case "es-ES": texts = ("Hoy hace buen tiempo.", "Al crear música, no solo importa el significado de las letras, sino también el ritmo de las palabras. Leo el texto en voz alta para comprobar que suena natural. Cuando pruebo una expresión nueva, intento evitar las costumbres de siempre. Al escuchar la grabación de nuevo, descubro pequeños detalles. Por último, reviso la estructura de toda la canción.")
        case "fr-FR": texts = ("Il fait beau aujourd’hui.", "Quand je crée de la musique, le rythme des mots compte autant que le sens des paroles. Je lis le texte à voix haute pour vérifier que le résultat est naturel. En essayant de nouvelles expressions, je cherche à dépasser mes habitudes. Une nouvelle écoute révèle parfois de petits détails. Enfin, je vérifie la structure de toute la chanson.")
        case "de-DE": texts = ("Heute ist schönes Wetter.", "Beim Schreiben von Musik ist neben der Bedeutung auch der Rhythmus der Worte wichtig. Ich lese den Text laut vor, um den natürlichen Klang zu prüfen. Bei neuen Formulierungen versuche ich, vertraute Muster zu verlassen. Beim erneuten Anhören fallen mir oft kleine Unterschiede auf. Zum Schluss überprüfe ich den Aufbau des ganzen Liedes.")
        default: texts = ("The weather is lovely today.", "When creating music, the rhythm of the words matters as much as their meaning. I read the lyrics aloud to check that they sound natural. When trying a new expression, I avoid relying only on familiar habits. Listening to the recording again often reveals small differences. Finally, I review the structure of the whole song so that its feeling reaches the listener.")
        }
        return long ? texts.1 : texts.0
    }
}
