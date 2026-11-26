import Foundation
import NaturalLanguage

/// A title is a fallible hint about speech. Never force an ambiguous or unsupported language.
enum VideoTitleLanguage {
    static func infer(from title: String) -> LanguageOption? {
        let text = String(title.prefix(512))
            .replacingOccurrences(of: #"\s+[-–—|]\s*YouTube\s*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.lowercased() != "youtube" else { return nil }
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let latin = letters.filter { $0.value <= 0x024F }.count
        let eastAsian = letters.filter {
            (0x3040...0x30FF).contains($0.value) || (0x3400...0x9FFF).contains($0.value)
                || (0xAC00...0xD7AF).contains($0.value) || (0xFF66...0xFF9D).contains($0.value)
        }.count
        guard letters.count >= (eastAsian > latin ? 4 : 12) else { return nil }
        if latin >= 8, eastAsian >= 4, Double(min(latin, eastAsian)) / Double(latin + eastAsian) >= 0.25 { return nil }
        if latin > 0, eastAsian == 0,
           text.split(whereSeparator: { !$0.isLetter }).filter({ $0.count >= 2 }).count < 3 { return nil }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let candidates = recognizer.languageHypotheses(withMaximum: 2).sorted { $0.value > $1.value }
        guard let best = candidates.first, best.value >= 0.8,
              best.value - (candidates.dropFirst().first?.value ?? 0) >= 0.25 else { return nil }
        let identifier: String
        switch best.key {
        case .english: identifier = "en-US"
        case .korean: identifier = "ko-KR"
        case .japanese: identifier = "ja-JP"
        case .simplifiedChinese, .traditionalChinese: identifier = "zh-CN"
        case .spanish: identifier = "es-ES"
        case .french: identifier = "fr-FR"
        case .german: identifier = "de-DE"
        default: return nil
        }
        return LanguageOption.supported.first { $0.id == identifier }
    }
}
