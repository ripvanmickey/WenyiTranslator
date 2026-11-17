import Foundation

enum SavedTranscriptTimestamp {
    struct Segment {
        let text: String
        let shownAt: Date
    }

    private static let prefixPattern = #"^\[\d{2,}:\d{2}:\d{2}\.\d{3}\] "#

    static func annotate(_ text: String, segments: [Segment], startedAt: Date) -> String {
        var result = ""
        var cursor = text.startIndex

        for segment in segments {
            let content = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty { continue }

            // Only add a mark where the saved text still contains this caption at a line boundary.
            var searchStart = cursor
            while let match = text.range(of: content, range: searchStart..<text.endIndex) {
                let startsLine = match.lowerBound == text.startIndex || text[text.index(before: match.lowerBound)].isNewline
                let endsLine = match.upperBound == text.endIndex || text[match.upperBound].isNewline
                if startsLine, endsLine {
                    result += text[cursor..<match.lowerBound]
                    result += prefix(elapsed: segment.shownAt.timeIntervalSince(startedAt))
                    result += text[match]
                    cursor = match.upperBound
                    break
                }
                searchStart = text.index(after: match.lowerBound)
            }
        }

        result += text[cursor...]
        return result
    }

    static func removingPrefix(from line: String) -> String {
        line.replacingOccurrences(of: prefixPattern, with: "", options: .regularExpression)
    }

    private static func prefix(elapsed: TimeInterval) -> String {
        let milliseconds = Int((max(0, elapsed) * 1_000).rounded())
        let hours = Int64(milliseconds / 3_600_000)
        let minutes = milliseconds / 60_000 % 60
        let seconds = milliseconds / 1_000 % 60
        return String(format: "[%02lld:%02d:%02d.%03d] ", hours, minutes, seconds, milliseconds % 1_000)
    }
}
