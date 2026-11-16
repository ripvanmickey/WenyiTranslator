import Foundation

enum AppInterfaceLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case japanese = "ja"
    case chineseSimplified = "zh-Hans"

    static let preferenceKey = "wenyiInterfaceLanguage"
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: InterfaceLocalization.ui("跟随系统", "System", "システムに従う")
        case .english: "English"
        case .japanese: "日本語"
        case .chineseSimplified: "简体中文"
        }
    }
}

enum InterfaceLocalization {
    enum InterfaceLanguage {
        case english, korean, japanese, chineseSimplified
    }

    static let launchLanguage = AppInterfaceLanguage(
        rawValue: UserDefaults.standard.string(forKey: AppInterfaceLanguage.preferenceKey) ?? ""
    ) ?? .system

    // Existing copy is cached for the duration of a launch, including native menu titles.
    static let interfaceLanguage: InterfaceLanguage = {
        switch launchLanguage {
        case .english: return .english
        case .japanese: return .japanese
        case .chineseSimplified: return .chineseSimplified
        case .system: break
        }
        if ProcessInfo.processInfo.environment["AIRTRANSLATE_PRODUCT_HUNT_SCREENSHOTS"] == "1" {
            return .english
        }
        let languageCode = Locale.preferredLanguages.first?.lowercased() ?? ""
        if languageCode.hasPrefix("ko") { return .korean }
        if languageCode.hasPrefix("ja") { return .japanese }
        if languageCode.hasPrefix("zh") { return .chineseSimplified }
        return .english
    }()

    static var interfaceLocale: Locale {
        switch interfaceLanguage {
        case .english: Locale(identifier: "en")
        case .japanese: Locale(identifier: "ja")
        case .chineseSimplified: Locale(identifier: "zh-Hans")
        case .korean: Locale(identifier: "ko")
        }
    }

    static func ui(_ chinese: String, _ english: String, _ japanese: String) -> String {
        switch interfaceLanguage {
        case .english, .korean: english
        case .japanese: japanese
        case .chineseSimplified: chinese
        }
    }
}
