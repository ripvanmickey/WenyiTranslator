import Foundation

/// A changed recognition tail invalidates only that tail, never unrelated earlier clauses.
struct IncrementalCaptionPlan: Sendable {
    struct Chunk: Equatable, Sendable { let source: String; let translation: String; var followingContext: String = ""; var punctuatedSource: String? = nil }
    let blocks: [String]
    let reusable: [Chunk]

    init(text: String, previous: [Chunk]) {
        var blocks: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            let sentenceEnd = ".!?。！？\n".contains(character) && current.count >= 8
            let clauseEnd = ",;、，；".contains(character) && current.count >= 24
            if sentenceEnd || clauseEnd || current.count >= 100 {
                blocks.append(current); current = ""
            }
        }
        if !current.isEmpty { blocks.append(current) }
        self.blocks = blocks
        var reusable: [Chunk] = []
        for (index, pair) in zip(blocks, previous).enumerated() {
            let (block, old) = pair
            guard block == old.source, old.followingContext == Self.following(blocks, at: index) else { break }
            reusable.append(old)
        }
        self.reusable = reusable
    }
    static func following(_ blocks: [String], at index: Int) -> String {
        let trimmed = blocks[index].trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = trimmed.last, ".!?。！？".contains(last) { return "" }
        return String(blocks.dropFirst(index + 1).joined().prefix(40))
    }
}

actor IncrementalLocalTranslator {
    static let shared = IncrementalLocalTranslator()
    private var previous: [String: [IncrementalCaptionPlan.Chunk]] = [:]
    private var revisions: [String: UUID] = [:]
    private var order: [String] = []
    private var submittedCharacters: [String: Int] = [:]
    private var reusedClauses: [String: Int] = [:]
    func statistics(identity: String, source: String, target: String, configuration: LocalTranslationConfiguration) -> (Int, Int) {
        let key = identity + "\t" + source + "\t" + target + "\t" + configuration.baseURL + "\t" + configuration.modelID
        return (submittedCharacters[key] ?? 0, reusedClauses[key] ?? 0)
    }
    private let client: LocalTranslationService
    init(client: LocalTranslationService = .shared) { self.client = client }

    func translate(_ text: String, identity: String, source: String, target: String,
                   configuration: LocalTranslationConfiguration, apiKey: String?,
                   punctuation: LocalTranslationService.Progress? = nil,
                   progress: @escaping LocalTranslationService.Progress) async throws -> String {
        let key = identity + "\t" + source + "\t" + target + "\t" + configuration.baseURL + "\t" + configuration.modelID
        let revision = UUID()
        revisions[key] = revision
        if !order.contains(key) { order.append(key) }
        while order.count > 32 {
            let old = order.removeFirst(); previous[old] = nil; revisions[old] = nil; submittedCharacters[old] = nil; reusedClauses[old] = nil
        }
        let plan = IncrementalCaptionPlan(text: text, previous: previous[key] ?? [])
        reusedClauses[key, default: 0] += plan.reusable.count
        var completed = plan.reusable
        previous[key] = completed
        func rendered(_ chunks: [IncrementalCaptionPlan.Chunk]) -> String {
            chunks.map(\.translation).filter { !$0.isEmpty }.joined(separator: "\n")
        }
        for index in completed.count..<plan.blocks.count {
            try Task.checkCancellation()
            guard revisions[key] == revision else { throw CancellationError() }
            let block = plan.blocks[index]
            let prefix = rendered(completed)
            let before = String(plan.blocks.prefix(index).joined().suffix(100))
            let after = IncrementalCaptionPlan.following(plan.blocks, at: index)
            let context = before.isEmpty && after.isEmpty ? "" : "Before: " + before + "\nAfter: " + after
            submittedCharacters[key, default: 0] += block.count
            let translated = try await client.translate(block, source: source, target: target,
                configuration: configuration, apiKey: apiKey,
                context: context,
                progress: { partial in
                    let value = [prefix, partial].filter { !$0.isEmpty }.joined(separator: "\n")
                    if !value.isEmpty { progress(value) }
                })
            try Task.checkCancellation()
            guard revisions[key] == revision else { throw CancellationError() }
            let punctuated = source.hasPrefix("ja") ? await client.punctuatedSource(block, configuration: configuration) : nil
            completed.append(.init(source: block, translation: translated, followingContext: after, punctuatedSource: punctuated))
            previous[key] = completed
        }
        let result = rendered(completed)
        if !result.isEmpty { await progress(result) }
        if let punctuation, completed.contains(where: { $0.punctuatedSource != nil }) {
            await punctuation(completed.map { $0.punctuatedSource ?? $0.source }.joined())
        }
        return result
    }
}
