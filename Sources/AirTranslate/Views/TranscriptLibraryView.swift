import AppKit
import SwiftUI

struct TranscriptLibraryView: View {
    @Bindable var session: TranslationSessionStore
    var mediaTranslator: VideoSubtitleTranslator? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDeleteSelectedConfirmationPresented = false
    @State private var isDeleteAllConfirmationPresented = false
    @State private var isCopyFeedbackVisible = false
    @State private var copyFeedbackToken = 0

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
            Button(AppText.deleteAllSavedTranscripts, role: .destructive) {
                session.deleteAllSavedTranscripts()
            }
            Button(AppText.cancel, role: .cancel) {}
        }
        .onAppear {
            ensureSelection()
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

                    Text(AppText.transcriptPersistenceDescription)
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
                Label(AppText.deleteAllSavedTranscripts, systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(AirTranslateDesign.Palette.danger)
            .disabled(session.savedTranscripts.isEmpty)
            .help(AppText.deleteAllSavedTranscriptsHelp)
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.savedTranscripts.isEmpty {
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
                transcriptList
                    .frame(width: 260)

                Rectangle()
                    .fill(AirTranslateDesign.Palette.hairline)
                    .frame(width: 1)

                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var transcriptList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(session.savedTranscripts) { transcript in
                    Button {
                        session.selectSavedTranscript(transcript.id)
                    } label: {
                        TranscriptLibraryRow(
                            transcript: transcript,
                            isSelected: session.selectedSavedTranscriptID == transcript.id
                        )
                        .contentShape(RoundedRectangle(cornerRadius: AirTranslateDesign.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(AirTranslateDesign.Palette.canvas)
    }

    @ViewBuilder
    private var editor: some View {
        if let selectedTranscript = session.selectedSavedTranscript {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text(AppText.editSaved)
                        .font(AirTranslateDesign.Typography.stageTitle)
                        .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                    Spacer(minLength: 0)

                    Button {
                        session.polishSelectedTranscriptDraft(using: selectedAI)
                    } label: {
                        if session.isTranscriptCleanupRunning {
                            ProgressView()
                                .controlSize(.small)
                                .frame(width: 28, height: 28)
                        } else {
                            Label(AppText.transcriptCleanupShort, systemImage: "sparkles")
                                .font(AirTranslateDesign.Typography.meta.weight(.semibold))
                        }
                    }
                    .disabled(!canCopyDraft || session.isTranscriptCleanupRunning || session.isGeneratingSavedTitle || session.isRunning || session.isStarting)
                    .help(AppText.transcriptCleanupHelp)
                    .accessibilityLabel(AppText.transcriptCleanupShort)

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

                Text(AppText.ui("当前 AI：\(selectedAI.title)", "Selected AI: \(selectedAI.title)", "現在の AI：\(selectedAI.title)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if selectedAI.sendsTextToCloud {
                    Text(AppText.ui("点击 AI 按钮后，将记录文字发送给当前所选服务处理，产生相应 API 用量。", "AI actions send transcript text to the selected service and use its API allowance.", "AI ボタンを押すと、記録のテキストを現在のサービスへ送信し、API 利用量が発生します。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(AppText.title).font(.headline)
                    HStack(spacing: 12) {
                        TextField(AppText.ui("输入记录标题…", "Enter a transcript title…", "記録のタイトルを入力…"), text: $session.savedDraftTitle)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                            .accessibilityLabel(AppText.title)
                        Button {
                            session.generateSavedTranscriptTitle(using: selectedAI)
                        } label: {
                            if session.isGeneratingSavedTitle { ProgressView().controlSize(.small) }
                            else { Label(AppText.ui("AI 生成标题", "Generate Title with AI", "AI でタイトルを生成"), systemImage: "sparkles") }
                        }
                        .disabled(session.isGeneratingSavedTitle || session.isTranscriptCleanupRunning || session.isRunning || session.isStarting)
                        .help(AppText.ui("使用当前选择的 AI 总结记录并生成标题，停止监听后可用。", "Use the selected AI to summarize the transcript into a title after stopping capture.", "聞き取りを停止した後、現在の AI で記録を要約してタイトルを生成します。"))
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
                        Text(message).font(.caption).foregroundStyle(.secondary)
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
            .padding(AirTranslateDesign.Spacing.md)
            .airRaisedSurface()
            .padding(AirTranslateDesign.Spacing.md)
        } else {
            ContentUnavailableView(AppText.noSavedTranscriptSelected, systemImage: "doc.text")
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
        if let selectedSavedTranscriptID = session.selectedSavedTranscriptID,
           session.savedTranscripts.contains(where: { $0.id == selectedSavedTranscriptID }) {
            return
        }

        if let firstTranscript = session.savedTranscripts.first {
            session.selectSavedTranscript(firstTranscript.id)
        }
    }
}

private struct TranscriptLibraryRow: View {
    let transcript: SavedTranscript
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: transcript.isOriginalAndTranslation ? "doc.on.doc.fill" : (isSelected ? "doc.text.fill" : "doc.text"))
                .foregroundStyle(isSelected ? AirTranslateDesign.Palette.accent : AirTranslateDesign.Palette.textSecondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(transcript.title)
                    .font(AirTranslateDesign.Typography.libraryRowTitle)
                    .lineLimit(2)
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                HStack(spacing: 5) {
                    if transcript.isOriginalAndTranslation {
                        Text(AppText.originalAndTranslation)
                    }

                    Text(transcript.updatedAt, style: .date)
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
