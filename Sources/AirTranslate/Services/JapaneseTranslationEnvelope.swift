import Foundation

/// Translation first; optional punctuation footer is never part of visible translation.
enum JapaneseTranslationEnvelope {
    static let marker = "[WENYI_JA]"
    static func translation(_ raw: String) -> String {
        if let range = raw.range(of: marker) { return String(raw[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines) }
        // SSE can split the marker at any byte/token boundary.
        for count in stride(from: min(raw.count, marker.count - 1), through: 1, by: -1) {
            if marker.hasPrefix(String(raw.suffix(count))) {
                return String(raw.dropLast(count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return raw
    }
    static func source(_ raw: String, original: String) -> String? {
        guard let range = raw.range(of: marker) else { return nil }
        let candidate = String(raw[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet(charactersIn: "、。！？!?，,．.").union(.whitespacesAndNewlines)
        func words(_ value: String) -> String {
            String(String.UnicodeScalarView(value.unicodeScalars.filter { !allowed.contains($0) }))
        }
        guard candidate.count <= original.count * 2, words(candidate) == words(original),
              candidate.contains(where: { "、。！？!?".contains($0) }) else { return nil }
        return candidate
    }
}
