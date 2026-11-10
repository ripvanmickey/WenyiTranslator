import SwiftUI

/// Daily controls only. Providers, recognition models and speech engines live in Settings.
struct ProcessingModePicker: View {
    @Bindable var session: TranslationSessionStore
    @Environment(\.openSettings) private var openSettings
    @State private var isPresented = false
    private var locked: Bool { session.isRunning || session.isStarting }
    private var supportsOutputSwitch: Bool {
        switch ProcessingEngine.current(for: session) {
        case .apple, .openAI, .nari, .grok: true
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
        Button { isPresented.toggle() } label: {
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
        .buttonStyle(.plain)
        .airFocusRing(cornerRadius: 12)
        .help(QuickOutputCopy.title)
        .accessibilityLabel(QuickOutputCopy.title)
        .accessibilityIdentifier("quickOutputControls")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(AppText.outputMode)
                    Spacer()
                    Picker(AppText.outputMode, selection: outputSelection) {
                        ForEach(LiveOutputMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .labelsHidden().pickerStyle(.menu)
                    .frame(width: 165)
                    .disabled(locked || !supportsOutputSwitch)
                }
                if locked {
                    Text(AppText.lockedDuringSession).font(.caption).foregroundStyle(.secondary)
                } else if !supportsOutputSwitch {
                    Text(QuickOutputCopy.providerOutput).font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                HStack {
                    Text(QuickOutputCopy.configurationHint).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(AppText.openSettings) {
                        session.requestedSettingsCategoryID = "output"
                        isPresented = false
                        openSettings()
                    }
                }
            }
            .padding(18).frame(width: 330)
        }
    }
}

private enum QuickOutputCopy {
    static let title = AppText.localized(english: "Caption output", korean: "자막 출력", japanese: "字幕出力", chineseSimplified: "字幕输出")
    static let configurationHint = AppText.localized(english: "Configure engines and models in Settings.", korean: "엔진과 모델은 설정에서 구성합니다.", japanese: "エンジンとモデルは設定で変更できます。", chineseSimplified: "引擎和模型请在设置中配置。")
    static let providerOutput = AppText.localized(english: "Change this service's output in Settings.", korean: "이 서비스의 출력은 설정에서 변경합니다.", japanese: "このサービスの出力は設定で変更できます。", chineseSimplified: "当前服务的字幕输出方式请在设置中调整。")
}
