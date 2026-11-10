import Foundation
import NaturalLanguage

/// Reading breaks only. Never changes the recognized words or invents sentence punctuation.
package enum JapaneseCaptionLayout {
    package static func containsKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
    }

    package static func format(_ text: String) -> String {
        guard containsKana(text) else { return text }
        let organized = text.components(separatedBy: "\n").map {
            TranscriptTextProcessor.organizeParagraph($0, languageID: "ja-JP")
        }.joined(separator: "\n")
        return organized.components(separatedBy: "\n").map { paragraph in
            // Prefer complete polite endings, without cutting ですけど / ですから / でしょう.
            let expression = try! NSRegularExpression(
                pattern: #"(?:なんですよね|んですよね|なんですね|んですね|ですよね|ますよね|でしたね|ましたね|ですね|ますね|でした|ました|ません|でしょうか|ですか|ますか|ですよ|ますよ|です|ます)(?![。！？!?、」』）】]|けど|が|から|ので|し|よ|ね|か|と|って)"#)
            var pieces: [String] = []
            var start = paragraph.startIndex
            for match in expression.matches(in: paragraph, range: NSRange(paragraph.startIndex..., in: paragraph)) {
                guard let range = Range(match.range, in: paragraph) else { continue }
                let end = range.upperBound
                if end < paragraph.endIndex, paragraph[start..<end].count >= 12 {
                    pieces.append(String(paragraph[start..<end])); start = end
                }
            }
            if start < paragraph.endIndex { pieces.append(String(paragraph[start...])) }
            return pieces.flatMap { wrap($0) }.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private static func wrap(_ text: String) -> [String] {
        guard text.count > 40 else { return [text] }
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.setLanguage(.japanese)
        tokenizer.string = text
        var boundaries: [String.Index] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            boundaries.append(range.upperBound); return true
        }
        var result: [String] = []
        var start = text.startIndex
        while text[start...].count > 40 {
            let preferred = text.index(start, offsetBy: 32)
            let maximum = text.index(start, offsetBy: 40)
            let minimum = text.index(start, offsetBy: 20)
            // Use Japanese word boundaries, rather than breaking midway through a name or number.
            guard let boundary = boundaries.last(where: { $0 >= minimum && $0 <= preferred })
                    ?? boundaries.first(where: { $0 > preferred && $0 <= maximum }), boundary > start else {
                // An unusually long single token remains intact.
                break
            }
            var end = boundary
            while end < text.endIndex, "、。！？!?」』）】,.;:".contains(text[end]) {
                end = text.index(after: end)
            }
            result.append(String(text[start..<end])); start = end
        }
        result.append(String(text[start...]))
        return result
    }
}
