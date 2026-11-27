import Foundation

public struct VideoSubtitleReviewProgress: Codable, Equatable, Sendable {
    public let nextCue: Int
    public let correctedCues: Int

    public init(nextCue: Int, correctedCues: Int) {
        self.nextCue = nextCue
        self.correctedCues = correctedCues
    }
}

public enum VideoSubtitleReviewError: Error, Sendable {
    case invalidResult, incompleteCaptions, emptyTranslation
}

public struct VideoSubtitleReviewBatch: Encodable, Sendable {
    private struct Line: Encodable, Sendable {
        let index: Int
        let text: String
        let editable: Bool
    }

    private struct Response: Decodable {
        struct Edit: Decodable {
            let index: Int
            let original: String
            let replacement: String
            let evidenceIndex: Int
            let evidence: String
        }

        let corrections: [Edit]
    }

    private enum CodingKeys: CodingKey { case lines }
    private let lines: [Line]
    fileprivate let targets: Range<Int>

    fileprivate init(cues: [VideoSubtitleCue], at start: Int) {
        let end = min(start + 10, cues.count)
        let context = max(0, start - 3)..<min(end + 3, cues.count)
        let targets = start..<end
        self.targets = targets
        lines = context.map { index in
            Line(index: index, text: String(cues[index].source.prefix(600)), editable: targets.contains(index))
        }
    }

    fileprivate func replacements(from response: String, in cues: [VideoSubtitleCue]) throws -> [Int: String] {
        var json = response.trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasPrefix("```"), json.hasSuffix("```"), let newline = json.firstIndex(of: "\n") {
            json = String(json[json.index(after: newline)...].dropLast(3))
        }
        guard json.utf8.count <= 48_000,
              let result = try? JSONDecoder().decode(Response.self, from: Data(json.utf8)),
              result.corrections.count <= targets.count * 3 else {
            throw VideoSubtitleReviewError.invalidResult
        }

        let visible = Dictionary(uniqueKeysWithValues: lines.map { ($0.index, $0.text) })
        let proposed = Dictionary(grouping: result.corrections, by: \.index)
        var replacements: [Int: String] = [:]
        for index in targets {
            guard let edits = proposed[index] else { continue }
            let source = cues[index].source
            let patches: [(range: Range<String.Index>, text: String)] = edits.compactMap { edit in
                guard edit.original != edit.replacement, Self.isTerm(edit.original), Self.isTerm(edit.replacement),
                      visible[index]?.range(of: edit.original, options: .literal) != nil,
                      (4...180).contains(edit.evidence.count),
                      visible[edit.evidenceIndex]?.range(of: edit.evidence, options: .literal) != nil,
                      edit.evidenceIndex != index || !edit.evidence.contains(edit.original),
                      let range = source.range(of: edit.original, options: .literal),
                      source.range(of: edit.original, options: .literal, range: range.upperBound..<source.endIndex) == nil
                else { return nil }

                let oldNumbers = edit.original.filter(\.isNumber)
                let newNumbers = edit.replacement.filter(\.isNumber)
                // Retain existing numbers. A new numeric term such as 2駆 needs an exact context match.
                guard oldNumbers == newNumbers || (oldNumbers.isEmpty && edit.evidence.contains(edit.replacement)) else {
                    return nil
                }
                return (range, edit.replacement)
            }
            let ordered = patches.sorted { $0.range.lowerBound < $1.range.lowerBound }
            var updated = ""
            var cursor = source.startIndex
            var changed = 0
            let editBudget = max(6, source.count / 4)
            for patch in ordered {
                let length = source[patch.range].count
                guard patch.range.lowerBound >= cursor, changed + length <= editBudget else { continue }
                updated += source[cursor..<patch.range.lowerBound]
                updated += patch.text
                cursor = patch.range.upperBound
                changed += length
            }
            if changed > 0 { replacements[index] = updated + source[cursor...] }
        }
        return replacements
    }

    private static func isTerm(_ text: String) -> Bool {
        (1...24).contains(text.count) && text == text.trimmingCharacters(in: .whitespacesAndNewlines)
            && text.contains(where: \.isLetter)
            && text.allSatisfy { $0.isLetter || $0.isNumber || " -.'’·+/&_".contains($0) }
    }
}

public enum VideoSubtitleReviewPipeline {
    /// Commit progress, corrected source, and its replacement translation together after each batch.
    public static func run(
        document initial: VideoSubtitleDocument,
        isolation: isolated (any Actor)? = #isolation,
        review: (VideoSubtitleReviewBatch) async throws -> String,
        translate: (String) async throws -> String,
        commit: (VideoSubtitleDocument) async throws -> Void
    ) async throws {
        guard initial.completed, initial.audioProgress?.isRecognitionComplete != false, !initial.cues.isEmpty else {
            throw VideoSubtitleReviewError.incompleteCaptions
        }
        var document = initial
        var start = document.reviewProgress?.nextCue ?? 0
        var corrected = document.reviewProgress?.correctedCues ?? 0
        guard (0...document.cues.count).contains(start), (0...start).contains(corrected) else {
            throw VideoSubtitleReviewError.invalidResult
        }

        while start < document.cues.count {
            try Task.checkCancellation()
            let batch = VideoSubtitleReviewBatch(cues: document.cues, at: start)
            let response = try await review(batch)
            try Task.checkCancellation()
            let replacements = try batch.replacements(from: response, in: document.cues)
            for (index, source) in replacements.sorted(by: { $0.key < $1.key }) {
                try Task.checkCancellation()
                let translation = try await translate(source).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !translation.isEmpty else { throw VideoSubtitleReviewError.emptyTranslation }
                document.cues[index].source = source
                document.cues[index].translation = translation
            }
            try Task.checkCancellation()
            start = batch.targets.upperBound
            corrected += replacements.count
            document.reviewProgress = .init(nextCue: start, correctedCues: corrected)
            document.updatedAt = Date()
            try await commit(document)
        }
    }
}
