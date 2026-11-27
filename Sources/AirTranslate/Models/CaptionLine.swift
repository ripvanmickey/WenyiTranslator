import Foundation
import AirTranslateCore

struct CaptionLine: Identifiable, Equatable {
    private static let maxDisplayCharacters = 4_000

    let id: UUID
    let sourceText: String
    let isSourcePlaceholder: Bool
    var sourceDisplayText: String
    let translatedText: String
    let translatedDisplayText: String
    let translatedSourceText: String
    let createdAt: Date
    let isTranslationComplete: Bool
    var isTranslationInterrupted = false
    let isFinal: Bool
    let revision: Int
    let speakerLabel: String?

    var hasConfirmedTranslation: Bool {
        isFinal && isTranslationComplete && translatedSourceText == sourceText
    }

    var hasUsableTranslation: Bool {
        !translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && translatedText != AppText.translating && translatedText != AppText.translationCancelled
    }

    var localTranslationStatus: String {
        if isTranslationInterrupted { return InterfaceLocalization.ui("中断", "Interrupted", "中断") }
        if hasConfirmedTranslation && hasUsableTranslation { return InterfaceLocalization.ui("已完成", "Complete", "完了") }
        return hasUsableTranslation
            ? InterfaceLocalization.ui("预览", "Preview", "プレビュー")
            : InterfaceLocalization.ui("等待译文", "Waiting for translation", "訳文を待機中")
    }

    init(
        id: UUID = UUID(),
        sourceText: String,
        isSourcePlaceholder: Bool = false,
        translatedText: String,
        translatedSourceText: String = "",
        createdAt: Date,
        isFinal: Bool,
        isTranslationComplete: Bool = false,
        revision: Int = 0,
        speakerLabel: String? = nil,
        usesLongSessionDisplay: Bool = false
    ) {
        self.id = id
        self.sourceText = sourceText
        self.isSourcePlaceholder = isSourcePlaceholder
        self.sourceDisplayText = Self.displayText(for: sourceText, usesLongSessionDisplay: usesLongSessionDisplay)
        self.translatedText = translatedText
        self.translatedDisplayText = Self.displayText(for: translatedText, usesLongSessionDisplay: usesLongSessionDisplay,
            preservesLineBreaks: true)
        self.translatedSourceText = translatedSourceText
        self.createdAt = createdAt
        self.isTranslationComplete = isTranslationComplete
        self.isFinal = isFinal
        self.revision = revision
        self.speakerLabel = speakerLabel
    }

    private static func displayText(for raw: String, usesLongSessionDisplay: Bool, preservesLineBreaks: Bool = false) -> String {
        // Apply at the shared presentation boundary, including native ASR paths that
        // intentionally bypass transcript rewriting. Raw source and translation remain intact.
        let text = if preservesLineBreaks && raw.contains(where: \.isNewline) {
            raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
                .map { formattedDisplayText(String($0)) }
                .joined(separator: "\n")
        } else {
            formattedDisplayText(raw)
        }
        guard usesLongSessionDisplay
            || text.utf8.count > Self.maxDisplayCharacters && text.count > Self.maxDisplayCharacters
        else {
            return text
        }

        return TranscriptTextProcessor.displayTail(
            from: text,
            maxCharacters: Self.maxDisplayCharacters
        )
    }

    private static func formattedDisplayText(_ raw: String) -> String {
        if JapaneseCaptionLayout.containsKana(raw) {
            return JapaneseCaptionLayout.format(raw)
        } else if raw.contains(where: { "。！？".contains($0) }) {
            return TranscriptTextProcessor.organizeTranscript(raw, languageID: "ja-JP")
        }
        return raw
    }
}
