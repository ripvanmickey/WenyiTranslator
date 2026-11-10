import Foundation
import CoreMedia
struct LanguageOption: Equatable, Sendable { let id: String }
@main struct PolicyChecks {
    static func main() {
        let start = Date(timeIntervalSince1970: 100)
        let line = UUID()
        let metadata = AppleSpeechRecognitionMetadata(segmentID: "ja", revision: 1, isFinal: false,
            audioRange: CMTimeRange(start: .zero, duration: CMTime(seconds: 1, preferredTimescale: 1000)),
            sourceText: "今日は", emittedAt: start)
        let fast = AppleRecognitionTranslationPolicy(partialCadence: 0.25, smallPartialSilenceFallback: 0.25)
        var fastState = AppleRecognitionTranslationPolicy.State()
        var originalState = AppleRecognitionTranslationPolicy.State()
        let original = AppleRecognitionTranslationPolicy()
        guard case .hold = fast.receive(sourceText: "今日は", lineID: line, metadata: metadata, now: start, state: &fastState) else { fatalError("Expected initial short-fragment hold") }
        _ = original.receive(sourceText: "今日は", lineID: line, metadata: metadata, now: start, state: &originalState)
        guard case .requestNow = fast.flushSmallPartial(lineID: line, metadata: metadata, now: start.addingTimeInterval(0.26), state: &fastState) else { fatalError("Local request was not released at 250 ms") }
        guard case .hold = original.flushSmallPartial(lineID: line, metadata: metadata, now: start.addingTimeInterval(0.26), state: &originalState) else { fatalError("Other engines changed") }
        let request = AppleTranslationRequestIdentity(lineID: line, sourceText: "今日は", segmentID: "ja", revision: 1, isFinal: false)
        let current = AppleTranslationLineIdentity(lineID: line, sourceText: "今日は天気がいい", segmentID: "ja", revision: 2, isFinal: false)
        precondition(fast.acceptsTranslationResult(request: request, current: current))
        let corrected = AppleTranslationLineIdentity(lineID: line, sourceText: "昨日は雨でした", segmentID: "ja", revision: 2, isFinal: false)
        precondition(!fast.acceptsTranslationResult(request: request, current: corrected))
        print("PASS local short-fragment release at 250 ms, original timing unchanged, compatible preview accepted, corrected source rejects stale translation")
    }
}
