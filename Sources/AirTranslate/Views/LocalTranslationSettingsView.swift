import SwiftUI

struct LocalTranslationSettingsView: View {
    @Bindable var session: TranslationSessionStore
    @State private var showingConfiguration = false
    @State private var showingDiagnostics = false
    @State private var replayMessage = ""
    @State private var message = ""
    @State private var isWorking = false
    @State private var operation: Task<Void, Never>?
    private var locked: Bool { session.isRunning || session.isStarting || isWorking }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WhisperRecognitionSettingsView(session: session)
            SettingsControlRow(title: "本地模式 · 翻译引擎", detail: "先由选定的本地引擎识别语音，再选择译文的处理方式。", systemImage: "character.bubble") {
                Picker("翻译引擎", selection: Binding(
                    get: { session.localTranslation.enabled },
                    set: { local in
                        message = ""
                        if local { showingConfiguration = true }
                        else { session.enableLocalTranslation(local) }
                    }
                )) {
                    if PlatformSupport.supportsAppleSpeech { Text("Apple 翻译").tag(false) }
                    Text("本地模型翻译").tag(true)
                }
                .labelsHidden().frame(width: 220).disabled(locked)
            }
            if session.localTranslation.enabled {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(session.localTranslation.modelID.isEmpty ? "尚未配置本地模型" : session.localTranslation.modelID)
                                .font(.headline).textSelection(.enabled)
                            Text(session.localTranslation.baseURL).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(LocalTranslationAPIKeyStore.hasAPIKey() ? "本地服务密钥：已保存" : "本地服务密钥：未配置（无认证）")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("配置…") { showingConfiguration = true }.disabled(locked)
                    }
                    HStack {
                        Button("测试翻译") { run(longSample: false) }
                        Button("测试长句翻译") { run(longSample: true) }
                        if isWorking { ProgressView().controlSize(.small) }
                        Button("延迟诊断") { showingDiagnostics = true }
                        Spacer()
                        Text(session.languageSummary).font(.caption).foregroundStyle(.secondary)
                    }
                    .disabled(locked || session.localTranslation.modelID.isEmpty || session.sourceLanguage == session.targetLanguage)
                    if !message.isEmpty {
                        Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .sheet(isPresented: $showingConfiguration) {
            LocalTranslationConfigurationSheet(session: session)
        }
        .sheet(isPresented: $showingDiagnostics) {
            VStack(alignment: .leading, spacing: 18) {
                Text("实际播放延迟诊断").font(.title2.bold())
                ScrollView {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(session.latencySummary()).font(.callout.monospaced()).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.frame(maxHeight: 420)
                if !replayMessage.isEmpty { Text(replayMessage).font(.callout).textSelection(.enabled) }
                HStack {
                    Button("文字增量回放", action: runReplay).disabled(isWorking || session.isRunning || session.isStarting)
                    Button("清空样本") { session.captionLatencyReadings.removeAll() }
                    Button("复制报告") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(session.latencySummary(), forType: .string)
                    }
                    Spacer()
                    Button("关闭") { operation?.cancel(); showingDiagnostics = false }
                }
            }.padding(24).frame(width: 640)
        }
        .onChange(of: session.localTranslation) { _, _ in message = "" }
        .onChange(of: session.sourceLanguage) { _, _ in message = "" }
        .onChange(of: session.targetLanguage) { _, _ in message = "" }
        .onDisappear { operation?.cancel() }
    }

    private func runReplay() {
        guard !locked else { return }
        let configuration = session.localTranslation
        isWorking = true; replayMessage = "正在进行固定文字回放（不含音频识别）…"
        operation = Task { @MainActor in
            defer { isWorking = false }
            do {
                let key = try LocalTranslationAPIKeyStore.readAPIKey()
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
                                replayMessage = previousReports.joined(separator: "\n") + "\n" + language + " 回放中：\n" + partial
                            })
                    }
                    let stats = await IncrementalLocalTranslator.shared.statistics(identity: identity,
                        source: language, target: "zh-CN", configuration: configuration)
                    let baseline = updates.reduce(0) { $0 + $1.count }
                    let ended = ProcessInfo.processInfo.systemUptime
                    reports.append(String(format: "%@ · 首译 %.2f 秒 · 4 次修订完成 %.2f 秒 · 源文字提交 %d/%d 字 · 复用 %d 个前缀片段\n%@", language, (first ?? ended) - started, ended - started, stats.0, baseline, stats.1, final))
                }
                replayMessage = reports.joined(separator: "\n\n") + "\n\n仅为文字修订回放。字符统计不含额外参考上下文，不代表模型 token 或真实音频延迟。"
            } catch is CancellationError { replayMessage = "已取消回放。" }
            catch { replayMessage = error.localizedDescription }
        }
    }

    private func run(longSample: Bool) {
        let configuration = session.localTranslation
        let source = session.sourceLanguage
        let target = session.targetLanguage
        isWorking = true
        message = "正在测试 \(source.localizedTitle) → \(target.localizedTitle)…"
        operation = Task { @MainActor in
            defer { isWorking = false }
            do {
                let startedAt = ProcessInfo.processInfo.systemUptime
                var firstTextAt: TimeInterval?
                let result = try await LocalTranslationService.shared.translate(
                    LocalTranslationTestText.sample(languageID: source.id, long: longSample),
                    source: source.id, target: target.id, configuration: configuration,
                    apiKey: LocalTranslationAPIKeyStore.readAPIKey(),
                    progress: { partial in
                        guard !partial.isEmpty else { return }
                        if firstTextAt == nil { firstTextAt = ProcessInfo.processInfo.systemUptime }
                        message = "正在翻译（流式）：\n\(partial)"
                    }
                )
                guard !Task.isCancelled, configuration == session.localTranslation,
                      source == session.sourceLanguage, target == session.targetLanguage else { return }
                let completedAt = ProcessInfo.processInfo.systemUptime
                let firstSeconds = (firstTextAt ?? completedAt) - startedAt
                message = String(format: "测试成功 · 首段译文 %.2f 秒 · 全部完成 %.2f 秒\n", firstSeconds, completedAt - startedAt) + result
            } catch is CancellationError { message = "已取消。" }
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
        _draft = State(initialValue: session.localTranslation)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("配置本地模型翻译").font(.title2.bold())
                Text("选定的本地引擎识别语音，本机服务负责翻译。配置和密钥更改在点击「保存配置」后生效。")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("服务地址").font(.headline)
                TextField("http://localhost:1235/v1", text: $draft.baseURL).textFieldStyle(.roundedBorder)
                    .onChange(of: draft.baseURL) { _, _ in models = []; message = "" }
            }.disabled(locked)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("模型").font(.headline)
                    Spacer()
                    Button("读取模型列表", action: readModels)
                    if isReading { ProgressView().controlSize(.small) }
                }
                if !models.isEmpty {
                    Picker("选择模型", selection: $draft.modelID) {
                        Text("请选择模型").tag("")
                        if !draft.modelID.isEmpty && !models.contains(draft.modelID) { Text(draft.modelID).tag(draft.modelID) }
                        ForEach(models, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                }
                TextField("模型 ID", text: $draft.modelID).textFieldStyle(.roundedBorder)
            }.disabled(locked)
            VStack(alignment: .leading, spacing: 8) {
                Text("本地服务密钥（可选）").font(.headline)
                SecureField("无认证时留空；已保存的密钥不会回显", text: $keyText).textFieldStyle(.roundedBorder)
                HStack {
                    Button("保存密钥") {
                        let key = keyText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !key.isEmpty, key.utf8.count <= 16_384,
                              key.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7e }) else {
                            message = "请输入有效的本地服务密钥。"; return
                        }
                        pendingKey = .save(key); keyText = ""
                        message = "密钥已暂存，保存配置后生效。"
                    }.disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Button("删除密钥") { pendingKey = .delete; keyText = ""; message = "已标记删除密钥，保存配置后生效。" }
                    Spacer()
                    Text(keyStatus).font(.caption).foregroundStyle(.secondary)
                }
            }.disabled(locked)
            if !message.isEmpty { Text(message).font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
            Divider()
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存配置", action: save).keyboardShortcut(.defaultAction).disabled(locked)
            }
        }
        .padding(24).frame(width: 560)
        .onDisappear { operation?.cancel() }
    }

    private var keyStatus: String {
        switch pendingKey {
        case .unchanged: LocalTranslationAPIKeyStore.hasAPIKey() ? "已保存" : "无认证"
        case .save: "待保存"
        case .delete: "待删除"
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
        isReading = true; message = "正在读取模型列表…"
        operation = Task { @MainActor in
            defer { isReading = false }
            do {
                models = try await LocalTranslationService.shared.models(configuration: configuration, apiKey: effectiveKey())
                message = models.isEmpty ? "服务没有返回模型。" : "请选择用于翻译的聊天模型。"
            } catch is CancellationError { }
            catch { message = error.localizedDescription }
        }
    }
    private func save() {
        guard !locked else { return }
        do {
            _ = try draft.validatedBaseURL(); try draft.validateModel()
            if !keyText.isEmpty { message = "请先点击「保存密钥」，或清空未保存的密钥输入。"; return }
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
