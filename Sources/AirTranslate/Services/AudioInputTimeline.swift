import Foundation

/// Maps analyzer-relative audio time to the monotonic arrival time of the input frames.
final class AudioInputTimeline: @unchecked Sendable {
    private struct Span { let start: Double; let end: Double; let arrival: Double }
    private let lock = NSLock()
    private var spans: [Span] = []
    private var duration: Double = 0
    func reset() { lock.withLock { spans.removeAll(); duration = 0 } }
    func append(duration seconds: Double, arrival: Double = ProcessInfo.processInfo.systemUptime) {
        guard seconds.isFinite, seconds > 0 else { return }
        lock.withLock {
            spans.append(Span(start: duration, end: duration + seconds, arrival: arrival))
            duration += seconds
            if spans.count > 2400 { spans.removeFirst(spans.count - 2400) }
        }
    }
    func uptime(at audioEnd: Double) -> Double? {
        guard audioEnd.isFinite, audioEnd > 0 else { return nil }
        return lock.withLock {
            guard let span = spans.last(where: { audioEnd >= $0.start && audioEnd <= $0.end + 0.002 }) else { return nil }
            return span.arrival - max(0, span.end - audioEnd)
        }
    }
}

struct CaptionLatencyReading: Sendable {
    let recognitionMS: Double?
    let queueMS: Double?
    let translationFirstMS: Double?
    let frameToTranslationMS: Double?
}
