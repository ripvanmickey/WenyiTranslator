import AppKit
import AVFoundation
import CoreGraphics
import Speech
import SwiftUI

struct SettingsView: View {
    @Bindable var session: TranslationSessionStore
    @Bindable private var localization = InterfaceLocalization.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("AirTranslate.SettingsView.selectedCategory") private var selectedCategoryID = SettingsCategory.general.rawValue
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var credentialScrollTarget: String?
    @State private var credentialScrollRequest = UUID()
    @State private var screenRecordingPermission: SettingsPermissionState = .unknown
    @State private var microphonePermission: SettingsPermissionState = .unknown
    @State private var speechRecognitionPermission: SettingsPermissionState = .unknown

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SettingsSidebar(selection: selectedCategory)
                .toolbar(removing: .sidebarToggle)
                .safeAreaInset(edge: .top, spacing: 0) {
                    HStack {
                        Text(AppText.settings)
                            .font(.title2.weight(.semibold))
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: AirTranslateDesign.Spacing.xs)
                        sidebarToggle
                    }
                    .padding(.horizontal, AirTranslateDesign.Spacing.md)
                    .frame(minHeight: 44)
                }
                .navigationSplitViewColumnWidth(
                    min: AirTranslateDesign.settingsSidebarMinimum,
                    ideal: AirTranslateDesign.settingsSidebarIdeal,
                    max: AirTranslateDesign.settingsSidebarMaximum
                )
        } detail: {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.md) {
                        Text(selectedCategory.wrappedValue.detail)
                            .font(.callout)
                            .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        selectedContent
                    }
                    .frame(maxWidth: AirTranslateDesign.settingsDetailMaximum, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, AirTranslateDesign.Spacing.lg)
                    .padding(.top, AirTranslateDesign.Spacing.md)
                    .padding(.bottom, AirTranslateDesign.Spacing.xl)
                }
                .id(selectedCategoryID)
                .scrollIndicators(.automatic)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AirTranslateDesign.Palette.canvas)
                .task(id: credentialScrollRequest) {
                    guard let credentialScrollTarget else { return }
                    await Task.yield()
                    proxy.scrollTo(credentialScrollTarget, anchor: .top)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack(spacing: AirTranslateDesign.Spacing.sm) {
                    if columnVisibility == .detailOnly {
                        sidebarToggle
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }
                    Text(selectedCategory.wrappedValue.title)
                        .font(.largeTitle.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                }
                .frame(maxWidth: AirTranslateDesign.settingsDetailMaximum, alignment: .leading)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, AirTranslateDesign.Spacing.lg)
                .background(AirTranslateDesign.Palette.canvas)
                .overlay(alignment: .bottom) { Divider() }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .background(SettingsWindowTitle(title: AppText.settings))
        .tint(AirTranslateDesign.Palette.accent)
        .background(AirTranslateDesign.Palette.canvas)
        .frame(
            minWidth: AirTranslateDesign.settingsWindowMinimumWidth,
            maxWidth: .infinity,
            minHeight: AirTranslateDesign.settingsWindowMinimumHeight,
            maxHeight: .infinity
        )
        .onAppear(perform: applyRequestedSettingsCategory)
        .onChange(of: session.requestedSettingsCategoryID) { _, _ in
            applyRequestedSettingsCategory()
        }
        .task(id: selectedCategoryID) {
            if selectedCategory.wrappedValue == .permissions {
                refreshPermissionStatuses()
            }
        }
    }

    @ViewBuilder
    private var sidebarToggle: some View {
        let isVisible = columnVisibility != .detailOnly
        let title = isVisible
            ? AppText.localized(english: "Hide Sidebar", korean: "사이드바 가리기", japanese: "サイドバーを非表示", chineseSimplified: "隐藏侧栏")
            : AppText.localized(english: "Show Sidebar", korean: "사이드바 보기", japanese: "サイドバーを表示", chineseSimplified: "显示侧栏")

        let button = Button {
            withAnimation(reduceMotion ? nil : AirTranslateDesign.Motion.enter) {
                columnVisibility = isVisible ? .detailOnly : .all
            }
        } label: {
            Image(systemName: "sidebar.left")
                .font(.system(size: 16, weight: .medium))
        }
        .buttonBorderShape(.circle)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("settingsSidebarToggle")

        if #available(macOS 26.0, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var selectedCategory: Binding<SettingsCategory> {
        Binding {
            SettingsCategory(rawValue: selectedCategoryID) ?? .general
        } set: { category in
            selectedCategoryID = category.rawValue
        }
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedCategory.wrappedValue {
        case .general:
            generalSettings
            if PlatformSupport.supportsAppleSpeech && session.isUsingAppleTextTranslation {
                AppleTranslationSettingsView(session: session)
            }
            interfaceLanguageSettings
        case .apiKeys:
            apiKeySettings
        case .audio:
            audioSettings
        case .output:
            outputSettings
        case .transcript:
            transcriptSettings
        case .floatingCaptions:
            floatingCaptionSettings
        case .assets:
            assetSettings
        case .permissions:
            permissionSettings
        case .info:
            infoSettings
        }
    }

    private var interfaceLanguageSettings: some View {
        SettingsGroup(title: AppText.ui("界面", "Interface", "表示")) {
            SettingsControlRow(
                title: AppText.ui("界面语言", "App Language", "アプリの言語"),
                detail: AppText.ui("选择后立即更新界面。", "Changes apply immediately.", "選択すると表示言語がすぐに切り替わります。"),
                systemImage: "globe",
                showsSeparator: false
            ) {
                Picker(AppText.ui("界面语言", "App Language", "アプリの言語"), selection: $localization.preference) {
                    ForEach(AppInterfaceLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(minWidth: 140, idealWidth: 160)
            }
        }
    }

    private var generalSettings: some View {
        let mode = selectedProcessingMode
        return SettingsGroup(title: SettingsCopy.modeSettings) {
            if isSessionConfigurationLocked {
                SettingsNoticeRow(text: SettingsCopy.captureRunningDisabledReason, systemImage: "info.circle")
            }

            SettingsControlRow(
                title: SettingsCopy.processingEngine,
                detail: mode.recognitionDetail,
                systemImage: "switch.2",
                showsSeparator: false,
                controlBelowLabel: true
            ) {
                Picker(SettingsCopy.processingEngine, selection: processingModeSelection) {
                    ForEach(ProcessingEngine.allCases) { mode in
                        Text(mode.settingsMenuTitle).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .allowsHitTesting(segmentedControlAllowsHitTesting())
                .accessibilityRespondsToUserInteraction(segmentedControlAllowsHitTesting())
                .opacity(isSessionConfigurationLocked ? 0.6 : 1)
                .help(mode.recognitionDetail)
                .accessibilityLabel(SettingsCopy.processingEngine)
                .accessibilityValue(mode.settingsMenuTitle)
                .accessibilityHint(
                    isSessionConfigurationLocked
                        ? SettingsCopy.captureRunningDisabledReason
                        : mode.recognitionDetail
                )
            }

            if mode.usesOnDeviceRecognition {
                LocalTranslationSettingsView(session: session, isOnlineIndex: mode == .indexOnline)
                    .id(mode)
            }

            if mode != .indexOnline && (mode != .apple || !session.localTranslation.enabled) {
            SettingsToggleRow(
                title: JevCopy.title,
                detail: session.isJevSelectionAvailable ? JevCopy.detail : JevCopy.appleOnly,
                systemImage: "text.badge.checkmark",
                detailLineLimit: nil,
                isOn: lockedSessionConfigurationBinding($session.isJevSelectionEnabled)
            )
            .disabled(isSessionConfigurationLocked || !session.isJevSelectionAvailable || session.isUsingLocalTranslation)
            .accessibilityIdentifier("jevSelectionToggle")

            if session.isUsingJevSelection {
                SettingsNoticeRow(
                    text: session.hasJevAPIKey ? session.jevSelectionStatus : JevCopy.keyRequired,
                    systemImage: session.hasJevAPIKey ? "info.circle" : "key"
                )
            }

            if session.isUsingJevSelection && !session.hasJevAPIKey {
                Button(JevCopy.keySettings) { session.requestAPIKeySettings(provider: .jev) }
                    .disabled(isSessionConfigurationLocked)
                    .accessibilityIdentifier("jevAPIKeySettings")
                    .padding(.leading, settingsLabelIndent)
            }

            }

            if processingModeSelection.wrappedValue == .gemini {
                SettingsControlRow(
                    title: SettingsCopy.geminiLiveMode,
                    detail: SettingsCopy.geminiLiveModeDetail,
                    systemImage: "waveform.badge.mic",
                    controlBelowLabel: true
                ) {
                    Picker(SettingsCopy.geminiLiveMode, selection: geminiModelSelection) {
                        ForEach(GeminiTranslationModel.selectableCases) { model in
                            Text(model.isTranscription ? SettingsCopy.transcribe : SettingsCopy.translate)
                                .tag(model)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(AirTranslateDesign.Palette.accent)
                    .labelsHidden()
                    .frame(width: 170)
                    .allowsHitTesting(segmentedControlAllowsHitTesting())
                    .accessibilityRespondsToUserInteraction(segmentedControlAllowsHitTesting())
                    .opacity(isSessionConfigurationLocked ? 0.6 : 1)
                    .accessibilityLabel(SettingsCopy.geminiLiveMode)
                    .accessibilityValue(geminiModelSelection.wrappedValue.title)
                    .accessibilityHint(
                        isSessionConfigurationLocked
                            ? SettingsCopy.captureRunningDisabledReason
                            : SettingsCopy.geminiLiveModeDetail
                    )
                }
            }

            if processingModeSelection.wrappedValue == .openAI, !session.hasOpenAIAPIKey {
                SettingsNoticeActionRow(
                    text: AppText.openAIAPIKeyRequiredForGPTMode,
                    systemImage: "key",
                    actionTitle: SettingsCopy.configureAPIKey
                ) {
                    selectedCategory.wrappedValue = .apiKeys
                }
            }

            if processingModeSelection.wrappedValue == .openAI {
                openAIOutputControl
            }

            if processingModeSelection.wrappedValue == .gemini, !session.hasGeminiAPIKey {
                SettingsNoticeActionRow(
                    text: AppText.geminiAPIKeyMissing,
                    systemImage: "key",
                    actionTitle: SettingsCopy.configureAPIKey
                ) {
                    selectedCategory.wrappedValue = .apiKeys
                }
            }

            if processingModeSelection.wrappedValue == .azure {
                SettingsControlRow(
                    title: AzureMAICopy.modelLabel,
                    detail: "",
                    systemImage: "waveform",
                    controlBelowLabel: true
                ) {
                    Picker(AzureMAICopy.modelLabel, selection: lockedSessionConfigurationBinding($session.azureTranscriptionModel)) {
                        ForEach(AzureTranscriptionModel.allCases) { model in
                            Text(model.title).tag(model)
                        }
                    }
                    .labelsHidden()
                    .disabled(isSessionConfigurationLocked)
                    .accessibilityIdentifier("settingsAzureModelPicker")
                }
                SettingsNoticeRow(text: AzureMAICopy.detail(for: session.azureTranscriptionModel), systemImage: "waveform")
                if let azureConfigurationIssue {
                    SettingsNoticeActionRow(
                        text: azureConfigurationIssue,
                        systemImage: "key",
                        actionTitle: SettingsCopy.configureAPIKey
                    ) {
                        selectedCategory.wrappedValue = .apiKeys
                    }
                }
            }
            if processingModeSelection.wrappedValue == .nari {
                nariGeneralSettings
            }
            if processingModeSelection.wrappedValue == .qwen {
                qwenGeneralSettings
            }

            if processingModeSelection.wrappedValue == .grok {
                grokGeneralSettings
            }
            if processingModeSelection.wrappedValue == .meta {
                SettingsControlRow(
                    title: AppText.metaScribe,
                    detail: AppText.metaScribeDetail,
                    systemImage: "person.2.wave.2"
                ) {
                    Text(MetaTranscriptionModel.museVoiceTranscribe.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(AirTranslateDesign.Palette.accent)
                }

                SettingsControlRow(
                    title: SettingsCopy.speakerLabels,
                    detail: SettingsCopy.speakerLabelsDetail,
                    systemImage: "person.2",
                    controlBelowLabel: true
                ) {
                    Toggle("", isOn: $session.isMetaSpeakerLabelsEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .disabled(isSessionConfigurationLocked)
                        .tint(AirTranslateDesign.Palette.accent)
                        .accessibilityLabel(SettingsCopy.speakerLabels)
                }
            }

            if processingModeSelection.wrappedValue == .meta, !session.hasMetaAPIKey {
                SettingsNoticeActionRow(
                    text: AppText.metaAPIKeyMissing,
                    systemImage: "key",
                    actionTitle: SettingsCopy.configureAPIKey
                ) {
                    selectedCategory.wrappedValue = .apiKeys
                }
            }

            if !session.isUsingOpenAIRealtime {
                if session.isUsingProviderRealtimeTranslation {
                    SettingsNoticeRow(text: SettingsCopy.realtimeTranslationOutputOnly, systemImage: "waveform")
                } else if session.isUsingProviderTranscriptionMode {
                    SettingsNoticeRow(text: AppText.gptTranscriptionSourceOnly, systemImage: "text.quote")
                }
            }

            SettingsValueRow(
                title: AppText.languages,
                detail: SettingsCopy.languagePairDetail,
                systemImage: "globe",
                value: session.languageSummary,
                showsSeparator: false
            )

            SettingsValueRow(
                title: AppText.autoDetectInput,
                detail: autoDetectionDetail,
                systemImage: "sparkles",
                value: autoDetectionStatus,
                showsSeparator: false
            )
        }
    }

    private var apiKeySettings: some View {
        APIKeySettingsView(session: session) { provider in
            credentialScrollTarget = provider.rawValue
            credentialScrollRequest = UUID()
        }
    }

    private var audioSettings: some View {
        SettingsGroup(title: AppText.audioInputSource) {
            if isSessionConfigurationLocked {
                SettingsNoticeRow(text: SettingsCopy.captureRunningDisabledReason, systemImage: "info.circle")
            }

            SettingsControlRow(
                title: AppText.audioInputSource,
                detail: SettingsCopy.audioInputDetail,
                systemImage: "waveform.badge.magnifyingglass",
                controlBelowLabel: true
            ) {
                Picker(AppText.audioInputSource, selection: lockedSessionConfigurationBinding($session.audioInputSource)) {
                    ForEach(AudioInputSource.allCases) { source in
                        Text(source.title).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .tint(AirTranslateDesign.Palette.accent)
                .labelsHidden()
                .frame(width: 190)
                .allowsHitTesting(segmentedControlAllowsHitTesting())
                .accessibilityRespondsToUserInteraction(segmentedControlAllowsHitTesting())
                .opacity(isSessionConfigurationLocked ? 0.6 : 1)
                .accessibilityLabel(AppText.audioInputSource)
                .accessibilityHint(
                    isSessionConfigurationLocked
                        ? SettingsCopy.captureRunningDisabledReason
                        : SettingsCopy.audioInputDetail
                )
            }

            SettingsControlRow(
                title: AppText.ui("纯音频采集（实验）", "Audio-Only Capture (Experimental)", "音声のみの収録（実験的）"),
                detail: PlatformSupport.supportsAudioTap ? AppText.ui("开启后仅采集 Mac 系统声音，不启动屏幕捕获。首次使用需允许系统音频录制；不保证受保护的视频可用。失败时不会自动切回屏幕捕获。停止采集后可更改。", "Capture only Mac system audio. Allow system audio recording on first use. Protected video may be unavailable, and failures do not fall back to screen capture. Stop capture to change this setting.", "Mac のシステム音声のみを収録します。初回はシステム音声の収録を許可してください。保護された動画は利用できない場合があり、失敗時に画面収録へは切り替わりません。変更するには収録を停止してください。") : AppText.ui("纯音频采集需要 macOS 14.2或以上。当前可用麦克风或屏幕捕获兼容方式；兼容方式可能影响受保护视频的播放。", "Audio-only capture requires macOS 14.2 or later. Microphone and screen capture remain available. Screen capture may affect protected playback.", "音声のみの収録には macOS 14.2 以降が必要です。マイクまたは画面収録を利用できます。画面収録は保護された動画の再生に影響する場合があります。"),
                systemImage: "waveform",
                controlBelowLabel: true
            ) {
                Toggle(AppText.ui("纯音频采集", "Audio-Only Capture", "音声のみの収録"), isOn: lockedSessionConfigurationBinding($session.audioOnlySystemCapture))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(AirTranslateDesign.Palette.accent)
                    .disabled(isSessionConfigurationLocked || session.audioInputSource != .systemAudio || !PlatformSupport.supportsAudioTap)
                    .accessibilityLabel(AppText.ui("纯音频采集（实验）", "Audio-Only Capture (Experimental)", "音声のみの収録（実験的）"))
            }

            SettingsControlRow(
                title: AppText.microphoneInputDevice,
                detail: session.audioInputSource == .microphone
                    ? SettingsCopy.microphoneDeviceDetail
                    : SettingsCopy.microphoneDeviceUnavailableForSystemAudioDetail,
                systemImage: "mic",
                controlBelowLabel: true
            ) {
                Picker(AppText.microphoneInputDevice, selection: lockedSessionConfigurationBinding($session.selectedMicrophoneInputDeviceID)) {
                    ForEach(session.microphoneInputDevices) { device in
                        Text(device.name).tag(device.id)
                    }
                }
                .labelsHidden()
                .frame(width: 220)
                .disabled(isSessionConfigurationLocked || session.audioInputSource != .microphone)
            }
        }
    }

    private var outputSettings: some View {
        SettingsGroup(title: AppText.output) {
            if isSessionConfigurationLocked {
                SettingsNoticeRow(text: SettingsCopy.captureRunningDisabledReason, systemImage: "info.circle")
            }

            if session.isUsingOpenAIRealtime {
                openAIOutputControl
            } else if session.isUsingProviderTranscriptionMode {
                SettingsValueRow(
                    title: AppText.outputMode,
                    detail: transcribeOnlyOutputDetail,
                    systemImage: "rectangle.split.2x1",
                    value: SettingsCopy.originalOnly
                )
            } else {
                SettingsControlRow(
                    title: AppText.outputMode,
                    detail: SettingsCopy.outputModeDetail,
                    systemImage: "rectangle.split.2x1",
                    controlBelowLabel: true
                ) {
                    Picker(AppText.outputMode, selection: liveOutputModeBinding) {
                        ForEach(LiveOutputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .tint(AirTranslateDesign.Palette.accent)
                    .labelsHidden()
                    .frame(width: 170)
                    .allowsHitTesting(
                        segmentedControlAllowsHitTesting(
                            isOtherwiseAvailable: !session.isUsingProviderRealtimeTranslation
                        )
                    )
                    .accessibilityRespondsToUserInteraction(
                        segmentedControlAllowsHitTesting(
                            isOtherwiseAvailable: !session.isUsingProviderRealtimeTranslation
                        )
                    )
                    .opacity(
                        segmentedControlAllowsHitTesting(
                            isOtherwiseAvailable: !session.isUsingProviderRealtimeTranslation
                        ) ? 1 : 0.6
                    )
                    .accessibilityLabel(AppText.outputMode)
                    .accessibilityHint(
                        isSessionConfigurationLocked
                            ? SettingsCopy.captureRunningDisabledReason
                            : session.isUsingProviderRealtimeTranslation
                                ? SettingsCopy.realtimeTranslationOutputOnly
                                : SettingsCopy.outputModeDetail
                    )
                }
            }

            if session.isUsingProviderRealtimeTranslation && !session.isUsingOpenAIRealtime {
                SettingsNoticeRow(text: SettingsCopy.realtimeTranslationOutputOnly, systemImage: "waveform")
            }

        }
    }

    private var openAIOutputControl: some View {
        SettingsControlRow(
            title: AppText.openAIAudio,
            detail: "",
            systemImage: "waveform",
            showsSeparator: false,
            controlBelowLabel: true
        ) {
            HStack(spacing: 12) {
                OpenAIOutputPicker(session: session)
                InlineHelpIcon(symbol: "info.circle", help: AppText.openAIAudioDescription)
            }
        }
    }

    private var transcribeOnlyOutputDetail: String {
        if session.isUsingGeminiTranscriptionMode {
            return SettingsCopy.geminiTranscribeSourceOnlyDetail
        }
        if session.isUsingGPTTranscriptionMode {
            return AppText.gptTranscriptionModeDescription
        }
        return SettingsCopy.appleTranscribeSourceOnlyDetail
    }

    private var transcriptSettings: some View {
        SettingsGroup(title: AppText.transcript) {
            if isSessionConfigurationLocked {
                SettingsNoticeRow(text: SettingsCopy.captureRunningDisabledReason, systemImage: "info.circle")
            }

            if session.isUsingOpenAIRealtime {
                SettingsNoticeRow(text: SettingsCopy.openAIRealtimeDisabledReason, systemImage: "info.circle")
            }

            SettingsControlRow(
                title: AppText.sessionLength,
                detail: session.sessionDurationMode.detail,
                systemImage: "timer",
                controlBelowLabel: true
            ) {
                Picker(AppText.sessionLength, selection: lockedSessionConfigurationBinding($session.sessionDurationMode)) {
                    ForEach(SessionDurationMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .tint(AirTranslateDesign.Palette.accent)
                .labelsHidden()
                .frame(width: 190)
                .allowsHitTesting(segmentedControlAllowsHitTesting())
                .accessibilityRespondsToUserInteraction(segmentedControlAllowsHitTesting())
                .opacity(isSessionConfigurationLocked ? 0.6 : 1)
                .accessibilityLabel(AppText.sessionLength)
                .accessibilityHint(
                    isSessionConfigurationLocked
                        ? SettingsCopy.captureRunningDisabledReason
                        : session.sessionDurationMode.detail
                )
            }

            SettingsControlRow(
                title: AppText.paragraphBreakSilenceInterval,
                detail: AppText.paragraphBreakSilenceDescription,
                systemImage: "text.append"
            ) {
                Stepper(
                    AppText.seconds(session.paragraphBreakSilenceInterval),
                    value: lockedSessionConfigurationBinding($session.paragraphBreakSilenceInterval),
                    in: 1...15,
                    step: 0.5
                )
                .frame(width: 104)
                .disabled(isSessionConfigurationLocked)
            }

            SettingsToggleRow(
                title: AppText.transcriptPersistence,
                detail: AppText.transcriptPersistenceDescription,
                systemImage: "externaldrive",
                isOn: lockedSessionConfigurationBinding($session.isTranscriptPersistenceEnabled)
            )
            .disabled(isSessionConfigurationLocked)

            SettingsToggleRow(
                title: AppText.transcriptLint,
                detail: AppText.transcriptLintDescription,
                systemImage: "wand.and.sparkles",
                isOn: lockedSessionConfigurationBinding($session.isTranscriptLintEnabled)
            )
            .disabled(isSessionConfigurationLocked || session.isUsingOpenAIRealtime)

            SettingsControlRow(
                title: AppText.savedTranscriptContent,
                detail: AppText.autoSaveDescription,
                systemImage: "archivebox",
                controlBelowLabel: true
            ) {
                if session.isTranscribeOnlyMode {
                    Text(session.effectiveSavedTranscriptContentMode.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                } else {
                    Picker(AppText.savedTranscriptContent, selection: lockedSessionConfigurationBinding($session.savedTranscriptContentMode)) {
                        ForEach(session.availableSavedTranscriptContentModes) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 150, idealWidth: 170, maxWidth: .infinity)
                    .disabled(isSessionConfigurationLocked)
                }
            }
        }
    }

    private var floatingCaptionSettings: some View {
        FloatingCaptionSettingsView(session: session)
    }

    private var assetSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !PlatformSupport.supportsAppleSpeech {
                Text(AppText.ui("Apple 语言资源需要 macOS 26。本地识别模型请在「通用 → 语音识别引擎」下载和管理。", "Apple language assets require macOS 26. Manage local recognition models in General → Speech Recognition Engine.", "Apple の言語リソースには macOS 26 が必要です。ローカル認識モデルは「一般 → 音声認識エンジン」で管理します。"))
                    .foregroundStyle(.secondary)
            }
            SettingsGroup(title: AppText.requiredAssets) {
                SettingsAssetAvailabilityRow(
                    title: AppText.speechLanguagePack,
                    availability: session.modelAvailability(for: .appleSpeechOnly)
                ) {
                    session.downloadModelAssets(for: .appleSpeechOnly)
                }

                SettingsAssetAvailabilityRow(
                    title: AppText.translationLanguagePack,
                    availability: session.modelAvailability(for: .appleOnDevice)
                ) {
                    session.downloadModelAssets(for: .appleOnDevice)
                }
            }
            .disabled(session.isDownloadingModelAssets || !PlatformSupport.supportsAppleSpeech)

            Label(SettingsCopy.assetDownloadNotice, systemImage: "internaldrive")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionSettings: some View {
        SettingsGroup(title: AppText.permissions) {
            SettingsPermissionRow(
                title: SettingsCopy.screenRecording,
                detail: SettingsCopy.screenRecordingPermissionDetail,
                systemImage: "rectangle.dashed.badge.record",
                status: screenRecordingPermission
            ) {
                session.openPrivacySettings(.screenRecording)
            }

            SettingsPermissionRow(
                title: SettingsCopy.systemAudioRecording,
                detail: SettingsCopy.systemAudioPermissionDetail,
                systemImage: "speaker.wave.2",
                status: .unknown
            ) {
                session.openPrivacySettings(.systemAudioRecording)
            }

            SettingsPermissionRow(
                title: SettingsCopy.microphonePermission,
                detail: SettingsCopy.microphonePermissionDetail,
                systemImage: "mic",
                status: microphonePermission
            ) {
                session.openPrivacySettings(.microphone)
            }

            SettingsPermissionRow(
                title: SettingsCopy.speechRecognitionPermission,
                detail: SettingsCopy.speechRecognitionPermissionDetail,
                systemImage: "quote.bubble",
                status: speechRecognitionPermission
            ) {
                session.openPrivacySettings(.speechRecognition)
            }

            HStack {
                Label(SettingsCopy.permissionReadOnlyNotice, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 16)

                Button(action: refreshPermissionStatuses) {
                    Label(SettingsCopy.refreshPermissionStatus, systemImage: "arrow.clockwise")
                }
                .accessibilityHint(SettingsCopy.permissionReadOnlyNotice)
            }
            .padding(.vertical, 8)
        }
    }

    private var infoSettings: some View {
        let currentVersion = RunningAppVersion.current()
        return VStack(alignment: .leading, spacing: 24) {
            SettingsGroup(title: SettingsCopy.versionInformation) {
                versionInfoRow(SettingsCopy.version, value: currentVersion.version, systemImage: "tag", identifier: "appVersionNumber")
                Divider().padding(.leading, settingsLabelIndent)
                versionInfoRow(SettingsCopy.buildNumber, value: currentVersion.build, systemImage: "hammer", identifier: "appBuildNumber")
            }

            SettingsGroup(title: SettingsCopy.aboutAirTranslate) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsRowLabel(
                        title: AppText.appName,
                        detail: AppText.appTagline,
                        systemImage: "waveform.and.magnifyingglass"
                    )

                    Divider().padding(.leading, settingsLabelIndent)

                    SettingsRowLabel(
                        title: SettingsCopy.privacy,
                        detail: SettingsCopy.privacyDetail,
                        systemImage: "lock.shield",
                        detailLineLimit: nil
                    )
                }
                .padding(.vertical, 12)
            }
        }
    }

    @ViewBuilder
    private var nariGeneralSettings: some View {
        SettingsControlRow(
            title: NariCopy.modelLabel,
            detail: NariCopy.modelDetail + "\n" + session.nariTranscriptionModel.billingSummary,
            systemImage: "waveform.badge.mic",
            controlBelowLabel: true
        ) {
            Picker(NariCopy.modelLabel, selection: lockedSessionConfigurationBinding($session.nariTranscriptionModel)) {
                ForEach(NariTranscriptionModel.selectableCases) { model in
                    Text(model.title).tag(model)
                }
            }
            .labelsHidden()
            .frame(minWidth: 210, idealWidth: 250, maxWidth: 300)
            .disabled(isSessionConfigurationLocked)
            .accessibilityLabel(NariCopy.modelLabel)
            .accessibilityValue(session.nariTranscriptionModel.title)
        }

        SettingsControlRow(
            title: AppText.autoDetectInput,
            detail: NariCopy.autoDetectDetail,
            systemImage: "globe",
            controlBelowLabel: true
        ) {
            Toggle("", isOn: lockedSessionConfigurationBinding($session.isNariSourceAutoDetectionEnabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(isSessionConfigurationLocked)
                .accessibilityLabel(AppText.autoDetectInput)
        }

        SettingsNoticeRow(text: NariCopy.detail, systemImage: "waveform")
        if !session.hasNariAPIKey {
            SettingsNoticeActionRow(
                text: NariCopy.configurationRequired,
                systemImage: "key",
                actionTitle: SettingsCopy.configureAPIKey
            ) {
                selectedCategory.wrappedValue = .apiKeys
            }
        }
    }

    @ViewBuilder
    private var grokGeneralSettings: some View {
        SettingsControlRow(
            title: GrokCopy.modelLabel,
            detail: GrokCopy.detail,
            systemImage: "waveform.badge.mic",
            controlBelowLabel: true
        ) {
            Picker(GrokCopy.modelLabel, selection: lockedSessionConfigurationBinding($session.grokTranscriptionModel)) {
                ForEach(GrokTranscriptionModel.selectableCases) { model in
                    Text(model.title).tag(model)
                }
            }
            .labelsHidden()
            .frame(minWidth: 210, idealWidth: 250, maxWidth: 300)
            .disabled(isSessionConfigurationLocked)
            .accessibilityLabel(GrokCopy.modelLabel)
            .accessibilityValue(session.grokTranscriptionModel.title)
        }

        SettingsControlRow(
            title: AppText.autoDetectInput,
            detail: GrokCopy.autoDetectDetail,
            systemImage: "globe",
            controlBelowLabel: true
        ) {
            Toggle("", isOn: lockedSessionConfigurationBinding($session.isGrokSourceAutoDetectionEnabled))
                .labelsHidden()
                .toggleStyle(.switch)
                .disabled(isSessionConfigurationLocked)
                .accessibilityLabel(AppText.autoDetectInput)
        }

        SettingsNoticeRow(text: GrokCopy.detail, systemImage: "waveform")
        if !session.hasGrokAPIKey {
            SettingsNoticeActionRow(
                text: GrokCopy.configurationRequired,
                systemImage: "key",
                actionTitle: SettingsCopy.configureAPIKey
            ) {
                selectedCategory.wrappedValue = .apiKeys
            }
        }
    }

    private var selectedProcessingMode: ProcessingEngine {
        ProcessingEngine.current(for: session)
    }

    private var azureConfigurationIssue: String? {
        let hasValidEndpoint = session.hasAzureConfiguration
        switch (hasValidEndpoint, session.hasAzureSpeechAPIKey) {
        case (false, false):
            return AzureMAICopy.configurationRequired
        case (false, true):
            return session.azureTranscriptionModel.isStreaming ? AzureMAICopy.configurationRequired : AzureMAICopy.endpointRequired
        case (true, false):
            return AzureMAICopy.keyRequired
        case (true, true):
            return nil
        }
    }

    private var autoDetectionDetail: String {
        if session.isUsingQwenTranslation { return QwenCopy.detail(for: session.qwenTranslationModel) }
        if session.isUsingGrokSTT { return GrokCopy.autoDetectDetail }
        if session.isUsingNariSTT { return NariCopy.autoDetectDetail }
        if session.isUsingMetaScribe { return SettingsCopy.metaAutoDetectDetail }
        if session.isUsingGeminiTranscriptionMode { return SettingsCopy.geminiAutoDetectDetail }
        return SettingsCopy.autoDetectDetail
    }

    private var autoDetectionStatus: String {
        if session.isUsingQwenTranslation { return SettingsCopy.enabled }
        if session.isUsingGrokSTT { return session.isGrokSourceAutoDetectionEnabled ? SettingsCopy.enabled : SettingsCopy.disabled }
        if session.isUsingNariSTT {
            return session.isNariSourceAutoDetectionEnabled ? SettingsCopy.enabled : SettingsCopy.disabled
        }
        return session.isUsingGeminiTranscriptionMode || session.isUsingMetaScribe
            ? SettingsCopy.enabled : SettingsCopy.comingSoon
    }

    private var isSessionConfigurationLocked: Bool {
        session.isRunning || session.isStarting
    }

    /// Keeps AppKit's segmented control enabled state stable while capture starts.
    /// The guarded bindings below remain the accessibility and programmatic write barrier.
    private func segmentedControlAllowsHitTesting(isOtherwiseAvailable: Bool = true) -> Bool {
        SettingsSegmentedControlAccess.allowsHitTesting(
            isRunning: session.isRunning,
            isStarting: session.isStarting,
            isOtherwiseAvailable: isOtherwiseAvailable
        )
    }

    private func lockedSessionConfigurationBinding<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { value in
                guard !isSessionConfigurationLocked else { return }
                binding.wrappedValue = value
            }
        )
    }

    private var processingModeSelection: Binding<ProcessingEngine> {
        Binding {
            selectedProcessingMode
        } set: { mode in
            guard !isSessionConfigurationLocked, mode != selectedProcessingMode else { return }
            switch mode {
            case .apple:
                session.useAppleDefaultMode()
            case .indexOnline:
                session.enableOnlineIndexTranslation()
            case .openAI:
                session.useOpenAIMode()
            case .gemini:
                session.usePreferredGeminiMode()
            case .azure:
                session.useAzureMAIMode()
            case .qwen:
                session.useQwenTranslationMode()
            case .grok:
                session.useGrokSTTMode()
            case .nari:
                session.useNariSTTMode()
            case .meta:
                session.useMetaScribeMode()
            }
        }
    }

    private var geminiModelSelection: Binding<GeminiTranslationModel> {
        Binding {
            session.geminiTranslationModel.isEnabled
                ? session.geminiTranslationModel
                : session.preferredGeminiModel
        } set: { model in
            guard !isSessionConfigurationLocked else { return }
            session.useGeminiMode(model)
        }
    }

    @ViewBuilder
    private var qwenGeneralSettings: some View {
        SettingsControlRow(
            title: QwenCopy.modelLabel,
            detail: QwenCopy.modelDetail,
            systemImage: "waveform",
            controlBelowLabel: true
        ) {
            Picker(QwenCopy.modelLabel, selection: lockedSessionConfigurationBinding($session.qwenTranslationModel)) {
                ForEach(QwenTranslationModel.selectableCases) { model in
                    Text(model.title).tag(model)
                }
            }
            .labelsHidden()
            .frame(minWidth: 210, idealWidth: 250, maxWidth: 300)
            .disabled(isSessionConfigurationLocked)
            .accessibilityLabel(QwenCopy.modelLabel)
            .accessibilityValue(session.qwenTranslationModel.title)
            .accessibilityIdentifier("qwenRealtimeModelPicker")
        }

        SettingsNoticeRow(
            text: QwenCopy.detail(for: session.qwenTranslationModel) + "\n" + QwenCopy.price(for: session.qwenTranslationModel),
            systemImage: "waveform"
        )
        if !session.hasQwenConfiguration {
            let model = session.qwenTranslationModel.isEnabled ? session.qwenTranslationModel : session.preferredQwenModel
            SettingsNoticeActionRow(text: QwenCopy.configurationRequired(for: model), systemImage: "key", actionTitle: SettingsCopy.configureAPIKey) {
                session.requestAPIKeySettings(provider: .qwen)
                selectedCategory.wrappedValue = .apiKeys
            }
        }
        QwenAudioFileTranscriptionView(hasAPIKey: session.hasQwenAPIKey)
            .padding(.leading, settingsLabelIndent)
    }

    private var liveOutputModeBinding: Binding<LiveOutputMode> {
        Binding {
            session.liveOutputMode
        } set: { mode in
            guard segmentedControlAllowsHitTesting(
                isOtherwiseAvailable: !session.isUsingProviderRealtimeTranslation
            ) else { return }
            session.useLiveOutputMode(mode)
        }
    }

    private func versionInfoRow(_ title: String, value: String?, systemImage: String, identifier: String) -> some View {
        HStack(spacing: 16) {
            SettingsRowLabel(title: title, detail: "", systemImage: systemImage)
            Spacer(minLength: 0)
            Text(value ?? SettingsCopy.versionUnavailable)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .accessibilityIdentifier(identifier)
        }
        .frame(minHeight: 44)
    }

    private func refreshPermissionStatuses() {
        screenRecordingPermission = CGPreflightScreenCaptureAccess() ? .allowed : .notGranted

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphonePermission = .allowed
        case .denied:
            microphonePermission = .denied
        case .restricted:
            microphonePermission = .restricted
        case .notDetermined:
            microphonePermission = .notDetermined
        @unknown default:
            microphonePermission = .unknown
        }

        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            speechRecognitionPermission = .allowed
        case .denied:
            speechRecognitionPermission = .denied
        case .restricted:
            speechRecognitionPermission = .restricted
        case .notDetermined:
            speechRecognitionPermission = .notDetermined
        @unknown default:
            speechRecognitionPermission = .unknown
        }
    }

    private func applyRequestedSettingsCategory() {
        guard let requestedCategoryID = session.requestedSettingsCategoryID,
              let category = SettingsCategory(rawValue: requestedCategoryID)
        else { return }

        selectedCategory.wrappedValue = category
        session.requestedSettingsCategoryID = nil
    }
}

private struct SettingsWindowTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> TitleView {
        let view = TitleView()
        view.title = title
        return view
    }

    func updateNSView(_ view: TitleView, context: Context) {
        view.title = title
    }

    final class TitleView: NSView {
        var title = "" {
            didSet {
                if title != oldValue { applyTitle() }
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyTitle()
        }

        private func applyTitle() {
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.title = self.title
                window.titleVisibility = .hidden
            }
        }
    }
}

private extension ProcessingEngine {
    var settingsMenuTitle: String {
        let name: String
        switch self {
        case .gemini: name = "Gemini"
        case .azure: name = "Azure MAI"
        case .meta: name = "Meta"
        default: name = title
        }
        let recognition = usesOnDeviceRecognition
            ? AppText.localized(english: "On-device recognition", korean: "기기 내 음성 인식", japanese: "端末内認識", chineseSimplified: "本机识别")
            : AppText.localized(english: "Cloud recognition", korean: "클라우드 음성 인식", japanese: "クラウド認識", chineseSimplified: "云端识别")
        return "\(name) · \(recognition)"
    }

    var recognitionDetail: String {
        if usesOnDeviceRecognition {
            return AppText.localized(
                english: "Speech is recognized on this Mac.",
                korean: "이 Mac에서 음성을 인식합니다.",
                japanese: "音声はこの Mac で認識されます。",
                chineseSimplified: "语音在这台 Mac 上识别。"
            )
        }
        return AppText.localized(
            english: "When listening starts, captured audio is sent to the selected service for recognition.",
            korean: "듣기를 시작하면 캡처한 오디오가 음성 인식을 위해 선택한 서비스로 전송됩니다.",
            japanese: "聞き取りを開始すると、収録した音声を選択中のサービスに送信して認識します。",
            chineseSimplified: "开始聆听后，采集的音频会发送给所选服务进行识别。"
        )
    }
}

private enum SettingsCategory: String, CaseIterable, Hashable, Identifiable {
    case general
    case apiKeys
    case audio
    case output
    case transcript
    case floatingCaptions
    case assets
    case permissions
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general:
            SettingsCopy.general
        case .apiKeys:
            SettingsCopy.apiKeys
        case .audio:
            SettingsCopy.audio
        case .output:
            AppText.output
        case .transcript:
            AppText.transcript
        case .floatingCaptions:
            AppText.floatingCaptions
        case .assets:
            SettingsCopy.assets
        case .permissions:
            AppText.permissions
        case .info:
            SettingsCopy.info
        }
    }

    var detail: String {
        switch self {
        case .general:
            SettingsCopy.generalDetail
        case .apiKeys:
            SettingsCopy.apiKeysDetail
        case .audio:
            SettingsCopy.audioDetail
        case .output:
            SettingsCopy.outputDetail
        case .transcript:
            SettingsCopy.transcriptDetail
        case .floatingCaptions:
            SettingsCopy.floatingDetail
        case .assets:
            SettingsCopy.assetsDetail
        case .permissions:
            SettingsCopy.permissionsDetail
        case .info:
            SettingsCopy.infoDetail
        }
    }

    var systemImage: String {
        switch self {
        case .general:
            "slider.horizontal.3"
        case .apiKeys:
            "key.fill"
        case .audio:
            "mic"
        case .output:
            "waveform"
        case .transcript:
            "doc.text"
        case .floatingCaptions:
            "captions.bubble"
        case .assets:
            "cube.box"
        case .permissions:
            "shield.lefthalf.filled"
        case .info:
            "info.circle"
        }
    }
}

enum SettingsSegmentedControlAccess {
    static func allowsHitTesting(
        isRunning: Bool,
        isStarting: Bool,
        isOtherwiseAvailable: Bool = true
    ) -> Bool {
        !isRunning && !isStarting && isOtherwiseAvailable
    }
}

enum SettingsCopy {
    static var general: String { AppText.localized(english: "General", korean: "일반", japanese: "一般", chineseSimplified: "通用") }
    static var apiKeys: String { AppText.localized(english: "API Keys", korean: "API 키", japanese: "API キー", chineseSimplified: "API 密钥") }
    static var audio: String { AppText.localized(english: "Audio", korean: "오디오", japanese: "音声", chineseSimplified: "音频") }
    static var assets: String { AppText.localized(english: "Assets", korean: "자산", japanese: "リソース", chineseSimplified: "资源") }
    static var info: String { AppText.localized(english: "Info", korean: "정보", japanese: "情報", chineseSimplified: "关于") }
    static var generalDetail: String {
        AppText.localized(
            english: "Set the default translation mode and language behavior.",
            korean: "기본 번역 방식과 언어 동작을 설정합니다.",
            japanese: "既定の翻訳モードや言語を設定します。", chineseSimplified: "设置默认处理模式和语言行为。"
        )
    }
    static var apiKeysDetail: String { CredentialsCopy.pageDetail }
    static var audioDetail: String {
        AppText.localized(
            english: "Choose where 文译 listens from.",
            korean: "文译가 어떤 오디오를 들을지 선택합니다.",
            japanese: "文译で使用する音声入力を選びます。", chineseSimplified: "选择文译的音频来源。"
        )
    }
    static var outputDetail: String {
        AppText.localized(
            english: "Control what appears and whether translated speech plays.",
            korean: "표시할 결과와 번역 음성 출력을 조정합니다.",
            japanese: "字幕に表示する内容を設定します。", chineseSimplified: "设置字幕输出内容。"
        )
    }
    static var transcriptDetail: String {
        AppText.localized(
            english: "Tune paragraphing, long sessions, and optional transcript file saving.",
            korean: "문단 나누기, 긴 세션, 선택적 기록 파일 저장을 조정합니다.",
            japanese: "段落分けや長時間セッション、記録のファイル保存を設定します。", chineseSimplified: "设置段落、长时间监听和记录文件保存。"
        )
    }
    static var floatingDetail: String {
        AppText.localized(
            english: "Configure the detachable floating caption window.",
            korean: "별도 창으로 표시되는 플로팅 자막을 설정합니다.",
            japanese: "フローティング字幕ウィンドウを設定します。", chineseSimplified: "设置独立悬浮字幕窗口。"
        )
    }
    static var assetsDetail: String {
        AppText.localized(
            english: "Check local speech and translation assets.",
            korean: "로컬 음성 인식 및 번역 자산을 확인합니다.",
            japanese: "ローカルの音声認識と翻訳リソースを確認します。", chineseSimplified: "检查本地语音识别和翻译资源。"
        )
    }
    static var permissionsDetail: String {
        AppText.localized(
            english: "Open macOS privacy controls required for capture.",
            korean: "캡처에 필요한 macOS 개인정보 보호 권한을 엽니다.",
            japanese: "収録に必要な macOS のプライバシー設定を開きます。", chineseSimplified: "打开音频采集所需的 macOS 隐私设置。"
        )
    }
    static var infoDetail: String {
        AppText.localized(
            english: "Review local-first behavior and privacy notes.",
            korean: "로컬 우선 동작과 개인정보 안내를 확인합니다.",
            japanese: "ローカル処理とプライバシーの説明を確認できます。", chineseSimplified: "查看本地处理方式和隐私说明。"
        )
    }
    static var modeSettings: String { AppText.localized(english: "Mode Settings", korean: "모드 설정", japanese: "モード設定", chineseSimplified: "模式设置") }
    static var processingEngine: String { AppText.localized(english: "Processing Mode", korean: "처리 방식", japanese: "処理モード", chineseSimplified: "处理模式") }
    static var configureAPIKey: String {
        AppText.localized(english: "Configure", korean: "설정", japanese: "設定", chineseSimplified: "配置")
    }
    static var sessionWorkflow: String { AppText.localized(english: "Session Workflow", korean: "세션 처리 방식", japanese: "セッションの処理方法", chineseSimplified: "字幕处理方式") }
    static var sessionWorkflowDetail: String {
        AppText.localized(
            english: "Choose translated captions or source-only transcription.",
            korean: "번역 자막 또는 원문 전사만 중에서 선택합니다.",
            japanese: "翻訳付き字幕または原文のみを選びます。", chineseSimplified: "选择显示翻译字幕，或仅转写原文。"
        )
    }
    static var realtimeTranslationOutputOnly: String {
        AppText.localized(
            english: "API live translation modes produce translated captions. For source-only captions, choose Apple transcription, OpenAI Audio → Transcribe, or Gemini Transcribe.",
            korean: "API 실시간 번역 모드는 번역 자막을 만듭니다. 원문 자막만 필요하면 Apple 전사, OpenAI 음성 → 전사 또는 Gemini 전사를 선택하세요.",
            japanese: "APIライブ翻訳モードは翻訳字幕を生成します。原文字幕のみの場合はApple文字起こし、OpenAI音声の文字起こし、またはGemini文字起こしを選択してください。",
            chineseSimplified: "API 实时翻译模式会生成翻译字幕。若只需原文字幕，请选择 Apple 转写、OpenAI 语音的转写或 Gemini 转写。"
        )
    }
    static var languagePairDetail: String {
        AppText.localized(
            english: "Select the language pair at the top left of the main window to change it.",
            korean: "메인 창 왼쪽 상단의 언어 조합을 선택해 변경할 수 있습니다.",
            japanese: "メインウインドウの左上にある言語の組み合わせを選んで変更できます。",
            chineseSimplified: "点击主窗口左上角的语言组合即可更改。"
        )
    }
    static var autoDetectDetail: String {
        AppText.localized(
            english: "Temporarily unavailable while automatic detection is improved.",
            korean: "자동 감지 개선 중이라 잠시 비활성화되어 있습니다.",
            japanese: "自動検出を改善中のため、一時的に利用できません。", chineseSimplified: "自动检测功能正在改进，暂时不可用。"
        )
    }
    static var geminiAutoDetectDetail: String {
        AppText.localized(
            english: "Gemini detects supported spoken languages automatically, including language changes within a session.",
            korean: "Gemini가 지원하는 음성 언어와 세션 중 언어 전환을 자동으로 감지합니다.",
            japanese: "Geminiが対応する音声言語とセッション中の言語切り替えを自動検出します。",
            chineseSimplified: "Gemini 会自动检测支持的口语及会话中的语言切换。"
        )
    }
    static var metaAutoDetectDetail: String {
        AppText.localized(
            english: "Muse Voice Transcribe detects 25 languages automatically, including code-switching within a sentence.",
            korean: "Muse Voice Transcribe가 문장 안의 코드 스위칭을 포함해 25개 언어를 자동 감지합니다.",
            japanese: "Muse Voice Transcribeは文中のコードスイッチングを含む25言語を自動検出します。",
            chineseSimplified: "Muse Voice Transcribe 可自动检测 25 种语言，包括句内语码转换。"
        )
    }
    static var speakerLabels: String {
        AppText.localized(
            english: "Speaker labels",
            korean: "화자 라벨",
            japanese: "話者ラベル",
            chineseSimplified: "说话人标签"
        )
    }
    static var speakerLabelsDetail: String {
        AppText.localized(
            english: "Labels turns as Speaker A, B… Turn off for lower-latency single-speaker transcription.",
            korean: "발화 차례를 화자 A, B…로 표시합니다. 단일 화자의 지연을 낮추려면 끄세요.",
            japanese: "発話を話者A、B…と表示します。単一話者で低遅延にする場合はオフにしてください。",
            chineseSimplified: "将轮次标记为说话人 A、B…。单人转写需要更低延迟时可关闭。"
        )
    }
    static var enabled: String {
        AppText.localized(
            english: "On",
            korean: "켜짐",
            japanese: "オン",
            chineseSimplified: "已开启"
        )
    }
    static var disabled: String {
        AppText.localized(
            english: "Off", korean: "꺼짐", japanese: "オフ", chineseSimplified: "已关闭"
        )
    }
    static var comingSoon: String {
        AppText.localized(
            english: "Coming soon",
            korean: "지원 예정",
            japanese: "近日対応",
            chineseSimplified: "即将支持"
        )
    }
    static var captureRunningDisabledReason: String {
        AppText.localized(
            english: "Stop capture before changing this setting.",
            korean: "이 설정을 바꾸려면 먼저 캡처를 중지하세요.",
            japanese: "この設定を変更する前に収録を停止してください。", chineseSimplified: "请先停止监听，再修改此设置。"
        )
    }
    static var openAIRealtimeDisabledReason: String {
        AppText.localized(
            english: "Transcript cleanup is disabled while OpenAI Realtime is active.",
            korean: "OpenAI Realtime이 켜져 있을 때는 기록 다듬기를 사용할 수 없습니다.",
            japanese: "OpenAI Realtime の使用中は文字起こしの整形を利用できません。", chineseSimplified: "使用 OpenAI Realtime 时，不进行记录润色。"
        )
    }
    static var gptRealtimeModel: String {
        AppText.localized(
            english: "GPT Realtime Model",
            korean: "GPT Realtime 모델",
            japanese: "GPT Realtime モデル", chineseSimplified: "GPT Realtime 模型"
        )
    }
    static var gptRealtimeModelDetail: String {
        AppText.localized(
            english: "Choose the translation-endpoint model used by GPT Realtime.",
            korean: "GPT Realtime에서 사용할 번역 엔드포인트 모델을 선택합니다.",
            japanese: "GPT Realtimeで使用する翻訳エンドポイントモデルを選択します。",
            chineseSimplified: "选择 GPT Realtime 使用的翻译端点模型。"
        )
    }
    static var openAIVoiceAgentModelNotice: String {
        AppText.localized(
            english: "gpt-realtime-2.1 and 2.1-mini are voice-agent models for /v1/realtime. 文译 live interpretation uses gpt-realtime-translate on the translation endpoint.",
            korean: "gpt-realtime-2.1과 2.1-mini는 /v1/realtime용 보이스 에이전트 모델입니다. 文译 실시간 통역은 번역 전용 엔드포인트의 gpt-realtime-translate를 사용합니다.",
            japanese: "gpt-realtime-2.1 と 2.1-mini は /v1/realtime 用の音声エージェントモデルです。文译のライブ通訳は翻訳用エンドポイントの gpt-realtime-translate を使います。", chineseSimplified: "模型 gpt-realtime-2.1 和 2.1-mini 用于 /v1/realtime 语音交互；文译实时口译使用翻译接口的 gpt-realtime-translate。"
        )
    }
    static var currentGPTRealtimeModel: String {
        AppText.localized(
            english: "Current GPT Realtime model",
            korean: "현재 GPT Realtime 모델",
            japanese: "現在の GPT Realtime モデル", chineseSimplified: "当前 GPT Realtime 模型"
        )
    }
    static var currentGPTRealtimeModelDetail: String {
        AppText.localized(
            english: "Change this from General after selecting GPT Realtime.",
            korean: "GPT Realtime을 선택한 뒤 일반 설정에서 변경합니다.",
            japanese: "GPT Realtime を選択してから「一般」で変更してください。", chineseSimplified: "在通用设置中选择 GPT Realtime 后，可修改此项。"
        )
    }
    static var openAIVoiceAgentModels: String {
        AppText.localized(
            english: "Voice-agent models",
            korean: "보이스 에이전트 모델",
            japanese: "音声エージェントモデル", chineseSimplified: "语音交互模型"
        )
    }
    static var openAIVoiceAgentModelsDetail: String {
        AppText.localized(
            english: "Documented OpenAI Realtime voice-agent models. They are not used for 文译's live interpreter path yet.",
            korean: "공식 문서에 등록된 OpenAI Realtime 보이스 에이전트 모델입니다. 아직 文译의 실시간 통역 경로에는 사용하지 않습니다.",
            japanese: "OpenAI Realtime が公開している音声エージェントモデルです。文译のライブ通訳ではまだ使用していません。", chineseSimplified: "OpenAI 文档列出的实时语音交互模型，目前尚未用于文译的实时口译。"
        )
    }
    static var geminiTranslationDetail: String {
        AppText.localized(
            english: "Use Gemini 3.5 Live Translate for direct audio-to-live-translation sessions.",
            korean: "Gemini 3.5 Live Translate로 오디오를 직접 실시간 번역합니다.",
            japanese: "Gemini 3.5 Live Translate で音声を直接リアルタイム翻訳します。", chineseSimplified: "使用 Gemini 3.5 Live Translate，直接将音频转换为实时翻译。"
        )
    }
    static var geminiLiveMode: String {
        AppText.localized(
            english: "Gemini Live Mode",
            korean: "Gemini Live 모드",
            japanese: "Gemini Liveモード",
            chineseSimplified: "Gemini Live 模式"
        )
    }
    static var geminiLiveModeDetail: String {
        AppText.localized(
            english: "Translate produces source and target captions. Transcribe detects the spoken language and keeps original captions only.",
            korean: "번역은 원문과 번역 자막을 만들고, 전사는 말하는 언어를 감지해 원문 자막만 유지합니다.",
            japanese: "翻訳は原文と翻訳字幕を生成し、文字起こしは話し言葉を検出して原文字幕のみを保持します。",
            chineseSimplified: "翻译会生成原文和译文字幕，转写会检测口语并仅保留原文字幕。"
        )
    }
    static var translate: String {
        AppText.localized(
            english: "Translate",
            korean: "번역",
            japanese: "翻訳",
            chineseSimplified: "翻译"
        )
    }
    static var transcribe: String {
        AppText.localized(
            english: "Transcribe",
            korean: "전사",
            japanese: "文字起こし",
            chineseSimplified: "转写"
        )
    }
    static var originalOnly: String {
        AppText.localized(
            english: "Original only",
            korean: "원문만",
            japanese: "原文のみ",
            chineseSimplified: "仅原文"
        )
    }
    static var geminiTranscribeSourceOnlyDetail: String {
        AppText.localized(
            english: "Gemini detects the spoken language automatically and shows original captions only.",
            korean: "Gemini가 말하는 언어를 자동 감지하고 원문 자막만 표시합니다.",
            japanese: "Geminiが話し言葉を自動検出し、原文字幕のみを表示します。",
            chineseSimplified: "Gemini 会自动检测口语，并仅显示原文字幕。"
        )
    }
    static var appleTranscribeSourceOnlyDetail: String {
        AppText.localized(
            english: "Apple Speech shows original captions only in Transcribe mode.",
            korean: "Apple Speech 전사 모드에서는 원문 자막만 표시합니다.",
            japanese: "Apple Speechの文字起こしモードでは原文字幕のみを表示します。",
            chineseSimplified: "Apple Speech 转写模式仅显示原文字幕。"
        )
    }
    static var audioInputDetail: String {
        AppText.localized(
            english: "Mac audio captures system playback. Microphone captures the selected input device.",
            korean: "PC 소리는 시스템 재생음을, 마이크는 선택한 입력 장치를 캡처합니다.",
            japanese: "「Mac の音声」はシステムの再生音を、「マイク」は選択した入力デバイスの音声を収録します。", chineseSimplified: "Mac 音频采集系统播放的声音，麦克风采集所选输入设备的声音。"
        )
    }
    static var microphoneDeviceDetail: String {
        AppText.localized(
            english: "Available only when microphone input is selected.",
            korean: "마이크 입력을 선택했을 때 사용할 수 있습니다.",
            japanese: "マイク入力を選択したときに使用できます。",
            chineseSimplified: "仅在选择麦克风输入时可用。"
        )
    }
    static var microphoneDeviceUnavailableForSystemAudioDetail: String {
        AppText.localized(
            english: "Not used for Mac Audio. Switch the audio input to Microphone to choose a device.",
            korean: "PC 소리에서는 마이크 장치를 사용하지 않습니다. 장치를 선택하려면 오디오 입력을 마이크로 바꾸세요.",
            japanese: "Mac音声ではマイクデバイスを使用しません。デバイスを選ぶには入力をマイクに切り替えてください。",
            chineseSimplified: "Mac 音频不使用麦克风设备。要选择设备，请将音频输入切换为麦克风。"
        )
    }
    static var outputModeDetail: String {
        AppText.localized(
            english: "Translation shows source and target text. Transcribe Only keeps the source text.",
            korean: "번역은 원문과 번역을 표시하고, 전사만은 원문 기록만 유지합니다.",
            japanese: "翻訳では原文と訳文を表示し、文字起こしのみでは原文を表示します。", chineseSimplified: "翻译模式显示原文和译文，仅转写模式只显示原文。"
        )
    }
    static var dubbingDetail: String {
        AppText.localized(
            english: "Speak translated output when a stable translated segment is available.",
            korean: "안정된 번역 문장이 생기면 번역 음성을 재생합니다.",
            japanese: "訳文が確定したら読み上げます。", chineseSimplified: "有稳定译文时进行朗读。"
        )
    }
    static var translatedSpeechModel: String {
        AppText.localized(
            english: "Translated Speech Model",
            korean: "번역 음성 모델",
            japanese: "翻訳音声モデル",
            chineseSimplified: "朗读引擎"
        )
    }
    static var translatedSpeechModelDetail: String {
        AppText.localized(
            english: "Choose how 文译 reads translated text in its Apple TranslationSession workflow, including text transcribed by STT providers: Apple system speech, Gemini 3.8 Flash / Flash-Lite TTS, or MAI Voice 2.1 / Flash through OpenRouter. Realtime speech-translation providers use their own audio output.",
            korean: "Apple TranslationSession으로 텍스트를 번역하는 흐름(전사 제공자의 결과를 번역하는 경우 포함)에서 번역문을 읽을 음성을 선택합니다(Apple 시스템 음성, Gemini 3.8 Flash·Flash-Lite TTS 또는 OpenRouter의 MAI Voice 2.1·Flash). 실시간 음성 번역 제공자는 자체 오디오 출력을 사용합니다.",
            japanese: "Apple TranslationSessionでテキストを翻訳するフロー（音声認識プロバイダーの文字起こし結果を翻訳する場合を含む）で読み上げる音声を選択します（Appleシステム音声、Gemini 3.8 Flash / Flash-Lite TTS または OpenRouter の MAI Voice 2.1 / Flash）。リアルタイム音声翻訳プロバイダーは独自の音声出力を使用します。",
            chineseSimplified: "选择朗读译文的语音引擎：Apple 系统语音、Gemini TTS 或 MAI Voice。实时语音翻译服务使用自身的语音输出。"
        )
    }
    static var liveTranslationVolume: String {
        AppText.localized(
            english: "Volume",
            korean: "음량",
            japanese: "音量", chineseSimplified: "音量"
        )
    }
    static var liveTranslationVolumeDetail: String {
        AppText.localized(
            english: "Controls the translated speech 文译 plays in live translation modes.",
            korean: "실시간 번역 모드에서 文译가 재생하는 번역 음성 크기를 조절합니다.",
            japanese: "リアルタイム翻訳で読み上げる音声の音量を調整します。", chineseSimplified: "控制文译在实时翻译模式下朗读译文的音量。"
        )
    }
    static var voiceOutputDisabledReason: String {
        AppText.localized(
            english: "Turn on Voice Output to adjust translated speech volume.",
            korean: "번역 음성의 음량을 조절하려면 음성 출력을 켜세요.",
            japanese: "翻訳音声の音量を調整するには音声出力をオンにしてください。",
            chineseSimplified: "开启语音输出后才能调整译文语音音量。"
        )
    }
    static var displaySettings: String { AppText.localized(english: "Display Settings", korean: "표시 설정", japanese: "表示設定", chineseSimplified: "显示设置") }
    static var displayContent: String { AppText.localized(english: "Display Content", korean: "표시 내용", japanese: "表示する内容", chineseSimplified: "显示内容") }
    static var floatingTextSizeDetail: String {
        AppText.localized(
            english: "Controls the optical size used in the floating caption window.",
            korean: "플로팅 자막 창에 쓰이는 글자 크기를 조정합니다.",
            japanese: "フローティング字幕の文字サイズを調整します。", chineseSimplified: "调整悬浮字幕窗口中的文字大小。"
        )
    }
    static var floatingCustomTextSizeDetail: String {
        AppText.localized(
            english: "Fine-tunes the caption point size without changing the saved preset.",
            korean: "저장된 preset은 유지한 채 자막 포인트 크기만 세밀하게 조정합니다.",
            japanese: "保存済みのプリセットを保ったまま、字幕のポイントサイズだけを細かく調整します。",
            chineseSimplified: "保留已保存的预设，只精细调整字幕字号。"
        )
    }
    static var floatingLineCountDetail: String {
        AppText.localized(
            english: "Limits how many wrapped lines stay visible at once.",
            korean: "한 번에 표시되는 줄 수를 제한합니다.",
            japanese: "一度に表示する行数を制限します。", chineseSimplified: "限制同时可见的自动换行行数。"
        )
    }
    static var floatingTextColorDetail: String {
        AppText.localized(
            english: "Uses one readable foreground color for source and translation text.",
            korean: "원문과 번역에 공통으로 쓰는 읽기 쉬운 글자 색상입니다.",
            japanese: "原文と翻訳に共通で使う読みやすい前景色です。",
            chineseSimplified: "源文和译文共用的易读前景颜色。"
        )
    }
    static var floatingBackgroundColorDetail: String {
        AppText.localized(
            english: "Sets the caption box background color.",
            korean: "자막 박스 배경 색상을 설정합니다.",
            japanese: "字幕ボックスの背景色を設定します。",
            chineseSimplified: "设置字幕框背景颜色。"
        )
    }
    static var floatingBackgroundOpacityDetail: String {
        AppText.localized(
            english: "Adjusts only the caption background opacity. Text and resize handles stay visible.",
            korean: "자막 배경 불투명도만 조정합니다. 글자와 크기 조절 핸들은 계속 보입니다.",
            japanese: "字幕背景の不透明度だけを調整します。文字とリサイズハンドルは表示されたままです。",
            chineseSimplified: "仅调整字幕背景不透明度。文字和大小调整手柄保持可见。"
        )
    }
    static var usePresetTextSize: String {
        AppText.localized(
            english: "Use Preset",
            korean: "프리셋 사용",
            japanese: "プリセットを使用",
            chineseSimplified: "使用预设"
        )
    }
    static var keepOnTop: String { AppText.localized(english: "Always On Top", korean: "항상 위에 표시", japanese: "常に手前に表示", chineseSimplified: "窗口置顶") }
    static var keepOnTopDetail: String {
        AppText.localized(
            english: "Keep floating captions above other windows.",
            korean: "다른 창 위에 플로팅 자막을 고정합니다.",
            japanese: "フローティング字幕をほかのウィンドウより手前に表示します。", chineseSimplified: "将悬浮字幕保持在其他窗口上方。"
        )
    }
    static var floatingFooter: String {
        AppText.localized(
            english: "Floating captions appear in a separate movable window.",
            korean: "플로팅 자막은 별도 창으로 표시되며 원하는 위치로 이동할 수 있습니다.",
            japanese: "フローティング字幕を移動可能な別ウィンドウに表示します。", chineseSimplified: "悬浮字幕显示在可独立移动的窗口中。"
        )
    }
    static var floatingPreviewAccessibilityLabel: String {
        AppText.localized(
            english: "Floating caption preview. Original: We're going to focus on real-time translation. Translation: We will focus on real-time translation.",
            korean: "플로팅 자막 미리보기. 원문: We're going to focus on real-time translation. 번역: 우리는 실시간 번역에 집중할 것입니다.",
            japanese: "フローティング字幕のプレビュー。原文：We will focus on real-time translation. 訳文：リアルタイム翻訳に焦点を当てます。", chineseSimplified: "悬浮字幕预览。原文：我们将重点讨论实时翻译。译文：我们将重点讨论实时翻译。"
        )
    }
    static var screenRecording: String {
        AppText.localized(
            english: "Screen Recording",
            korean: "화면 기록",
            japanese: "画面収録",
            chineseSimplified: "屏幕录制"
        )
    }
    static var systemAudioRecording: String {
        AppText.localized(
            english: "System Audio Recording",
            korean: "시스템 오디오 녹음",
            japanese: "システムオーディオ録音",
            chineseSimplified: "系统音频录制"
        )
    }
    static var microphonePermission: String {
        AppText.localized(
            english: "Microphone",
            korean: "마이크",
            japanese: "マイク",
            chineseSimplified: "麦克风"
        )
    }
    static var speechRecognitionPermission: String {
        AppText.localized(
            english: "Speech Recognition",
            korean: "음성 인식",
            japanese: "音声認識",
            chineseSimplified: "语音识别"
        )
    }
    static var screenRecordingPermissionDetail: String {
        AppText.localized(
            english: "Required to capture Mac audio. This check never requests permission.",
            korean: "PC 소리를 캡처하는 데 필요합니다. 이 확인 과정에서는 권한을 요청하지 않습니다.",
            japanese: "Mac音声のキャプチャに必要です。この確認では権限を要求しません。",
            chineseSimplified: "捕获 Mac 音频时需要。此检查不会请求权限。"
        )
    }
    static var systemAudioPermissionDetail: String {
        AppText.localized(
            english: "macOS can allow screen and audio together or audio only. Confirm the exact choice in System Settings.",
            korean: "macOS에서는 화면과 오디오를 함께 또는 오디오만 허용할 수 있습니다. 정확한 상태는 시스템 설정에서 확인하세요.",
            japanese: "macOSでは画面と音声の両方、または音声のみを許可できます。正確な状態はシステム設定で確認してください。",
            chineseSimplified: "macOS 可允许屏幕和音频，或仅允许音频。请在系统设置中确认确切状态。"
        )
    }
    static var microphonePermissionDetail: String {
        AppText.localized(
            english: "Required only when Microphone is selected as the audio input.",
            korean: "오디오 입력으로 마이크를 선택할 때만 필요합니다.",
            japanese: "音声入力にマイクを選択した場合のみ必要です。",
            chineseSimplified: "仅在音频输入选择麦克风时需要。"
        )
    }
    static var speechRecognitionPermissionDetail: String {
        AppText.localized(
            english: "Required for Apple speech recognition modes.",
            korean: "Apple 음성 인식 모드에 필요합니다.",
            japanese: "Apple音声認識モードに必要です。",
            chineseSimplified: "Apple 语音识别模式需要此权限。"
        )
    }
    static var permissionReadOnlyNotice: String {
        AppText.localized(
            english: "Statuses are read-only. Permission prompts are never shown from this page.",
            korean: "상태만 확인하며 이 화면에서 권한 요청 창을 띄우지 않습니다.",
            japanese: "状態の確認のみ行い、この画面から権限要求は表示しません。",
            chineseSimplified: "这里只读取状态，不会从此页面弹出权限请求。"
        )
    }
    static var refreshPermissionStatus: String {
        AppText.localized(
            english: "Refresh Status",
            korean: "상태 새로고침",
            japanese: "状態を更新",
            chineseSimplified: "刷新状态"
        )
    }
    static var openSystemSettings: String {
        AppText.localized(
            english: "Open Settings",
            korean: "설정 열기",
            japanese: "設定を開く",
            chineseSimplified: "打开设置"
        )
    }
    static var permissionAllowed: String {
        AppText.localized(
            english: "Allowed",
            korean: "허용됨",
            japanese: "許可済み",
            chineseSimplified: "已允许"
        )
    }
    static var permissionNotGranted: String {
        AppText.localized(
            english: "Not Allowed",
            korean: "허용 안 됨",
            japanese: "未許可",
            chineseSimplified: "未允许"
        )
    }
    static var permissionNotDetermined: String {
        AppText.localized(
            english: "Not Requested",
            korean: "요청 전",
            japanese: "未要求",
            chineseSimplified: "尚未请求"
        )
    }
    static var permissionRestricted: String {
        AppText.localized(
            english: "Restricted",
            korean: "제한됨",
            japanese: "制限あり",
            chineseSimplified: "受限"
        )
    }
    static var permissionUnknown: String {
        AppText.localized(
            english: "Check in Settings",
            korean: "설정에서 확인",
            japanese: "設定で確認",
            chineseSimplified: "在设置中确认"
        )
    }
    static var replaceSavedAPIKeyHint: String {
        AppText.localized(
            english: "A key is already saved. Entering and saving a new key replaces it.",
            korean: "키가 이미 저장되어 있습니다. 새 키를 입력해 저장하면 기존 키를 교체합니다.",
            japanese: "キーは保存済みです。新しいキーを入力して保存すると置き換えます。",
            chineseSimplified: "已有密钥。输入并保存新密钥会替换旧密钥。"
        )
    }
    static var saveNewAPIKeyHint: String {
        AppText.localized(
            english: "Enter a provider API key, then save it to macOS Keychain.",
            korean: "제공자 API 키를 입력한 뒤 macOS 키체인에 저장합니다.",
            japanese: "プロバイダーのAPIキーを入力し、macOSキーチェーンに保存します。",
            chineseSimplified: "输入提供商 API 密钥，然后保存到 macOS 钥匙串。"
        )
    }
    static var replaceSavedOpenAIKeyDetail: String {
        AppText.localized(
            english: "An OpenAI key is saved in macOS Keychain. Enter and save a new key to replace it.",
            korean: "OpenAI 키가 macOS 키체인에 저장되어 있습니다. 새 키를 입력하고 저장하면 교체됩니다.",
            japanese: "OpenAIキーはmacOSキーチェーンに保存済みです。新しいキーを入力して保存すると置き換えます。",
            chineseSimplified: "OpenAI 密钥已保存在 macOS 钥匙串中。输入并保存新密钥即可替换。"
        )
    }
    static var replaceSavedGeminiKeyDetail: String {
        AppText.localized(
            english: "A Gemini key is saved in macOS Keychain. Enter and save a new key to replace it.",
            korean: "Gemini 키가 macOS 키체인에 저장되어 있습니다. 새 키를 입력하고 저장하면 교체됩니다.",
            japanese: "GeminiキーはmacOSキーチェーンに保存済みです。新しいキーを入力して保存すると置き換えます。",
            chineseSimplified: "Gemini 密钥已保存在 macOS 钥匙串中。输入并保存新密钥即可替换。"
        )
    }
    static var required: String { AppText.localized(english: "Required", korean: "필수", japanese: "必須", chineseSimplified: "必需") }
    static var aboutAirTranslate: String { AppText.localized(english: "About 文译", korean: "文译 정보", japanese: "文译について", chineseSimplified: "关于文译") }
    static var version: String {
        AppText.localized(
            english: "Version",
            korean: "버전",
            japanese: "バージョン",
            chineseSimplified: "版本"
        )
    }
    static var versionInformation: String {
        AppText.localized(
            english: "Version Information",
            korean: "버전 정보",
            japanese: "バージョン情報",
            chineseSimplified: "版本信息"
        )
    }
    static var buildNumber: String {
        AppText.localized(
            english: "Build Number",
            korean: "빌드 번호",
            japanese: "ビルド番号",
            chineseSimplified: "构建号"
        )
    }
    static var versionUnavailable: String {
        AppText.localized(
            english: "Unavailable",
            korean: "확인할 수 없음",
            japanese: "確認できません",
            chineseSimplified: "无法获取"
        )
    }
    static var privacy: String { AppText.localized(english: "Privacy", korean: "개인정보", japanese: "プライバシー", chineseSimplified: "隐私") }
    static var privacyDetail: String {
        AppText.localized(
            english: "Apple mode runs locally. Cloud providers receive audio only after you save their API key, choose the mode, and start capture.",
            korean: "Apple 모드는 로컬에서 실행됩니다. 클라우드 제공업체는 해당 API 키를 저장하고 모드를 선택한 뒤 캡처를 시작하면 오디오를 받습니다.",
            japanese: "Appleモードはローカルで動作します。クラウドサービスにはAPIキーを保存し、モードを選択してキャプチャを開始したときに音声が送信されます。",
            chineseSimplified: "本体模型在本机运行。保存对应 API 密钥、选择模式并开始采集后，音频才会发送给云服务。"
        )
    }
    static var retry: String {
        AppText.localized(
            english: "Retry",
            korean: "다시 시도",
            japanese: "再試行",
            chineseSimplified: "重试"
        )
    }
    static var assetDownloadNotice: String {
        AppText.localized(
            english: "Language assets download to this Mac. Size varies by language and macOS version; progress and errors appear here.",
            korean: "언어 자산은 이 Mac에 내려받습니다. 크기는 언어와 macOS 버전에 따라 달라지며 진행 및 오류 상태는 이 화면에 표시됩니다.",
            japanese: "言語アセットはこのMacにダウンロードされます。容量は言語とmacOSのバージョンにより異なり、進行状況とエラーはここに表示されます。",
            chineseSimplified: "语言资源会下载到这台 Mac。大小因语言和 macOS 版本而异，进度和错误会显示在此处。"
        )
    }
}

private struct SettingsSidebar: View {
    @Binding var selection: SettingsCategory

    private var selectedRow: Binding<SettingsCategory?> {
        Binding(
            get: { selection },
            set: { if let category = $0 { selection = category } }
        )
    }

    var body: some View {
        List(selection: selectedRow) {
            ForEach(SettingsCategory.allCases) { category in
                Label(category.title, systemImage: category.systemImage)
                    .tag(category)
            }
        }
        .listStyle(.sidebar)
        .tint(AirTranslateDesign.Palette.accent)
    }
}

private enum SettingsPermissionState: Equatable {
    case allowed
    case notGranted
    case denied
    case restricted
    case notDetermined
    case unknown

    var title: String {
        switch self {
        case .allowed:
            SettingsCopy.permissionAllowed
        case .notGranted, .denied:
            SettingsCopy.permissionNotGranted
        case .restricted:
            SettingsCopy.permissionRestricted
        case .notDetermined:
            SettingsCopy.permissionNotDetermined
        case .unknown:
            SettingsCopy.permissionUnknown
        }
    }

    var color: Color {
        switch self {
        case .allowed:
            AirTranslateDesign.Palette.live
        case .notDetermined, .unknown:
            AirTranslateDesign.Palette.warning
        case .notGranted, .denied, .restricted:
            AirTranslateDesign.Palette.danger
        }
    }

    var systemImage: String {
        switch self {
        case .allowed:
            "checkmark.circle.fill"
        case .notDetermined, .unknown:
            "questionmark.circle.fill"
        case .notGranted, .denied, .restricted:
            "xmark.circle.fill"
        }
    }
}

private struct SettingsPermissionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let status: SettingsPermissionState
    let openSettings: () -> Void

    var body: some View {
        SettingsControlRow(title: title, detail: detail, systemImage: systemImage) {
            HStack(spacing: 10) {
                Label(status.title, systemImage: status.systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(status.color)
                    .accessibilityLabel("\(title): \(status.title)")

                if status != .allowed && status != .notDetermined {
                    Button(action: openSettings) {
                        Label(SettingsCopy.openSystemSettings, systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel("\(title), \(SettingsCopy.openSystemSettings)")
                }
            }
        }
    }
}

struct SettingsNoticeRow: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(AirTranslateDesign.Palette.warning)
                .frame(width: 28, height: 28)

            Text(text)
                .font(AirTranslateDesign.Typography.meta.weight(.semibold))
                .foregroundStyle(AirTranslateDesign.Palette.warning)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(AirTranslateDesign.Spacing.sm)
        .background(
            AirTranslateDesign.Palette.pausedSoft,
            in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous)
        )
        .padding(.leading, settingsLabelIndent)
        .padding(.vertical, AirTranslateDesign.Spacing.xxs)
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsNoticeActionRow: View {
    let text: String
    let systemImage: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            noticeLabel
                .frame(maxWidth: .infinity, alignment: .leading)

            actionButton
                .fixedSize()
        }
        .padding(AirTranslateDesign.Spacing.sm)
        .background(
            AirTranslateDesign.Palette.pausedSoft,
            in: RoundedRectangle(cornerRadius: AirTranslateDesign.Radius.control, style: .continuous)
        )
        .padding(.leading, settingsLabelIndent)
        .padding(.vertical, AirTranslateDesign.Spacing.xxs)
    }

    private var noticeLabel: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(AirTranslateDesign.Palette.warning)
                .frame(width: 28, height: 28)

            Text(text)
                .font(AirTranslateDesign.Typography.meta.weight(.semibold))
                .foregroundStyle(AirTranslateDesign.Palette.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionButton: some View {
        Button(action: action) {
            Label(actionTitle, systemImage: "arrow.right.circle.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(actionTitle)
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AirTranslateDesign.Spacing.xs) {
            Text(title)
                .font(AirTranslateDesign.Typography.sectionLabel)
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)

            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, AirTranslateDesign.Spacing.md)
            .padding(.vertical, AirTranslateDesign.Spacing.xxs)
            .airRaisedSurface()
        }
    }
}

struct SettingsControlRow<Trailing: View>: View {
    let title: String
    let detail: String
    let systemImage: String
    var detailLineLimit: Int? = 3
    var showsSeparator = true
    var controlBelowLabel = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        Group {
            if controlBelowLabel {
                stackedRow
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 10) {
                        rowLabel
                        Spacer(minLength: 16)
                        trailing
                            .controlSize(.regular)
                            .frame(maxWidth: 360, alignment: .trailing)
                    }
                    .frame(minWidth: AirTranslateDesign.settingsRowBreakpoint)

                    stackedRow
                }
            }
        }
        .frame(minHeight: 64)
        .padding(.vertical, AirTranslateDesign.Spacing.xs)
        .settingsRowSeparator(visible: showsSeparator)
    }

    private var rowLabel: some View {
        SettingsRowLabel(title: title, detail: detail, systemImage: systemImage, detailLineLimit: detailLineLimit)
    }

    private var stackedRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            rowLabel
                .frame(maxWidth: .infinity, alignment: .leading)

            trailing
                .controlSize(.regular)
                .padding(.leading, settingsLabelIndent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    let systemImage: String
    var detailLineLimit: Int? = 3
    @Binding var isOn: Bool

    var body: some View {
        SettingsControlRow(title: title, detail: detail, systemImage: systemImage, detailLineLimit: detailLineLimit, controlBelowLabel: true) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(AirTranslateDesign.Palette.accent)
        }
    }
}

private struct SettingsVolumeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let accessibilityLabel: String

    var body: some View {
        HStack(spacing: 10) {
            Slider(value: $value, in: range, step: 0.05)
                .frame(width: 150)
                .tint(AirTranslateDesign.Palette.accent)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityValue("\(Int((value * 100).rounded()))%")

            Text("\(Int((value * 100).rounded()))%")
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
                .accessibilityHidden(true)
        }
    }
}

private struct SettingsValueRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let value: String
    var showsSeparator = true

    var body: some View {
        SettingsControlRow(title: title, detail: detail, systemImage: systemImage, showsSeparator: showsSeparator) {
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }
}

private let settingsRowIconWidth: CGFloat = 20
private let settingsRowIconSpacing: CGFloat = 9
let settingsLabelIndent = settingsRowIconWidth + settingsRowIconSpacing

private struct SettingsRowLabel: View {
    let title: String
    let detail: String
    let systemImage: String

    var detailLineLimit: Int? = 3

    var body: some View {
        HStack(alignment: .top, spacing: settingsRowIconSpacing) {
            Image(systemName: systemImage)
                .font(.system(size: AirTranslateDesign.iconRegular, weight: .medium))
                .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                .frame(width: settingsRowIconWidth, height: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(AirTranslateDesign.Typography.label.weight(.semibold))
                    .foregroundStyle(AirTranslateDesign.Palette.textPrimary)

                if !detail.isEmpty {
                    Text(detail)
                        .font(AirTranslateDesign.Typography.meta)
                        .foregroundStyle(AirTranslateDesign.Palette.textSecondary)
                        .lineLimit(detailLineLimit)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(minWidth: 210, idealWidth: 230, maxWidth: 300, alignment: .leading)
        .layoutPriority(1)
    }
}

private struct SettingsAssetAvailabilityRow: View {
    let title: String
    let availability: ModelAvailability
    let download: () -> Void

    var body: some View {
        SettingsControlRow(
            title: title,
            detail: availability.detail,
            systemImage: symbolName
        ) {
            if availability.state == .checking || availability.state == .downloading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)

                    assetStateLabel
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(title) \(availability.state.title)")
            } else if availability.state.canDownload {
                HStack(spacing: 10) {
                    assetStateLabel

                    Button(availability.state == .failed ? SettingsCopy.retry : AppText.download) {
                        download()
                    }
                    .accessibilityLabel(
                        "\(title) \(availability.state == .failed ? SettingsCopy.retry : AppText.download)"
                    )
                }
            } else {
                assetStateLabel
                    .accessibilityLabel("\(title) \(availability.state.title)")
            }
        }
        .help(availability.detail)
    }

    private var assetStateLabel: some View {
        Text(availability.state.title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(color)
    }

    private var symbolName: String {
        switch availability.state {
        case .checking:
            "clock"
        case .installed:
            "checkmark.seal.fill"
        case .downloadRequired, .downloading:
            "arrow.down.circle.fill"
        case .unsupported, .unavailable, .failed:
            "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch availability.state {
        case .checking:
            AirTranslateDesign.Palette.textSecondary
        case .installed:
            AirTranslateDesign.Palette.live
        case .downloadRequired, .downloading:
            AirTranslateDesign.Palette.warning
        case .unsupported, .unavailable, .failed:
            AirTranslateDesign.Palette.danger
        }
    }
}

private extension View {
    func settingsRowSeparator(visible: Bool = true) -> some View {
        overlay(alignment: .bottom) {
            if visible {
                Rectangle()
                    .fill(AirTranslateDesign.Palette.hairline)
                    .frame(height: 1)
                    .padding(.leading, 42)
            }
        }
    }
}
