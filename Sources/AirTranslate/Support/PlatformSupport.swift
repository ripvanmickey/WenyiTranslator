import Foundation

enum PlatformSupport {
    static var supportsAudioTap: Bool {
        if #available(macOS 14.2, *) { return true }
        return false
    }
    static var supportsWritingTools: Bool {
        if #available(macOS 15.2, *) { return true }
        return false
    }
    static var supportsAppleSpeech: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
    static var appleFeatureUnavailable: NSError {
        NSError(domain: "Wenyi.Platform", code: 26, userInfo: [NSLocalizedDescriptionKey: "此 Apple 功能需要 macOS 26。请使用 Nemotron、Granite 或 Qwen 本地识别，并配置 LM Studio 翻译。"])
    }
}
