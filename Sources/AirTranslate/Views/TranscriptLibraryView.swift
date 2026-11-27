import AppKit
import SwiftUI
import AirTranslateCore

struct TranscriptLibraryView: View {
    @Bindable var session: TranslationSessionStore
    let subtitleCache: VideoSubtitleCache
    var mediaTranslator: VideoSubtitleTranslator? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDeleteSelectedConfirmationPresented = false
    @State private var isDeleteAllConfirmationPresented = false
    @State private var isCopyFeedbackVisible = false
    @State private var copyFeedbackToken = 0
    @State private var isLoadingMediaHistory = true
    @State private var mediaHistory: [VideoSubtitleHistoryEntry] = []
    @State private var selectedMedia: VideoSubtitleHistoryEntry?
    @State private var pendingExport: VideoSubtitleHistoryEntry?
    @State private var mediaError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, AirTranslateDesign.Spacing.lg)
                .padding(.vertical, AirTranslateDesign.Spacing.md)

            Rectangle()
                .fill(AirTranslateDesign.Palette.hairline)
                .frame(height: 1)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(
            minWidth: AirTranslateDesign.libraryMinimumWidth,
            idealWidth: AirTranslateDesign.libraryIdealWidth,
            minHeight: AirTranslateDesign.libraryMinimumHeight,
            idealHeight: AirTranslateDesign.libraryIdealHeight
        )
        .tint(AirTranslateDesign.Palette.accent)
        .background(AirTranslateDesign.Palette.canvas)
        .confirmationDialog(
            AppText.deleteSavedTranscriptConfirmation,
            isPresented: $isDeleteSelectedConfirmationPresented
        ) {
            Button(AppText.deleteSavedTranscript, role: .destructive) {
                session.deleteSelectedTranscript()
            }
            Button(AppText.cancel, role: .cancel) {}
        }
        .confirmationDialog(
            AppText.deleteAllSavedTranscriptsConfirmation,
            isPresented: $isDeleteAllConfirmationPresented
        ) {
            Button(deleteAllTitle, role: .destructive) {
                session.deleteAllSavedTranscripts()
            }
            Button(AppText.cancel, role: .cancel) {}
        }
        .alert(AppText.savedMediaSubtitles, isPresented: Binding(
            get: { mediaError != nil }, set: { if !$0 { mediaError = nil } }
        )) {
            Button(AppText.close, role: .cancel) { mediaError = nil }
        } message: {
            Text(mediaError ?? "")
        }
        .onAppear {
            ensureSelection()
        }
        .task { await loadMediaHistory() }
        .task(id: pendingExport?.id) {
            if let entry = pendingExport { await exportMedia(entry) }
        }
        .onDisappear { session.cancelSavedTitleGeneration(); session.cancelTranscriptCleanup() }
        .onChange(of: selectedAI) { _, _ in
            session.cancelSavedTitleGeneration()
            session.cancelTranscriptCleanup()
            session.savedTitleMessage = nil
        }
        .onChange(of: session.savedTranscripts.count) { _, _ in
            ensureSelection()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.sm) {
            HStack(spacing: AirTranslateDesign.Spacing.sm) {
                Image(systemName: "tray.full")
                    .font(.system(size: AirTranslateDesign.iconRegular, weight: .semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.accent)
                    .frame(width: 40, height: 40)
                    .background(
                        AirTranslateDesign.Palette.accentSoft,
                        in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xxs) {
                    Text(AppText.savedTranscripts)
                        .font(AirTranslateDesign.Typography.stageTitle)
                        .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                    Text(libraryDescription)
                        .font(AirTranslateDesign.Typography.meta)
                        .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .help(AppText.close)
                .accessibilityLabel(AppText.close)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 9) {
                    contentModeControl
                    Spacer(minLength: 12)
                    libraryActions
                }
                .frame(minWidth: 700)

                VStack(alignment: .leading, spacing: 10) {
                    contentModeControl
                    libraryActions
                }
            }
        }
    }

    private var contentModeControl: some View {
        HStack(spacing: 8) {
            Text(AppText.savedTranscriptContent)
                .font(AirTranslateDesign.Typography.sectionLabel)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)

            if session.isTranscribeOnlyMode {
                Text(session.effectiveSavedTranscriptContentMode.title)
                    .font(AirTranslateDesign.Typography.label)
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
            } else {
                Picker(AppText.savedTranscriptContent, selection: $session.savedTranscriptContentMode) {
                    ForEach(session.availableSavedTranscriptContentModes) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .tint(AirTranslateDesign.Palette.accent)
                .frame(minWidth: 210, idealWidth: 230, maxWidth: 280)
            }
        }
    }

    private var libraryActions: some View {
        HStack(spacing: 9) {
            Button {
                session.openTranscriptsFolder()
            } label: {
                Label(AppText.openSaveFolder, systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .tint(AirTranslateDesign.Palette.accent)

            Button(role: .destructive) {
                isDeleteAllConfirmationPresented = true
            } label: {
                Label(deleteAllTitle, systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(AirTranslateDesign.Palette.danger)
            .disabled(session.savedTranscripts.isEmpty)
            .help(AppText.deleteAllSavedTranscriptsHelp)
        }
    }

    private var libraryDescription: String {
        guard !mediaHistory.isEmpty else { return AppText.transcriptPersistenceDescription }
        return AppText.ui("实时记录按设置保存为 TXT。媒体字幕从本机缓存读取。",
                          "Live transcripts are saved as TXT according to your settings. Media subtitles are loaded from the local cache.",
                          "リアルタイムの記録は設定に従って TXT に保存します。メディア字幕は端末のキャッシュから読み込みます。")
    }

    private var deleteAllTitle: String {
        mediaHistory.isEmpty ? AppText.deleteAllSavedTranscripts
            : AppText.ui("删除全部 TXT", "Delete All TXT", "TXT をすべて削除")
    }

    private var libraryItems: [TranscriptLibraryItem] {
        (session.savedTranscripts.map(TranscriptLibraryItem.transcript) + mediaHistory.map(TranscriptLibraryItem.media))
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var selectedItemID: TranscriptLibraryItem.ID? {
        if let selectedMedia { return .media(selectedMedia.id) }
        return session.selectedSavedTranscriptID.map(TranscriptLibraryItem.ID.transcript)
    }

    @ViewBuilder
    private var content: some View {
        let items = libraryItems
        if items.isEmpty && isLoadingMediaHistory {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if items.isEmpty {
            VStack(spacing: AirTranslateDesign.Spacing.md) {
                AudioLevelWaveform(
                    level: nil,
                    date: .distantPast,
                    barCount: 11,
                    width: 92,
                    height: 30,
                    barWidth: 4,
                    barSpacing: 4,
                    tint: AirTranslateDesign.Palette.accent
                )

                Text(AppText.savedEmpty)
                    .font(AirTranslateDesign.Typography.stageTitle)
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                Text(AppText.transcriptPersistenceDescription)
                    .font(AirTranslateDesign.Typography.meta)
                    .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
            .padding(AirTranslateDesign.Spacing.xl)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 0) {
                transcriptList(items)
                    .frame(width: 260)

                Rectangle()
                    .fill(AirTranslateDesign.Palette.hairline)
                    .frame(width: 1)

                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func transcriptList(_ items: [TranscriptLibraryItem]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    Button {
                        select(item)
                    } label: {
                        TranscriptLibraryRow(item: item, isSelected: selectedItemID == item.id)
                            .contentShape(RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AirTranslateDesign.Spacing.sm)
        }
        .background(AirTranslateDesign.Palette.canvas)
    }

    @ViewBuilder
    private var editor: some View {
        if selectedMedia != nil || session.selectedSavedTranscript != nil {
            ScrollView(.vertical) {
                Group {
                    if let selectedMedia {
                        mediaCard(for: selectedMedia)
                    } else if let transcript = session.selectedSavedTranscript {
                        editorCard(for: transcript)
                    }
                }
                .padding(.horizontal, AirTranslateDesign.Spacing.md)
                .padding(.top, AirTranslateDesign.Spacing.sm)
                .padding(.bottom, AirTranslateDesign.Spacing.md)
            }
            .scrollBounceBehavior(.basedOnSize)
        } else {
            ContentUnavailableView(AppText.noSavedTranscriptSelected, systemImage: "doc.text")
        }
    }

    private func editorCard(for selectedTranscript: SavedTranscript) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(AppText.editSaved)
                    .font(AirTranslateDesign.Typography.stageTitle)
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                Spacer(minLength: 0)

                Button {
                    session.polishSelectedTranscriptDraft(using: selectedAI)
                } label: {
                    Label(AppText.transcriptCleanupShort, systemImage: "sparkles")
                        .font(AirTranslateDesign.Typography.meta.weight(.semibold))
                        .opacity(session.isTranscriptCleanupRunning ? 0 : 1)
                        .overlay {
                            if session.isTranscriptCleanupRunning {
                                ProgressView().controlSize(.small)
                            }
                        }
                }
                .fixedSize(horizontal: true, vertical: false)
                .disabled(!canCopyDraft || session.isTranscriptCleanupRunning || session.isGeneratingSavedTitle || session.isRunning || session.isStarting)
                .help(AppText.transcriptCleanupHelp + "\n" + selectedAIHelp)
                .accessibilityLabel(AppText.transcriptCleanupShort)
                .accessibilityValue(selectedAI.title)

                Button {
                    if copyDraftText() {
                        showCopyFeedback()
                    }
                } label: {
                    Image(systemName: isCopyFeedbackVisible ? "checkmark" : "clipboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isCopyFeedbackVisible ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textSecondary)
                        .frame(width: 26, height: 26)
                        .airTranslateInteractiveSurface(isSelected: isCopyFeedbackVisible)
                }
                .buttonStyle(AirTranslatePressButtonStyle())
                .help(isCopyFeedbackVisible ? AppText.copied : AppText.copy)
                .accessibilityLabel(AppText.copy)
                .disabled(!canCopyDraft)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppText.title).font(.headline)
                HStack(spacing: 12) {
                    TextField(AppText.ui("输入记录标题…", "Enter a transcript title…", "記録のタイトルを入力…"), text: $session.savedDraftTitle)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .accessibilityLabel(AppText.title)
                        .frame(minWidth: 120, maxWidth: .infinity)
                    Button {
                        session.generateSavedTranscriptTitle(using: selectedAI)
                    } label: {
                        Label(AppText.ui("AI 生成标题", "Generate Title with AI", "AI でタイトルを生成"), systemImage: "sparkles")
                            .opacity(session.isGeneratingSavedTitle ? 0 : 1)
                            .overlay {
                                if session.isGeneratingSavedTitle {
                                    ProgressView().controlSize(.small)
                                }
                            }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .disabled(session.isGeneratingSavedTitle || session.isTranscriptCleanupRunning || session.isRunning || session.isStarting)
                    .help(AppText.ui("使用当前选择的 AI 总结记录并生成标题，停止监听后可用。", "Use the selected AI to summarize the transcript into a title after stopping capture.", "聞き取りを停止した後、現在の AI で記録を要約してタイトルを生成します。") + "\n" + selectedAIHelp)
                    .accessibilityLabel(AppText.ui("AI 生成标题", "Generate Title with AI", "AI でタイトルを生成"))
                    .accessibilityValue(selectedAI.title)
                }
                Text(AppText.ui("保存修改时同步更新 TXT 文件名；原文和译文保留配对，重名时自动编号。", "Saving also renames the TXT files. Source and translation stay paired, and duplicate names are numbered.", "保存時に TXT ファイル名も更新します。原文と訳文の対応を保ち、同名の場合は番号を付けます。"))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(selectedTranscript.sourceFileName)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        .help(selectedTranscript.sourceFileName)
                    Button { session.revealSelectedTranscriptInFinder() } label: {
                        Label(AppText.ui("在访达中显示", "Show in Finder", "Finder に表示"), systemImage: "folder")
                    }
                }
                if let message = session.savedTitleMessage {
                    Text(message)
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 8)

            HStack {
                Button {
                    session.saveSelectedTranscriptEdits()
                } label: {
                    Label(AppText.saveEdits, systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(AirTranslateDesign.Palette.accent)
                .keyboardShortcut("s", modifiers: [.command])
                .disabled(session.isRunning || session.isStarting)

                Spacer(minLength: 0)

                Button(role: .destructive) {
                    isDeleteSelectedConfirmationPresented = true
                } label: {
                    Label(AppText.deleteSavedTranscript, systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(AirTranslateDesign.Palette.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AirTranslateDesign.Spacing.md)
        .airRaisedSurface()
    }

    private func mediaCard(for entry: VideoSubtitleHistoryEntry) -> some View {
        let source = AppText.languageTitle(for: entry.sourceLanguage, fallback: entry.sourceLanguage)
        let target = AppText.languageTitle(for: entry.targetLanguage, fallback: entry.targetLanguage)
        let input = entry.input.hasPrefix("import:") ? VideoSubtitleInput.imported : VideoSubtitleInput(rawValue: entry.input)
        let translator = entry.provider.hasPrefix("cloudflare:")
            ? VideoSubtitleTranslator.cloudflare : VideoSubtitleTranslator(rawValue: entry.provider)
        let engineNames = [input?.title, translator?.title].compactMap { $0 }.joined(separator: " · ")

        return VStack(alignment: .leading, spacing: 12) {
            Label(AppText.savedMediaSubtitles, systemImage: "play.rectangle")
                .font(AirTranslateDesign.Typography.stageTitle)
                .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(3)
                    .help(entry.title)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(source) → \(target)")
                if !engineNames.isEmpty { Text(engineNames) }
                Text(entry.updatedAt, format: .dateTime.year().month().day().hour().minute())
                if !entry.completed {
                    Text(AppText.ui("字幕未处理完，可下载已准备的部分。",
                                    "Preparation is incomplete. Captions prepared so far are available to download.",
                                    "字幕の準備は途中です。準備済みの部分をダウンロードできます。"))
                }
            }
            .font(AirTranslateDesign.Typography.meta)
            .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                pendingExport = entry
            } label: {
                Label(AppText.downloadSRT, systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .disabled(pendingExport != nil)
            .help(AppText.ui("保存本机字幕及已有译文。", "Save cached captions with any available translations.",
                             "キャッシュ内の字幕を取得済みの訳文と一緒に保存します。"))
            .accessibilityIdentifier("downloadSavedMediaSRT")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AirTranslateDesign.Spacing.md)
        .airRaisedSurface()
    }

    private func loadMediaHistory() async {
        defer { isLoadingMediaHistory = false }
        do {
            let entries = try await subtitleCache.history()
            guard !Task.isCancelled else { return }
            mediaHistory = entries
            ensureSelection()
        } catch {
            guard !Task.isCancelled else { return }
            mediaError = AppText.ui("无法读取本机媒体字幕记录。", "Could not read the local media subtitle history.",
                                    "端末のメディア字幕履歴を読み込めませんでした。")
        }
    }

    private func exportMedia(_ entry: VideoSubtitleHistoryEntry) async {
        defer {
            if !Task.isCancelled { pendingExport = nil }
        }
        let document = try? await subtitleCache.load(entry)
        guard !Task.isCancelled, selectedMedia?.id == entry.id else { return }
        guard let document else {
            mediaError = AppText.ui("此记录的本机字幕已不可用。", "Cached subtitles for this record are unavailable.",
                                    "この記録のキャッシュ字幕は利用できません。")
            return
        }
        do {
            try VideoSubtitlePreloadStore.exportSRT(document)
        } catch VideoSubtitleError.noSubtitles {
            mediaError = AppText.ui("此记录没有可下载的字幕。", "This record has no subtitles to download.",
                                    "この記録にダウンロードできる字幕はありません。")
        } catch {
            mediaError = AppText.subtitleExportFailed
        }
    }

    private var canCopyDraft: Bool {
        [session.savedDraftSourceText, session.savedDraftTranslationText].contains {
            $0.rangeOfCharacter(from: .whitespacesAndNewlines.inverted) != nil
        }
    }

    private var selectedAI: TranscriptAIModel {
        session.savedTranscriptAIModel(mediaTranslator: mediaTranslator)
    }

    private var selectedAIHelp: String {
        let model = AppText.ui("当前 AI：\(selectedAI.title)", "Selected AI: \(selectedAI.title)", "現在の AI：\(selectedAI.title)")
        guard selectedAI.sendsTextToCloud else { return model }
        return model + "\n" + AppText.ui("点击后将记录文字发送给所选服务处理，产生相应 API 用量。", "Sends transcript text to the selected service and uses its API allowance.", "記録のテキストを選択中のサービスへ送信し、API 利用量が発生します。")
    }

    private func copyDraftText() -> Bool {
        let sourceText = session.savedDraftSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translatedText = session.savedDraftTranslationText.trimmingCharacters(in: .whitespacesAndNewlines)
        let copiedText: String

        if session.selectedSavedTranscript?.isOriginalAndTranslation == true, !translatedText.isEmpty {
            copiedText = "\(AppText.original)\n\(sourceText)\n\n\(AppText.translation)\n\(translatedText)"
        } else {
            copiedText = sourceText
        }

        guard !copiedText.isEmpty else { return false }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copiedText, forType: .string)
        return true
    }

    private func showCopyFeedback() {
        copyFeedbackToken += 1
        let token = copyFeedbackToken

        withAnimation(reduceMotion ? nil : AirTranslateDesign.Motion.quick) {
            isCopyFeedbackVisible = true
        }

        Task {
            try? await Task.sleep(for: .milliseconds(900))
            await MainActor.run {
                guard token == copyFeedbackToken else { return }

                withAnimation(reduceMotion ? nil : AirTranslateDesign.Motion.quick) {
                    isCopyFeedbackVisible = false
                }
            }
        }
    }

    private func ensureSelection() {
        guard selectedMedia == nil else { return }
        if let selectedSavedTranscriptID = session.selectedSavedTranscriptID,
           session.savedTranscripts.contains(where: { $0.id == selectedSavedTranscriptID }) {
            return
        }

        if let first = libraryItems.first {
            select(first)
        }
    }

    private func select(_ item: TranscriptLibraryItem) {
        pendingExport = nil
        switch item {
        case let .transcript(transcript):
            selectedMedia = nil
            session.selectSavedTranscript(transcript.id)
        case let .media(entry):
            session.cancelSavedTitleGeneration()
            session.cancelTranscriptCleanup()
            selectedMedia = entry
        }
    }
}

private enum TranscriptLibraryItem: Identifiable {
    enum ID: Hashable {
        case transcript(String), media(String)
    }

    case transcript(SavedTranscript)
    case media(VideoSubtitleHistoryEntry)

    var id: ID {
        switch self {
        case let .transcript(record): .transcript(record.id)
        case let .media(entry): .media(entry.id)
        }
    }

    var title: String {
        switch self {
        case let .transcript(record): record.title
        case let .media(entry): entry.title
        }
    }

    var updatedAt: Date {
        switch self {
        case let .transcript(record): record.updatedAt
        case let .media(entry): entry.updatedAt
        }
    }

    var subtitle: String? {
        switch self {
        case let .transcript(record): record.isOriginalAndTranslation ? AppText.originalAndTranslation : nil
        case .media: AppText.savedMediaSubtitles
        }
    }

    func icon(selected: Bool) -> String {
        switch self {
        case let .transcript(record):
            record.isOriginalAndTranslation ? "doc.on.doc.fill" : selected ? "doc.text.fill" : "doc.text"
        case .media:
            selected ? "play.rectangle.fill" : "play.rectangle"
        }
    }
}

private struct TranscriptLibraryRow: View {
    let item: TranscriptLibraryItem
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: item.icon(selected: isSelected))
                .foregroundStyle(isSelected ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textSecondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(AirTranslateDesign.Typography.libraryRowTitle)
                    .lineLimit(2)
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                HStack(spacing: 5) {
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                    }

                    Text(item.updatedAt, style: .date)
                }
                .font(AirTranslateDesign.Typography.meta)
                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(
            isSelected ? AirTranslateDesign.Palette.accentSoft : AirTranslateDesign.Palette.transparent,
            in: RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous)
        )
    }
}
