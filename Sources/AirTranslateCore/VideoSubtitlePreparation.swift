import Foundation

public struct VideoAudioRange: Codable, Equatable, Sendable {
    public let start: Double
    public let end: Double
    public init(start: Double, end: Double) { self.start = start; self.end = end }
}

/// A checkpoint covers audio requests, including ranges that returned no speech.
/// Nil on a document means the source was fully recognized by an older version.
public struct VideoAudioPreparationProgress: Codable, Sendable {
    public var ranges: [VideoAudioRange]
    public var nextRange: Int
    public var isRecognitionComplete: Bool { nextRange == ranges.count }
    public init(ranges: [VideoAudioRange], nextRange: Int = 0) {
        self.ranges = ranges; self.nextRange = nextRange
    }
}

public enum VideoSubtitleProgressivePipeline {
    /// Deliver and await each whole phrase before requesting the next one. The consumer
    /// can persist and translate it while the rest of the audio is still unrecognized.
    public static func run(
        ranges: [VideoAudioRange], from startIndex: Int,
        isolation: isolated (any Actor)? = #isolation,
        recognize: (Int, VideoAudioRange) async throws -> String,
        consume: (VideoSubtitleCue?, Int, Int) async throws -> Void
    ) async throws {
        guard (0...ranges.count).contains(startIndex) else { throw VideoSubtitleError.invalidAudio }
        for index in startIndex..<ranges.count {
            try Task.checkCancellation()
            let range = ranges[index]
            let text = try await recognize(index, range).trimmingCharacters(in: .whitespacesAndNewlines)
            try Task.checkCancellation()
            let cue = text.isEmpty ? nil : VideoSubtitleCue(id: index, start: range.start, end: range.end, source: text)
            try await consume(cue, index + 1, ranges.count)
        }
    }
}
