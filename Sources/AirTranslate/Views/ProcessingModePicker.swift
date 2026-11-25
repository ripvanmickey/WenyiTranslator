import SwiftUI

/// Daily controls only. Providers, recognition models and speech engines live in Settings.
struct ProcessingModePicker: View {
    @Bindable var session: TranslationSessionStore
    private var locked: Bool { session.isRunning || session.isStarting }
    private var supportsOutputSwitch: Bool {
        switch ProcessingEngine.current(for: session) {
        case .apple, .indexOnline, .openAI, .nari, .grok: true
        default: false
        }
    }
    private var canChangeOutput: Bool { !locked && supportsOutputSwitch }

    private var outputSelection: Binding<LiveOutputMode> {
        Binding(get: { session.liveOutputMode }, set: { mode in
            guard canChangeOutput else { return }
            session.useLiveOutputMode(mode)
        })
    }
    var body: some View {
        Picker(QuickOutputCopy.title, selection: outputSelection) {
            Text(ConsoleLayoutMetrics.originalOnly).tag(LiveOutputMode.transcription)
            Text(ConsoleLayoutMetrics.bilingual).tag(LiveOutputMode.translation)
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .labelsHidden()
        .frame(width: ConsoleLayoutMetrics.current.outputWidth)
        .allowsHitTesting(canChangeOutput)
        .accessibilityRespondsToUserInteraction(canChangeOutput)
        .opacity(canChangeOutput ? 1 : 0.6)
        .help(locked ? AppText.lockedDuringSession : supportsOutputSwitch ? QuickOutputCopy.title : QuickOutputCopy.providerOutput)
        .accessibilityLabel(QuickOutputCopy.title)
        .accessibilityIdentifier("quickOutputControls")
    }
}

private enum QuickOutputCopy {
    static var title: String { AppText.localized(english: "Caption output", korean: "자막 출력", japanese: "字幕出力", chineseSimplified: "字幕输出") }
    static var originalOnly: String { AppText.localized(english: "Original Only", korean: "원문만", japanese: "原文のみ", chineseSimplified: "仅原文") }
    static var providerOutput: String { AppText.localized(english: "Change this service's output in Settings.", korean: "이 서비스의 출력은 설정에서 변경합니다.", japanese: "このサービスの出力は設定で変更できます。", chineseSimplified: "当前服务的字幕输出方式请在设置中调整。") }
}
