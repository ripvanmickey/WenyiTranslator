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
    private var outputSelection: Binding<LiveOutputMode> {
        Binding(get: { session.liveOutputMode }, set: { mode in
            guard !locked, supportsOutputSwitch else { return }
            session.useLiveOutputMode(mode)
        })
    }
    var body: some View {
        Menu {
            Picker(QuickOutputCopy.title, selection: outputSelection) {
                ForEach(LiveOutputMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .disabled(locked || !supportsOutputSwitch)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "captions.bubble")
                Text(QuickOutputCopy.title)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(AirTranslateDesign.Typography.label)
            .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .airFocusRing(cornerRadius: 12)
        .help(locked ? AppText.lockedDuringSession : supportsOutputSwitch ? QuickOutputCopy.title : QuickOutputCopy.providerOutput)
        .accessibilityLabel(QuickOutputCopy.title)
        .accessibilityValue(session.liveOutputMode.title)
        .accessibilityIdentifier("quickOutputControls")
    }
}

private enum QuickOutputCopy {
    static var title: String { AppText.localized(english: "Caption output", korean: "자막 출력", japanese: "字幕出力", chineseSimplified: "字幕输出") }
    static var providerOutput: String { AppText.localized(english: "Change this service's output in Settings.", korean: "이 서비스의 출력은 설정에서 변경합니다.", japanese: "このサービスの出力は設定で変更できます。", chineseSimplified: "当前服务的字幕输出方式请在设置中调整。") }
}
