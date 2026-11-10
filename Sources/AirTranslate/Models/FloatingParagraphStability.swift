import Foundation

/// A presentation-only latch. Recognition and transcript history retain every revision.
struct FloatingParagraphStability {
    struct Channel {
        private(set) var text = ""
        private var pending = ""
        private var lastPresented: TimeInterval = 0
        private var pendingSince: TimeInterval = 0

        mutating func receive(_ value: String, final: Bool, now: TimeInterval, minimumFirstLength: Int = 1) {
            if value != pending { pendingSince = now }
            pending = value
            guard !value.isEmpty else { return }
            if final || (text.isEmpty && value.count >= minimumFirstLength) {
                if value != text { text = value; lastPresented = now }
                return
            }
            advance(now: now)
        }

        mutating func advance(now: TimeInterval) {
            // Short standalone translations must not remain hidden indefinitely.
            if text.isEmpty, !pending.isEmpty, now - pendingSince >= 0.5 {
                text = pending; lastPresented = now; return
            }
            // Never patch already visible words mid-sentence. Only extend an exact prefix.
            guard !text.isEmpty, now - lastPresented >= 0.5,
                  pending.hasPrefix(text), pending.count >= text.count + 2 else { return }
            text = pending
            lastPresented = now
        }
    }
    var source = Channel()
    var translation = Channel()
}
