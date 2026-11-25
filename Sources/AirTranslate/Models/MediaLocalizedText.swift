import Foundation

/// Store all translations for progress messages so changing the app language
/// also updates messages that were produced before the language changed.
struct MediaLocalizedText: Sendable {
    let chinese: String
    let english: String
    let japanese: String
    init(_ chinese: String, _ english: String, _ japanese: String) {
        self.chinese = chinese; self.english = english; self.japanese = japanese
    }
    init(verbatim text: String) { self.init(text, text, text) }
    var value: String { AppText.ui(chinese, english, japanese) }
}

struct ConsoleLayoutMetrics {
    let inputWidth: CGFloat
    let outputWidth: CGFloat
    let captionMinimumWidth: CGFloat
    static var current: Self { forLanguage(InterfaceLocalization.interfaceLanguage) }
    static func forLanguage(_ language: InterfaceLocalization.InterfaceLanguage) -> Self {
        switch language {
        case .english, .korean: .init(inputWidth: 300, outputWidth: 240, captionMinimumWidth: 1000)
        case .japanese: .init(inputWidth: 270, outputWidth: 210, captionMinimumWidth: 940)
        case .chineseSimplified: .init(inputWidth: 246, outputWidth: 180, captionMinimumWidth: 900)
        }
    }
    static var originalOnly: String { AppText.ui("仅原文", "Original Only", "原文のみ") }
    static var bilingual: String { AppText.ui("原文 + 译文", "Bilingual", "原文 + 訳文") }
}
