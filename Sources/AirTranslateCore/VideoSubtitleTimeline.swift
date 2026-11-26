import Foundation

public struct YouTubeVideoReference: Equatable, Sendable {
    public let id: String
    public var url: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }

    public init(_ text: String) throws {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", parts.user == nil, parts.password == nil,
              parts.port == nil, let host = parts.host?.lowercased() else { throw VideoSubtitleError.invalidVideo }
        let path = parts.path.split(separator: "/").map(String.init)
        let candidate: String?
        if ["youtu.be", "www.youtu.be"].contains(host) {
            candidate = path.count == 1 ? path.first : nil
        } else if ["youtube.com", "www.youtube.com", "m.youtube.com"].contains(host) {
            if parts.path == "/watch" {
                candidate = parts.queryItems?.first(where: { $0.name == "v" })?.value
            } else if path.count == 2, ["shorts", "live", "embed"].contains(path[0]) {
                candidate = path[1]
            } else { candidate = nil }
        } else { candidate = nil }
        guard let candidate, candidate.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil else {
            throw VideoSubtitleError.invalidVideo
        }
        id = candidate
    }
}

public enum VideoSubtitleError: Error, Sendable {
    case invalidVideo, invalidSubtitles, noSubtitles, invalidPlayback, invalidAudio
}

public struct VideoSubtitleCue: Codable, Identifiable, Equatable, Sendable {
    public let id: Int
    public var start: Double
    public var end: Double
    public var source: String
    public var translation: String
    public init(id: Int, start: Double, end: Double, source: String, translation: String = "") {
        self.id = id; self.start = start; self.end = end
        self.source = source; self.translation = translation
    }
}

public struct VideoSubtitleDocument: Codable, Sendable {
    public var videoID: String
    public var title: String
    public var sourceLanguage: String
    public var targetLanguage: String
    public var provider: String
    public var input: String
    public var cues: [VideoSubtitleCue]
    public var completed: Bool
    public var audioProgress: VideoAudioPreparationProgress?
    public var updatedAt: Date
    public init(videoID: String, title: String, sourceLanguage: String, targetLanguage: String,
                provider: String, input: String, cues: [VideoSubtitleCue], completed: Bool = false,
                audioProgress: VideoAudioPreparationProgress? = nil) {
        self.videoID = videoID; self.title = title; self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage; self.provider = provider; self.input = input
        self.cues = cues; self.completed = completed; self.audioProgress = audioProgress; updatedAt = Date()
    }
}

public enum VideoSubtitleTimeline {
    /// Display is driven by media time. Seeking backwards or forwards requires no state reset.
    public static func activeCue(in cues: [VideoSubtitleCue], at time: Double) -> VideoSubtitleCue? {
        guard let cue = mostRecentCue(in: cues, at: time) else { return nil }
        return time < cue.end ? cue : nil
    }

    /// Main-window reading context remains visible in gaps; overlays use activeCue.
    public static func mostRecentCue(in cues: [VideoSubtitleCue], at time: Double) -> VideoSubtitleCue? {
        guard time.isFinite, time >= 0, !cues.isEmpty else { return nil }
        var low = 0, high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].start <= time { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return nil }
        return cues[low - 1]
    }

    public static func parse(_ data: Data) throws -> [VideoSubtitleCue] {
        guard data.count <= 20_000_000, let raw = String(data: data, encoding: .utf8) else {
            throw VideoSubtitleError.invalidSubtitles
        }
        var cues: [VideoSubtitleCue] = []
        let wordTimingPattern = "<[0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{3}>"
        let hasWordTiming = raw.range(of: wordTimingPattern, options: .regularExpression) != nil
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        var index = 0
        while index < lines.count {
            let times = lines[index].components(separatedBy: "-->")
            index += 1
            guard times.count == 2, let start = timestamp(times[0]), let end = timestamp(times[1]),
                  end > start else { continue }
            var content: [String] = []
            while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                content.append(lines[index]); index += 1
            }
            let timedLines = content.filter { $0.range(of: wordTimingPattern, options: .regularExpression) != nil }
            if hasWordTiming && timedLines.isEmpty && end - start < 0.1 { continue }
            let text = clean((timedLines.isEmpty ? content : timedLines).joined(separator: "\n"))
            if !text.isEmpty { cues.append(.init(id: cues.count, start: start, end: end, source: text)) }
        }
        let result = normalized(cues)
        guard !result.isEmpty else { throw VideoSubtitleError.noSubtitles }
        return result
    }

    public static func normalized(_ values: [VideoSubtitleCue]) -> [VideoSubtitleCue] {
        let sorted = values.filter { $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && !$0.source.isEmpty }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        var result: [VideoSubtitleCue] = []
        for cue in sorted {
            if let last = result.last, last.source == cue.source, cue.start <= last.end + 0.05 {
                result[result.count - 1].end = max(last.end, cue.end)
                continue
            }
            if let last = result.last, cue.start < last.end {
                if cue.start <= last.start { result.removeLast() }
                else { result[result.count - 1].end = cue.start }
            }
            result.append(.init(id: result.count, start: cue.start, end: cue.end, source: cue.source, translation: cue.translation))
        }
        return result
    }

    private static func timestamp(_ text: String) -> Double? {
        guard let token = text.trimmingCharacters(in: .whitespaces).split(separator: " ").first else { return nil }
        let pieces = token.replacingOccurrences(of: ",", with: ".").split(separator: ":")
        guard (2...3).contains(pieces.count) else { return nil }
        var value = 0.0
        for piece in pieces {
            guard let number = Double(piece), number.isFinite, number >= 0 else { return nil }
            value = value * 60 + number
        }
        return value
    }

    private static func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func srt(_ cues: [VideoSubtitleCue], bilingual: Bool = true) -> String {
        var blocks: [String] = []
        blocks.reserveCapacity(cues.count)
        for cue in cues {
            guard cue.start >= 0,
                  let start = Int64(exactly: (cue.start * 1_000).rounded()),
                  let end = Int64(exactly: (cue.end * 1_000).rounded()), end > start else { continue }
            let text = srtText(bilingual ? cue.source + "\n" + cue.translation : cue.source)
            guard !text.isEmpty else { continue }
            blocks.append("\(blocks.count + 1)\n\(srtTime(start)) --> \(srtTime(end))\n\(text)\n")
        }
        return blocks.joined(separator: "\n")
    }

    private static func srtText(_ text: String) -> String {
        // A blank line separates cues in SRT, even when a translator returns paragraphs.
        text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: "\n")
    }

    private static func srtTime(_ ms: Int64) -> String {
        String(format: "%02lld:%02lld:%02lld,%03lld", ms / 3_600_000, ms / 60_000 % 60, ms / 1_000 % 60, ms % 1_000)
    }
}
