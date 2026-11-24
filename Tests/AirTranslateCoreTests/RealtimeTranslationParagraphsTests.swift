import Foundation
import Testing
@testable import AirTranslate

struct RealtimeTranslationParagraphsTests {
    @Test
    func delayedTranslationKeepsOriginalLiveUntilBothHaveSentenceBoundaries() {
        var paragraphs = RealtimeTranslationParagraphs()
        let source = String(repeating: "日本語の文章です。", count: 16) + "続き"
        #expect(paragraphs.takeCompleted(source: source, translation: "") == nil)
        #expect(paragraphs.pending(source: source, translation: "").source == source)
        let translation = String(repeating: "这是完整的句子。", count: 16) + "未完"
        let completed = paragraphs.takeCompleted(source: source, translation: translation)
        #expect(completed?.source == String(source.dropLast(2)))
        #expect(completed?.translation == String(translation.dropLast(2)))
        #expect(paragraphs.pending(source: source, translation: translation) == .init(source: "続き", translation: "未完"))
        #expect(paragraphs.takeCompleted(source: source, translation: translation) == nil)
    }

    @Test
    func streamingParagraphsPreserveContentAcrossRepeatedCumulativeUpdates() {
        var paragraphs = RealtimeTranslationParagraphs()
        var source = ""
        var translation = ""
        var completed: [RealtimeTranslationParagraphs.Paragraph] = []
        for index in 0..<300 {
            source += "第\(index)段の日本語です。 "
            translation += "这是第\(index)段中文。 "
            if let paragraph = paragraphs.takeCompleted(source: source, translation: translation) {
                completed.append(paragraph)
            }
            #expect(paragraphs.takeCompleted(source: source, translation: translation) == nil)
        }
        let pending = paragraphs.pending(source: source, translation: translation)
        func content(_ text: String) -> String { String(text.filter { !$0.isWhitespace }) }
        #expect(completed.count > 10)
        #expect(content(completed.map(\.source).joined() + pending.source) == content(source))
        #expect(content(completed.map(\.translation).joined() + pending.translation) == content(translation))
    }

    @Test
    func punctuationFreeStreamsAndClosingQuotesAreHandled() {
        var paragraphs = RealtimeTranslationParagraphs()
        let longText = String(repeating: "長い文", count: 200)
        let completed = paragraphs.takeCompleted(source: longText, translation: longText)
        #expect(completed?.source.count == 320)
        #expect(paragraphs.pending(source: longText, translation: longText).source.count == 280)

        paragraphs = RealtimeTranslationParagraphs()
        let quoted = String(repeating: "文章", count: 70) + "。』"
        #expect(paragraphs.takeCompleted(source: quoted, translation: quoted)?.source == quoted)
    }
}
