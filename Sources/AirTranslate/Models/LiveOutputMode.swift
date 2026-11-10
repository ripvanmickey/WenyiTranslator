import Foundation

enum LiveOutputMode: String, CaseIterable, Identifiable {
    case translation
    case transcription

    var id: String { rawValue }

    var title: String {
        switch self {
        case .translation:
            AppText.originalAndTranslation
        case .transcription:
            AppText.originalOnly
        }
    }

    var systemImage: String {
        switch self {
        case .translation:
            "character.bubble"
        case .transcription:
            "waveform"
        }
    }
}
