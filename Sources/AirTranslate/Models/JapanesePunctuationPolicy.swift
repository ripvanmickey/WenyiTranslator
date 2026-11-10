import Foundation
import AirTranslateCore

/// Punctuation is presentation-only; recognition identities and translation inputs stay intact.
enum JapanesePunctuationPolicy {
    static func needsRestoration(_ text: String) -> Bool {
        (12...320).contains(text.count) && !text.contains(where: { "。！？!?".contains($0) })
            && text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) }
    }

    static func validatedDisplay(_ candidate: String, original: String) -> String? {
        let allowed = CharacterSet(charactersIn: "、。！？!?，,．.").union(.whitespacesAndNewlines)
        func words(_ text: String) -> String {
            String(String.UnicodeScalarView(text.unicodeScalars.filter { !allowed.contains($0) }))
        }
        guard candidate.count <= original.count * 2, words(candidate) == words(original),
              candidate.contains(where: { "、。！？!?".contains($0) }) else { return nil }
        return JapaneseCaptionLayout.format(candidate)
    }
}
