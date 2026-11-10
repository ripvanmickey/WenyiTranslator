import Foundation
import AirTranslateCore

struct CaptionLine: Identifiable, Equatable {
    private static let maxDisplayCharacters = 4_000

    let id: UUID
    let sourceText: String
    var sourceDisplayText: String
    let translatedText: String
    let translatedDisplayText: String
    let translatedSourceText: String
    let createdAt: Date
    let isTranslationComplete: Bool
    let isFinal: Bool
    let revision: Int
    let speakerLabel: String?

    init(
        id: UUID = UUID(),
        sourceText: String,
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
        self.sourceDisplayText = Self.displayText(for: sourceText, usesLongSessionDisplay: usesLongSessionDisplay)
        self.translatedText = translatedText
        self.translatedDisplayText = Self.displayText(for: translatedText, usesLongSessionDisplay: usesLongSessionDisplay)
        self.translatedSourceText = translatedSourceText
        self.createdAt = createdAt
        self.isTranslationComplete = isTranslationComplete
        self.isFinal = isFinal
        self.revision = revision
        self.speakerLabel = speakerLabel
    }

    private static func displayText(for raw: String, usesLongSessionDisplay: Bool) -> String {
        // Apply at the shared presentation boundary, including native ASR paths that
        // intentionally bypass transcript rewriting. Raw source and translation remain intact.
        let text: String
        if JapaneseCaptionLayout.containsKana(raw) {
            text = JapaneseCaptionLayout.format(raw)
        } else if raw.contains(where: { "。！？".contains($0) }) {
            text = TranscriptTextProcessor.organizeTranscript(raw, languageID: "ja-JP")
        } else { text = raw }
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
}
