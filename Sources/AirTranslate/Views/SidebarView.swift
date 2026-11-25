import SwiftUI

// Kept as a compatibility wrapper for call sites outside the main window.
struct SidebarView: View {
    @Bindable var session: TranslationSessionStore

    var body: some View {
        ConsoleBarView(session: session)
    }
}

enum SidebarSessionConfigurationAccess {
    static func isLocked(isRunning: Bool, isStarting: Bool, isMediaActive: Bool = false) -> Bool {
        isRunning || isStarting || isMediaActive
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
    case cloudflare
    case openAI
    case gemini
    case meta
    case azure
    case nari
    case grok
    case qwen

    // Paused integrations remain decodable, but cannot be selected.
    static let selectableCases: [Self] = [.apple, .indexOnline, .cloudflare, .openAI, .gemini, .meta, .grok, .qwen]
    var isAvailable: Bool { Self.selectableCases.contains(self) }
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
        case .cloudflare: CloudflareCopy.title
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
        if session.localTranslation.usesCloudflare { return .cloudflare }
        return session.localTranslation.usesOnlineIndex ? .indexOnline : .apple
    }
}

struct StageHeaderView: View {
    @Bindable var session: TranslationSessionStore
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        ViewThatFits(in: .horizontal) {
            headerControls.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                HStack { SessionStatusPill(session: session); Spacer(); PermissionActionButton(session: session) }
                languageMenu
                engineControl
                if session.isUsingMetaScribe && session.isMetaSpeakerLabelsEnabled {
                    AirChip(text: AppText.speakerLabelsOn, systemImage: "person.2.fill", tint: AirTranslateDesign.Palette.textSecondary)
                }
            }
        }
        .padding(.horizontal, AirTranslateDesign.Spacing.lg)
        .frame(minHeight: 44)
        .background(AirTranslateDesign.Palette.canvas)
    }

    private var headerControls: some View {
        HStack(spacing: AirTranslateDesign.Spacing.sm) {
            SessionStatusPill(session: session)

            languageMenu

            Spacer(minLength: AirTranslateDesign.Spacing.sm)

            engineControl

            if session.isUsingMetaScribe && session.isMetaSpeakerLabelsEnabled {
                AirChip(
                    text: AppText.speakerLabelsOn,
                    systemImage: "person.2.fill",
                    tint: AirTranslateDesign.Palette.textSecondary
                )
            }

            PermissionActionButton(session: session)
        }
    }

    private var engineControl: some View {
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
        case .cloudflare: !session.hasCloudflareAPIKey || !session.hasCloudflareConfiguration
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
        case .cloudflare: CloudflareCopy.configure
        case .indexOnline: AppText.configureTranslationSettings
        }
    }
}

enum MainInputSelection: String, CaseIterable, Identifiable {
    case systemAudio, microphone, media
    var id: String { rawValue }
    var title: String {
        switch self {
        case .systemAudio: AudioInputSource.systemAudio.title
        case .microphone: AudioInputSource.microphone.title
        case .media: AppText.ui("媒体", "Media", "メディア")
        }
    }
}

struct ConsoleBarView: View {
    @Bindable var session: TranslationSessionStore
    @Binding var isMediaInputSelected: Bool
    var media: VideoSubtitlePreloadStore? = nil
    @Environment(\.openSettings) private var openSettings
    @State private var showsInputLockedAlert = false
    @FocusState private var isCaptureFocused: Bool

    init(session: TranslationSessionStore, isMediaInputSelected: Binding<Bool> = .constant(false), media: VideoSubtitlePreloadStore? = nil) {
        self.session = session
        self._isMediaInputSelected = isMediaInputSelected
        self.media = media
    }

    var body: some View {
        consoleSurface
        .alert(AppText.ui("请先结束当前录制", "Please end the current recording first", "現在の収録を終了してください"), isPresented: $showsInputLockedAlert) {
            Button(AppText.ui("好", "OK", "OK"), role: .cancel) {}
        }
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

    @ViewBuilder
    private var consoleSurface: some View {
        if #available(macOS 26.0, *) {
            consoleControls.glassEffect(.regular, in: Capsule())
        } else {
            consoleControls.background(.regularMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    private var outputControl: some View {
        if isMediaInputSelected, let media {
            Picker(AppText.outputMode, selection: Binding(
                get: { media.showsTranslation }, set: { media.showsTranslation = $0 }
            )) {
                Text(ConsoleLayoutMetrics.originalOnly).tag(false)
                Text(ConsoleLayoutMetrics.bilingual).tag(true)
            }
            .pickerStyle(.segmented).controlSize(.large).labelsHidden().frame(width: ConsoleLayoutMetrics.current.outputWidth)
        } else {
            ProcessingModePicker(session: session)
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

            if !isMediaInputSelected && session.audioInputSource == .microphone {
                microphoneControl
            }

            Spacer(minLength: 0)
            outputControl
        }
        .padding(.horizontal, AirTranslateDesign.Spacing.sm)
        .padding(.vertical, AirTranslateDesign.Spacing.xs)
        .frame(minWidth: 740, maxWidth: 1120)
    }

    private var captureButton: some View {
        Button {
            if isMediaInputSelected {
                media?.performMainAction()
            } else if session.isRunning || session.isStarting {
                session.stop()
            } else {
                session.start()
            }
        } label: {
            HStack(spacing: AirTranslateDesign.Spacing.xs) {
                if isMediaInputSelected ? media?.isPreparing == true : session.captureControlState.phase.showsProgress {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isMediaInputSelected ? (media?.isConfigurationLocked == true ? "stop.fill" : "play.fill") : session.captureControlState.phase.actionSystemImage)
                }

                Text(captureTitle)
                    .lineLimit(1)

                if !isMediaInputSelected && session.captureControlState.phase == .running {
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
        .disabled(isMediaInputSelected ? media?.canPerformMainAction != true : !session.captureControlState.canToggleCapture)
        .airFocusRing(cornerRadius: 22, focus: $isCaptureFocused)
        .defaultFocus($isCaptureFocused, true)
        .help(captureTitle)
        .accessibilityLabel(captureTitle)
        .accessibilityValue(captureStateDescription)
    }

    private var pauseButton: some View {
        let paused = isMediaInputSelected ? (media?.isPaused ?? true) : session.isPaused
        let title = isMediaInputSelected
            ? (paused ? AppText.ui("播放视频", "Play video", "動画を再生") : AppText.ui("暂停视频", "Pause video", "動画を一時停止"))
            : (paused ? AppText.resume : AppText.pause)
        return Button {
            if isMediaInputSelected {
                Task { await media?.togglePlayback() }
            } else { session.isPaused ? session.resume() : session.pause() }
        } label: {
            Image(systemName: paused ? "play.fill" : "pause.fill")
        }
        .buttonStyle(AirIconButton())
        .airFocusRing(cornerRadius: 18)
        .disabled(isMediaInputSelected ? media?.canTogglePlayback != true : !session.captureControlState.canTogglePause)
        .help(title)
        .accessibilityLabel(title)
    }

    private var audioSourceControl: some View {
        Picker(AppText.audioInputSource, selection: mainInputSelection) {
            ForEach(MainInputSelection.allCases) { source in
                Text(source.title).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .labelsHidden()
        .frame(width: ConsoleLayoutMetrics.current.inputWidth)
        .disabled(!isConfigurationAvailable)
        .accessibilityLabel(AppText.audioInputSource)
        .overlay {
            if !isConfigurationAvailable {
                // Keep the system tabs visible; intercept attempts without changing selection.
                Button { showsInputLockedAlert = true } label: {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppText.ui("请先结束当前录制", "Please end the current recording first", "現在の収録を終了してください"))
                .accessibilityIdentifier("lockedMainInputSelection")
            }
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
            isStarting: session.isStarting,
            isMediaActive: media?.isConfigurationLocked == true
        )
    }

    private var segmentedControlPresentation: SidebarSegmentedControlPresentation {
        SidebarSessionConfigurationAccess.segmentedControlPresentation(
            isRunning: session.isRunning || media?.isConfigurationLocked == true,
            isStarting: session.isStarting
        )
    }

    private var captureTitle: String {
        if isMediaInputSelected {
            return media?.isConfigurationLocked == true
                ? AppText.ui("停止", "Stop", "停止") : AppText.ui("开始", "Start", "開始")
        }
        return session.captureControlState.phase.actionTitle
    }

    private var captureStateDescription: String {
        if isMediaInputSelected { return media?.connectionStatus ?? captureTitle }
        return session.captureControlState.statusTitle(statusMessage: session.statusMessage)
    }

    private var captureButtonKind: AirPillButtonKind {
        if isMediaInputSelected { return media?.isConfigurationLocked == true ? .stop : .start }
        if session.captureControlState.phase == .paused { return .paused }
        if session.isRunning || session.isStarting { return .stop }
        return .start
    }

    private var mainInputSelection: Binding<MainInputSelection> {
        Binding {
            isMediaInputSelected ? .media : session.audioInputSource == .microphone ? .microphone : .systemAudio
        } set: { selection in
            guard isConfigurationAvailable else {
                showsInputLockedAlert = true
                return
            }
            isMediaInputSelected = selection == .media
            if selection != .media {
                session.audioInputSource = selection == .microphone ? .microphone : .systemAudio
            }
        }
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
