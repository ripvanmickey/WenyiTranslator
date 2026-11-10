import Foundation

enum NariTranscriptionModel: String, CaseIterable, Identifiable, Sendable {
    case off
    case qwen3ASRFree = "qwen3-asr:free"
    case qwen3ASRFastFree = "qwen3-asr-fast:free"
    case qwen3ASR = "qwen3-asr"
    case qwen3ASRFast = "qwen3-asr-fast"

    static let selectableCases: [NariTranscriptionModel] = [
        .qwen3ASRFast, .qwen3ASR, .qwen3ASRFastFree, .qwen3ASRFree,
    ]

    // Nari session.configure의 공식 언어 코드 목록.
    static let supportedLanguageCodes: Set<String> = [
        "ar", "cs", "da", "de", "el", "en", "es", "fa", "fi", "fil",
        "fr", "hi", "hu", "id", "it", "ja", "ko", "mk", "ms", "nl",
        "pl", "pt", "ro", "ru", "sv", "th", "tr", "vi", "yue", "zh",
    ]

    var id: String { rawValue }
    var isEnabled: Bool { self != .off }
    var isLegacyFreeEndpoint: Bool { self == .qwen3ASRFree || self == .qwen3ASRFastFree }
    var canStart: Bool { isEnabled && !isLegacyFreeEndpoint }
    var apiModelID: String { isEnabled ? rawValue : "" }

    var title: String {
        switch self {
        case .off: AppText.localized(english: "Off", korean: "끔", japanese: "オフ", chineseSimplified: "关闭")
        case .qwen3ASRFree: AppText.localized(english: "Qwen3-ASR · Free Public Beta ended", korean: "Qwen3-ASR · Free Public Beta ended", chineseSimplified: "Qwen3-ASR · 免费公开测试已结束")
        case .qwen3ASRFastFree: AppText.localized(english: "Qwen3-ASR Fast · Free Public Beta ended", korean: "Qwen3-ASR Fast · Free Public Beta ended", chineseSimplified: "Qwen3-ASR Fast · 免费公开测试已结束")
        case .qwen3ASR: AppText.localized(english: "Qwen3-ASR · GA · credits", korean: "Qwen3-ASR · GA · credits", chineseSimplified: "Qwen3-ASR · 正式版 · 使用额度")
        case .qwen3ASRFast: AppText.localized(english: "Qwen3-ASR Fast · GA · credits", korean: "Qwen3-ASR Fast · GA · credits", chineseSimplified: "Qwen3-ASR Fast · 正式版 · 使用额度")
        }
    }

    var billingSummary: String {
        switch self {
        case .off: ""
        case .qwen3ASRFree, .qwen3ASRFastFree:
            NariCopy.legacyFreeModelEnded
        case .qwen3ASR:
            NariCopy.standardBilling
        case .qwen3ASRFast:
            NariCopy.fastBilling
        }
    }

    static func languageCode(for language: LanguageOption) -> String? {
        let primary = language.id.lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-").first.map(String.init) ?? ""
        let code = primary == "tl" ? "fil" : primary
        return supportedLanguageCodes.contains(code) ? code : nil
    }
}
