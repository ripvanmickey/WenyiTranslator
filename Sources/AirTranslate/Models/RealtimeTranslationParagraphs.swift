import Foundation

/// Commit only complete sentence prefixes from both independently arriving streams.
/// The remaining suffixes stay live until both streams have enough completed text.
struct RealtimeTranslationParagraphs {
    private var sourceOffset = 0
    private var translationOffset = 0

    struct Paragraph: Equatable {
        let source: String
        let translation: String
    }

    func pending(source: String, translation: String) -> Paragraph {
        Paragraph(
            source: String(source.dropFirst(sourceOffset)).trimmingCharacters(in: .whitespacesAndNewlines),
            translation: String(translation.dropFirst(translationOffset)).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    mutating func takeCompleted(source: String, translation: String) -> Paragraph? {
        let remaining = pending(source: source, translation: translation)
        guard remaining.source.count >= 120 || remaining.translation.count >= 180,
              let sourceEnd = sentenceEnd(in: remaining.source),
              let translationEnd = sentenceEnd(in: remaining.translation) else { return nil }
        let paragraph = Paragraph(
            source: String(remaining.source[..<sourceEnd]),
            translation: String(remaining.translation[..<translationEnd])
        )
        // Locate the consumed prefixes in the raw suffixes to retain whitespace correctly.
        let rawSource = source.dropFirst(sourceOffset)
        let rawTranslation = translation.dropFirst(translationOffset)
        guard let sourceRange = rawSource.range(of: paragraph.source),
              let translationRange = rawTranslation.range(of: paragraph.translation) else { return nil }
        sourceOffset += rawSource.distance(from: rawSource.startIndex, to: sourceRange.upperBound)
        translationOffset += rawTranslation.distance(from: rawTranslation.startIndex, to: translationRange.upperBound)
        return paragraph
    }

    private func sentenceEnd(in text: String) -> String.Index? {
        // Full stops in decimals, hostnames and abbreviations are not safe boundaries.
        // A Latin full stop is accepted at the end or before whitespace.
        var boundary: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            if "。！？!?\n".contains(character)
                || character == "." && (next == text.endIndex || text[next].isWhitespace) {
                boundary = next
            } else if "\"'」』）】”’".contains(character), boundary == index {
                boundary = next
            }
            index = next
        }
        if boundary == nil, text.count >= 480 {
            let limit = text.index(text.startIndex, offsetBy: 320)
            boundary = text[..<limit].lastIndex(where: \.isWhitespace).map { text.index(after: $0) } ?? limit
        }
        return boundary
    }
}
