import Foundation

struct FloatingParagraphVisibility {
    private(set) var latestID: UUID?
    private(set) var hidesPrevious = false
    private var expiresAt: TimeInterval?
    private var sawSource = false
    private var sawTranslation = false

    mutating func update(latestID: UUID?, hasSource: Bool, hasTranslation: Bool,
                         requiresTranslation: Bool, now: TimeInterval) {
        if self.latestID != latestID {
            self.latestID = latestID; hidesPrevious = false; expiresAt = nil
            sawSource = false; sawTranslation = false
        }
        guard latestID != nil else { return }
        if hasSource && !sawSource {
            sawSource = true
            expiresAt = now + (requiresTranslation ? 2 : 1)
        }
        if hasTranslation && !sawTranslation {
            sawTranslation = true
            expiresAt = min(expiresAt ?? .infinity, now + 1)
        }
        if let expiresAt, now >= expiresAt { hidesPrevious = true }
    }
}
