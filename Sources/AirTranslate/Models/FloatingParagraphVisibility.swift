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
            if !requiresTranslation { expiresAt = now + 1 }
        }
        if requiresTranslation && hasTranslation && !sawTranslation {
            sawTranslation = true
            expiresAt = min(expiresAt ?? .infinity, now + 1)
        }
        if let expiresAt, now >= expiresAt { hidesPrevious = true }
    }

    func visibleIDs(recent: [UUID], retainedTranslationID: UUID?,
                    latestHasTranslation: Bool, requiresTranslation: Bool) -> [UUID] {
        if requiresTranslation, !latestHasTranslation,
           let latest = recent.last, let retainedTranslationID, retainedTranslationID != latest {
            return [retainedTranslationID, latest]
        }
        return hidesPrevious ? Array(recent.suffix(1)) : recent
    }
}
