import AppKit
import SwiftUI

struct QwenAudioFileTranscriptionView: View {
    let hasAPIKey: Bool
    private let service: QwenAudioFileTranscriptionService
    @AppStorage("qwenFileTranscriptionURL") private var savedFileURL = ""
    @State private var showsConfiguration = false
    @State private var draftFileURL = ""
    @State private var transcript = ""
    @State private var errorMessage: String?
    @State private var isWorking = false
    @State private var task: Task<Void, Never>?

    init(hasAPIKey: Bool, service: QwenAudioFileTranscriptionService = QwenAudioFileTranscriptionService()) {
        self.hasAPIKey = hasAPIKey
        self.service = service
    }

    var body: some View {
        SettingsControlRow(
            title: QwenCopy.fileTranscriptionTitle,
            detail: savedFileURL.isEmpty ? QwenCopy.fileTranscriptionNoSavedURL : savedFileURL,
            systemImage: "waveform",
            detailLineLimit: 1,
            showsSeparator: false
        ) {
            HStack {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(QwenCopy.fileTranscriptionWorking)
                }
                Button(QwenCopy.fileTranscriptionConfigure) {
                    if !isWorking { draftFileURL = savedFileURL }
                    showsConfiguration = true
                }
                .accessibilityIdentifier("qwenFileTranscriptionConfigure")
            }
        }
        .sheet(isPresented: $showsConfiguration) {
            configurationSheet
        }
    }

    private var configurationSheet: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.sm) {
            Text(QwenCopy.fileTranscriptionTitle)
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            Text(QwenCopy.fileTranscriptionDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField(QwenCopy.fileTranscriptionURLLabel, text: $draftFileURL,
                      prompt: Text(QwenCopy.fileTranscriptionURLPlaceholder))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .disabled(isWorking)
                .accessibilityLabel(QwenCopy.fileTranscriptionURLLabel)
                .accessibilityIdentifier("qwenFileTranscriptionURL")

            Text(QwenCopy.fileTranscriptionPrivacy)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !trimmedDraftURL.isEmpty, validatedDraftURL == nil {
                Label(QwenCopy.fileTranscriptionInvalidURL, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AirTranslateDesign.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(QwenCopy.fileTranscriptionWorking)
                    Text(QwenCopy.fileTranscriptionWorking)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(QwenCopy.fileTranscriptionCancel, action: cancel)
                        .accessibilityIdentifier("qwenFileTranscriptionCancel")
                } else {
                    Button(QwenCopy.fileTranscriptionStart, action: start)
                        .disabled(!hasAPIKey || validatedDraftURL == nil)
                        .accessibilityIdentifier("qwenFileTranscriptionStart")
                    Spacer()
                    if !hasAPIKey {
                        Label(QwenCopy.apiKeyRequired, systemImage: "key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(AirTranslateDesign.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("qwenFileTranscriptionError")
            }

            if !transcript.isEmpty {
                ScrollView {
                    Text(transcript)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(maxHeight: 190)
                .background(AirTranslateDesign.Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityIdentifier("qwenFileTranscriptionResult")

                HStack {
                    Spacer()
                    Button(QwenCopy.fileTranscriptionCopy, action: copyTranscript)
                        .accessibilityIdentifier("qwenFileTranscriptionCopy")
                }
            }

            HStack {
                Spacer()
                Button(AppText.close) { showsConfiguration = false }
                    .keyboardShortcut(.cancelAction)
                Button(QwenCopy.fileTranscriptionSave, action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking || (!trimmedDraftURL.isEmpty && validatedDraftURL == nil))
                    .accessibilityIdentifier("qwenFileTranscriptionSave")
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var trimmedDraftURL: String {
        draftFileURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validatedDraftURL: URL? {
        try? QwenAudioFileTranscriptionService.publicAudioURL(draftFileURL)
    }

    private func save() {
        if let validatedDraftURL {
            savedFileURL = validatedDraftURL.absoluteString
        } else if trimmedDraftURL.isEmpty {
            savedFileURL = ""
        } else {
            return
        }
        showsConfiguration = false
    }

    private func start() {
        guard !isWorking, hasAPIKey, let fileURL = validatedDraftURL else { return }
        transcript = ""
        errorMessage = nil
        isWorking = true
        task = Task {
            do {
                transcript = try await service.transcribe(fileURL: fileURL.absoluteString)
            } catch is CancellationError {
                // Cancellation is initiated by the user.
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
            task = nil
        }
    }

    private func cancel() {
        task?.cancel()
    }

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcript, forType: .string)
    }
}
