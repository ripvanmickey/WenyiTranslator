import SwiftUI

// Kept as a compatibility wrapper for call sites outside the main window.
struct SidebarView: View {
    @Bindable var session: TranslationSessionStore

    var body: some View {
        ConsoleBarView(session: session)
    }
}

enum SidebarSessionConfigurationAccess {
    static func isLocked(isRunning: Bool, isStarting: Bool) -> Bool {
        isRunning || isStarting
    }

    static func segmentedControlPresentation(
        isRunning: Bool,
        isStarting: Bool
    ) -> SidebarSegmentedControlPresentation {
        isLocked(isRunning: isRunning, isStarting: isStarting) ? .lockedSummary : .picker
    }
}

enum SidebarSegmentedControlPresentation: Equatable {
    case picker
    case lockedSummary
}

enum ProcessingEngine: String, CaseIterable, Identifiable {
    case apple
    case indexOnline
    case openAI
    case gemini
    case meta
    case azure
    case nari
    case grok
    case qwen

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: AppText.appleProcessingMode
        case .indexOnline: AppText.localized(
            english: "Index online translation (Bilibili, free & open source)",
            korean: "Index 온라인 번역 (빌리빌리, 무료·오픈 소스)",
            japanese: "Index オンライン翻訳（Bilibili、無料・オープンソース）",
            chineseSimplified: "Index 在线翻译（B 站免费开源）"
        )
        case .openAI: AppText.openAIAudio
        case .gemini: AppText.geminiModels
        case .azure: AzureMAICopy.title
        case .qwen: QwenCopy.title
        case .grok: GrokCopy.title
        case .nari: NariCopy.title
        case .meta: AppText.metaScribe
        }
    }

    @MainActor
    static func current(for session: TranslationSessionStore) -> ProcessingEngine {
        if session.isUsingQwenTranslation { return .qwen }
        if session.isUsingGrokSTT { return .grok }
        if session.isUsingNariSTT { return .nari }
        if session.isUsingAzureMAI { return .azure }
        if session.isUsingMetaScribe { return .meta }
        if session.openAITranscriptionModel.isEnabled || session.openAITranslationModel.isEnabled {
            return .openAI
        }
        if session.isUsingGemini { return .gemini }
        return session.localTranslation.usesOnlineIndex ? .indexOnline : .apple
    }
}

struct StageHeaderView: View {
    @Bindable var session: TranslationSessionStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: AirTranslateDesign.Spacing.sm) {
            SessionStatusPill(session: session)

            languageMenu

            Spacer(minLength: AirTranslateDesign.Spacing.sm)

            Button {
                if needsAPIKey {
                    session.requestAPIKeySettings()
                }
                openSettings()
            } label: {
                Label(session.processingEngineTitle, systemImage: needsAPIKey ? "key.fill" : "cpu")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(
                        needsAPIKey ? AirTranslateDesign.Palette.warning : AirTranslateDesign.Palette.textSecondary
                    )
                    .lineLimit(1)
                    .padding(.horizontal, AirTranslateDesign.Spacing.xs)
                    .frame(minHeight: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .airFocusRing(cornerRadius: 12)
            .help(needsAPIKey ? missingAPIKeyTitle : AppText.configureTranslationSettings)
            .accessibilityLabel(AppText.translationSettings)
            .accessibilityValue(
                needsAPIKey
                    ? "\(session.processingEngineTitle), \(missingAPIKeyTitle)"
                    : session.processingEngineTitle
            )

            if session.isUsingMetaScribe && session.isMetaSpeakerLabelsEnabled {
                AirChip(
                    text: AppText.speakerLabelsOn,
                    systemImage: "person.2.fill",
                    tint: AirTranslateDesign.Palette.textSecondary
                )
            }

            PermissionActionButton(session: session)
        }
        .padding(.horizontal, AirTranslateDesign.Spacing.lg)
        .frame(minHeight: 44)
        .background(AirTranslateDesign.Palette.canvas)
    }

    private var canChangeLanguage: Bool {
        !SidebarSessionConfigurationAccess.isLocked(isRunning: session.isRunning, isStarting: session.isStarting)
    }

    private var languageMenu: some View {
        Menu {
            if usesAutomaticSource {
                Text(AppText.autoDetectInput)
            } else {
                Picker(AppText.from, selection: sourceLanguageBinding) {
                    ForEach(LanguageOption.supported) { language in
                        Text(language.localizedTitle).tag(language)
                    }
                }
            }

            if !session.isTranscribeOnlyMode {
                Picker(AppText.to, selection: targetLanguageBinding) {
                    ForEach(LanguageOption.supported.filter { usesAutomaticSource || $0 != session.sourceLanguage }) { language in
                        Text(language.localizedTitle).tag(language)
                    }
                }

                if !usesAutomaticSource {
                    Button(AppText.swapLanguages, systemImage: "arrow.left.arrow.right") {
                        guard canChangeLanguage else { return }
                        session.swapQuickLanguagePair()
                    }
                }
            }
        } label: {
            Label(session.languageSummary, systemImage: "arrow.triangle.swap")
                .font(AirTranslateDesign.Typography.label)
                .foregroundStyle(AirTranslateDesign.Palette.textPrimary)
                .lineLimit(1)
                .frame(minHeight: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.visible)
        .airFocusRing(cornerRadius: 12)
        .disabled(!canChangeLanguage)
        .help(canChangeLanguage ? AppText.languagePair : AppText.lockedDuringSession)
        .accessibilityLabel(AppText.languagePair)
        .accessibilityValue(session.languageSummary)
        .accessibilityIdentifier("quickLanguagePair")
    }

    private var sourceLanguageBinding: Binding<LanguageOption> {
        Binding(
            get: { session.sourceLanguage },
            set: { language in
                guard canChangeLanguage else { return }
                session.useQuickSourceLanguage(language)
            }
        )
    }

    private var targetLanguageBinding: Binding<LanguageOption> {
        Binding(
            get: { session.targetLanguage },
            set: { language in
                guard canChangeLanguage else { return }
                session.useQuickTargetLanguage(language)
            }
        )
    }

    private var usesOpenAIAutoLanguageFlow: Bool {
        ProcessingEngine.current(for: session) == .openAI && session.isUsingOpenAIRealtimeTranslation
    }

    private var usesAutomaticSource: Bool {
        if session.isUsingQwenTranslation { return true }
        if session.isUsingGrokSTT { return session.isGrokSourceAutoDetectionEnabled }
        if session.isUsingNariSTT { return session.isNariSourceAutoDetectionEnabled }
        return session.isAppleSourceAutoDetectionEnabled
            || usesOpenAIAutoLanguageFlow
            || session.isUsingGeminiTranscriptionMode
            || session.isUsingMetaScribe
    }

    private var needsAPIKey: Bool {
        switch ProcessingEngine.current(for: session) {
        case .openAI: !session.hasOpenAIAPIKey
        case .gemini: !session.hasGeminiAPIKey
        case .azure: !session.hasAzureSpeechAPIKey || !session.hasAzureConfiguration
        case .qwen: !session.hasQwenConfiguration
        case .grok: !session.hasGrokAPIKey
        case .nari: !session.hasNariAPIKey
        case .meta: !session.hasMetaAPIKey
        case .apple: session.isUsingJevSelection && !session.hasJevAPIKey
        case .indexOnline: false
        }
    }

    private var missingAPIKeyTitle: String {
        switch ProcessingEngine.current(for: session) {
        case .openAI: AppText.openAIAPIKeyNotConfigured
        case .gemini: AppText.geminiAPIKeyNotConfigured
        case .azure: AzureMAICopy.configurationRequired
        case .qwen: QwenCopy.configurationRequired(for: session.qwenTranslationModel.isEnabled ? session.qwenTranslationModel : session.preferredQwenModel)
        case .grok: GrokCopy.configurationRequired
        case .nari: NariCopy.configurationRequired
        case .meta: AppText.metaAPIKeyNotConfigured
        case .apple: session.isUsingJevSelection ? JevCopy.keyRequired : AppText.configureTranslationSettings
        case .indexOnline: AppText.configureTranslationSettings
        }
    }
}

struct ConsoleBarView: View {
    @Bindable var session: TranslationSessionStore
    @Environment(\.openSettings) private var openSettings
    @FocusState private var isCaptureFocused: Bool

    var body: some View {
        consoleControls
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                isCaptureFocused = true
            }
            session.refreshModelAvailability()
            guard isConfigurationAvailable else { return }
            session.refreshMicrophoneInputDevices()
            if session.isUsingOpenAIRealtimeTranslation, ProcessingEngine.current(for: session) == .openAI {
                session.usePreferredLanguageForOpenAIOutput()
            }
        }
    }

    private var consoleControls: some View {
        HStack(spacing: AirTranslateDesign.Spacing.sm) {
            captureButton
            pauseButton

            consoleDivider
            if !isConfigurationAvailable {
                lockGroupIndicator
            }
            audioSourceControl

            if session.audioInputSource == .microphone {
                microphoneControl
            }

            Spacer(minLength: 0)
            ProcessingModePicker(session: session)
        }
        .padding(.horizontal, AirTranslateDesign.Spacing.sm)
        .padding(.vertical, AirTranslateDesign.Spacing.xs)
        .frame(maxWidth: 1120)
    }

    private var captureButton: some View {
        Button {
            if session.isRunning || session.isStarting {
                session.stop()
            } else {
                session.start()
            }
        } label: {
            HStack(spacing: AirTranslateDesign.Spacing.xs) {
                if session.captureControlState.phase.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: session.captureControlState.phase.actionSystemImage)
                }

                Text(captureTitle)
                    .lineLimit(1)

                if session.captureControlState.phase == .running {
                    AudioLevelWaveform(
                        level: session.latestAudioLevel,
                        date: Date(),
                        barCount: 5,
                        width: 40,
                        height: 14,
                        barWidth: 3,
                        barSpacing: 2.5,
                        tint: AirTranslateDesign.Palette.danger
                    )
                }
            }
        }
        .buttonStyle(AirPillButtonStyle(kind: captureButtonKind))
        .disabled(!session.captureControlState.canToggleCapture)
        .airFocusRing(cornerRadius: 22, focus: $isCaptureFocused)
        .defaultFocus($isCaptureFocused, true)
        .help(captureTitle)
        .accessibilityLabel(captureTitle)
        .accessibilityValue(captureStateDescription)
    }

    private var pauseButton: some View {
        Button {
            session.isPaused ? session.resume() : session.pause()
        } label: {
            Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
        }
        .buttonStyle(AirIconButton())
        .airFocusRing(cornerRadius: 18)
        .disabled(!session.captureControlState.canTogglePause)
        .help(session.isPaused ? AppText.resume : AppText.pause)
        .accessibilityLabel(session.isPaused ? AppText.resume : AppText.pause)
    }

    @ViewBuilder
    private var audioSourceControl: some View {
        if segmentedControlPresentation == .lockedSummary {
            LockedConsoleSummary(
                title: AppText.audioInputSource,
                value: session.audioInputSource.title,
                systemImage: session.audioInputSource == .microphone ? "mic.fill" : "speaker.wave.2.fill"
            )
        } else {
            Picker(AppText.audioInputSource, selection: audioInputSourceBinding) {
                ForEach(AudioInputSource.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.large)
            .labelsHidden()
            .frame(width: 168)
            .disabled(!isConfigurationAvailable)
            .accessibilityLabel(AppText.audioInputSource)
        }
    }

    @ViewBuilder
    private var microphoneControl: some View {
        if segmentedControlPresentation == .lockedSummary {
            LockedConsoleSummary(
                title: AppText.microphoneInputDevice,
                value: selectedMicrophoneName,
                systemImage: "mic.circle.fill"
            )
        } else {
            Menu {
                ForEach(session.microphoneInputDevices) { device in
                    Button(device.name) {
                        guard isConfigurationAvailable else { return }
                        session.selectedMicrophoneInputDeviceID = device.id
                    }
                }
            } label: {
                Label(selectedMicrophoneName, systemImage: "mic.circle.fill")
                    .font(AirTranslateDesign.Typography.label)
                    .lineLimit(1)
                    .frame(maxWidth: 128)
            }
            .menuIndicator(.hidden)
            .airFocusRing(cornerRadius: AirTranslateDesign.Radius.control)
            .allowsHitTesting(isConfigurationAvailable)
            .accessibilityRespondsToUserInteraction(isConfigurationAvailable)
            .accessibilityLabel(AppText.microphoneInputDevice)
            .accessibilityValue(selectedMicrophoneName)
        }
    }

    private var consoleDivider: some View {
        Rectangle()
            .fill(AirTranslateDesign.Palette.hairline)
            .frame(width: 1, height: 28)
    }

    private var lockGroupIndicator: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AirTranslateDesign.Palette.textTertiary)
            .help(AppText.lockedDuringSession)
            .accessibilityLabel(AppText.lockedDuringSession)
    }

    private var isConfigurationAvailable: Bool {
        !SidebarSessionConfigurationAccess.isLocked(
            isRunning: session.isRunning,
            isStarting: session.isStarting
        )
    }

    private var segmentedControlPresentation: SidebarSegmentedControlPresentation {
        SidebarSessionConfigurationAccess.segmentedControlPresentation(
            isRunning: session.isRunning,
            isStarting: session.isStarting
        )
    }

    private var captureTitle: String {
        session.captureControlState.phase.actionTitle
    }

    private var captureStateDescription: String {
        session.captureControlState.statusTitle(statusMessage: session.statusMessage)
    }

    private var captureButtonKind: AirPillButtonKind {
        if session.captureControlState.phase == .paused { return .paused }
        if session.isRunning || session.isStarting { return .stop }
        return .start
    }

    private var audioInputSourceBinding: Binding<AudioInputSource> {
        Binding(
            get: { session.audioInputSource },
            set: { source in
                guard isConfigurationAvailable else { return }
                session.audioInputSource = source
            }
        )
    }

    private var selectedMicrophoneName: String {
        session.microphoneInputDevices.first { $0.id == session.selectedMicrophoneInputDeviceID }?.name
            ?? MicrophoneInputDevice.systemDefault.name
    }


}

private struct SessionStatusPill: View {
    let session: TranslationSessionStore

    var body: some View {
        AirChip(text: title, systemImage: symbolName, tint: tint)
            .help(session.statusMessage)
            .accessibilityLabel(title)
            .accessibilityValue(session.statusMessage)
    }

    private var title: String {
        session.captureControlState.statusTitle(statusMessage: session.statusMessage)
    }

    private var symbolName: String {
        switch session.captureControlState.phase {
        case .starting, .finishing: "hourglass.circle.fill"
        case .reconnecting: "arrow.triangle.2.circlepath"
        case .paused: "pause.circle.fill"
        case .running: "waveform.circle.fill"
        case .idle: session.statusMessage == AppText.ready ? "checkmark.circle.fill" : "circle.dotted"
        }
    }

    private var tint: Color {
        switch session.captureControlState.phase {
        case .starting, .finishing, .reconnecting, .paused:
            AirTranslateDesign.Palette.paused
        case .running:
            AirTranslateDesign.Palette.live
        case .idle:
            session.statusMessage == AppText.ready
                ? AirTranslateDesign.Palette.live : AirTranslateDesign.Palette.textSecondary
        }
    }
}

struct PermissionActionButton: View {
    let session: TranslationSessionStore

    var body: some View {
        if needsPermissionAction {
            Button {
                session.openPrivacySettings()
            } label: {
                Label(AppText.openPrivacySettings, systemImage: "lock.shield.fill")
                    .font(AirTranslateDesign.Typography.label)
                    .foregroundStyle(AirTranslateDesign.Palette.warning)
            }
            .buttonStyle(.plain)
            .airFocusRing(cornerRadius: AirTranslateDesign.Radius.control)
            .help(AppText.openPrivacySettings)
            .accessibilityLabel(AppText.openPrivacySettings)
        }
    }

    var needsPermissionAction: Bool {
        session.statusMessage.localizedCaseInsensitiveContains("permission")
            || session.statusMessage.localizedCaseInsensitiveContains("권한")
            || session.statusMessage.localizedCaseInsensitiveContains("権限")
            || session.statusMessage.localizedCaseInsensitiveContains("权限")
    }
}

private struct LockedConsoleSummary: View {
    let title: String
    let value: String
    let systemImage: String
    var spokenValue: String? = nil

    var body: some View {
        Label(value, systemImage: systemImage)
            .font(AirTranslateDesign.Typography.label)
            .foregroundStyle(AirTranslateDesign.Palette.textTertiary)
            .lineLimit(1)
            .padding(.horizontal, AirTranslateDesign.Spacing.xs)
            .frame(height: 32)
            .background(AirTranslateDesign.Palette.raisedHover, in: Capsule())
            .opacity(0.7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue("\(spokenValue ?? value), \(AppText.lockedDuringSession)")
    }
}
