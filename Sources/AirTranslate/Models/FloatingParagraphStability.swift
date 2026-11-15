import Foundation

/// Keeps the first visible caption and publishes at most one confirmed replacement.
struct FirstAndFinalCaptionText {
    private(set) var text = ""
    private var didConfirm = false

    mutating func receive(_ value: String, confirmed: Bool) {
        guard !didConfirm, !value.isEmpty else { return }
        if text.isEmpty || confirmed { text = value }
        if confirmed { didConfirm = true }
    }
}

/// A presentation-only latch. Recognition and transcript history retain every revision.
struct FloatingParagraphStability {
    struct Channel {
        private(set) var text = ""
        private var pending = ""
        private var lastPresented: TimeInterval = 0
        private var pendingSince: TimeInterval = 0
        private var confirmedText = FirstAndFinalCaptionText()

        mutating func receive(_ value: String, final: Bool, now: TimeInterval, minimumFirstLength: Int = 1,
                              firstAndFinal: Bool = false) {
            if value != pending { pendingSince = now }
            pending = value
            guard !value.isEmpty else { return }
            if firstAndFinal {
                if final || value.count >= minimumFirstLength || now - pendingSince >= 0.5 {
                    confirmedText.receive(value, confirmed: final)
                    text = confirmedText.text
                }
                return
            }
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
