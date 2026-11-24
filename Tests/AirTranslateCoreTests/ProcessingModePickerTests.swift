import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct ProcessingModePickerTests {
    private func withSession(preferences: [String: Any] = [:], _ body: (TranslationSessionStore) throws -> Void) throws {
        let name = "ProcessingModePickerTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        for (key, value) in preferences { defaults.set(value, forKey: key) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        setKeys(session, enabled: false)
        defer {
            session.isRunning = false
            session.isStarting = false
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
        try body(session)
    }

    private func setKeys(_ session: TranslationSessionStore, enabled: Bool) {
        session.hasOpenAIAPIKey = enabled
        session.hasGeminiAPIKey = enabled
        session.hasMetaAPIKey = enabled
        session.hasAzureSpeechAPIKey = enabled
        session.hasNariAPIKey = enabled
        session.hasGrokAPIKey = enabled
        session.hasQwenAPIKey = enabled
    }

    @Test func onlyLocalAndIndexModesUseOnDeviceRecognition() {
        #expect(ProcessingEngine.allCases.filter(\.usesOnDeviceRecognition) == [.apple, .indexOnline])
    }

    @Test func freshSettingsUseNemotronInLocalAndIndexModes() throws {
        try withSession { session in
            #expect(session.localRecognitionEngine == "nemotron")
            #expect(ProcessingEngine.indexOnline.select(in: session))
            #expect(session.localRecognitionEngine == "nemotron")

            session.localRecognitionEngine = "qwen"
            #expect(ProcessingEngine.apple.select(in: session))
            #expect(session.localRecognitionEngine == "qwen")
        }
    }

    @Test func openAITranscriptionTitleShowsCloudProviderWithNemotronConfigured() throws {
        try withSession { session in
            session.useOpenAIMode(.transcription)
            #expect(session.localRecognitionEngine == "nemotron")
            #expect(session.processingEngineTitle == ProcessingEngine.openAI.title)
        }
    }

    @Test func openAICanUseLocalASRAndTextTranslation() throws {
        try withSession { session in
            session.useOpenAIMode(.translation)
            session.localRecognitionEngine = "qwen"
            session.useOpenAIOnDeviceRecognition(true)
            #expect(ProcessingEngine.current(for: session) == .openAI)
            #expect(session.localRecognitionEngine == "qwen")
            #expect(session.openAITranslationModel == .gpt41Mini)
            #expect(!session.isUsingOpenAIRealtime)
            #expect(!session.isUsingProviderRealtimeTranslation)
            #expect(!session.isTranscribeOnlyMode)
            #expect(session.openAITranscriptionModel == .off)
            #expect(session.processingEngineTitle.contains("GPT-4.1 mini"))
            #expect(session.startReadinessAssessment().issue == .openAIAPIKeyMissing)
            session.hasOpenAIAPIKey = true
            #expect(session.startReadinessAssessment().canStart)
            session.useOpenAIOnDeviceRecognition(false)
            #expect(session.isUsingOpenAIRealtimeTranslation)
            #expect(session.openAITranslationModel == .gptRealtimeTranslate)
        }
    }

    @Test func openAILocalRecognitionRestoresAndCannotChangeDuringCapture() throws {
        try withSession(preferences: [
            "openAITranslationModelID": "gpt-4.1-mini",
            "whisperRecognitionEnabled": true,
            "nemotronRecognitionEnabled": true,
        ]) { session in
            #expect(session.openAITranslationModel == .gpt41Mini)
            #expect(session.localRecognitionEngine == "nemotron")
            #expect(!session.isUsingOpenAIRealtime)
            session.isRunning = true
            session.useOpenAIOnDeviceRecognition(false)
            #expect(session.openAITranslationModel == .gpt41Mini)
            session.isRunning = false
            session.isStarting = true
            session.useOpenAIOnDeviceRecognition(false)
            #expect(session.openAITranslationModel == .gpt41Mini)
        }
    }

    @Test func previouslySelectedAppleSpeechIsRestored() throws {
        guard PlatformSupport.supportsAppleSpeech else { return }
        try withSession(preferences: ["whisperRecognitionEnabled": false]) { session in
            #expect(session.localRecognitionEngine == "apple")
        }
    }

    @Test func nemotronWithAppleTranslationRequiresTranslationAssetsOnly() throws {
        guard PlatformSupport.supportsAppleSpeech else { return }
        try withSession { session in
            session.modelAvailabilityByModelID = [
                IntelligenceModel.appleSystem.id: .init(state: .downloadRequired, detail: ""),
                IntelligenceModel.appleSpeechOnly.id: .init(state: .downloadRequired, detail: ""),
                IntelligenceModel.appleOnDevice.id: .init(state: .installed, detail: ""),
            ]
            #expect(session.startReadinessAssessment().canStart)
        }
    }

    @Test func retiredGraniteSelectionRestoresNemotronWithoutChangingOnlineTranslation() throws {
        var configuration = LocalTranslationConfiguration()
        configuration.onlineIndex = true
        try withSession(preferences: [
            "whisperRecognitionEnabled": true,
            "nemotronRecognitionEnabled": true,
            "graniteRecognitionEnabled": true,
            "localTranslationConfiguration": try JSONEncoder().encode(configuration),
        ]) { session in
            #expect(session.localRecognitionEngine == "nemotron")
            #expect(session.qwenASRModel.isEmpty)
            #expect(ProcessingEngine.current(for: session) == .indexOnline)
        }
    }

    @Test func keyPresenceEnablesOnlyItsProvider() throws {
        try withSession { session in
            #expect(ProcessingEngine.allCases.filter { $0.canSelect(in: session) } == [.apple, .indexOnline])
            let providers: [(CredentialProvider, ReferenceWritableKeyPath<TranslationSessionStore, Bool>)] = [
                (.openAI, \.hasOpenAIAPIKey), (.gemini, \.hasGeminiAPIKey),
                (.meta, \.hasMetaAPIKey), (.azure, \.hasAzureSpeechAPIKey),
                (.nari, \.hasNariAPIKey), (.grok, \.hasGrokAPIKey), (.qwen, \.hasQwenAPIKey),
            ]
            for (provider, keyPath) in providers {
                setKeys(session, enabled: false)
                session[keyPath: keyPath] = true
                for engine in ProcessingEngine.allCases {
                    #expect(engine.canSelect(in: session) == (engine.credentialProvider == nil || engine.credentialProvider == provider))
                }
            }
        }
    }

    @Test func missingKeysAndCaptureLockRejectSelection() throws {
        try withSession { session in
            for engine in ProcessingEngine.allCases where engine.credentialProvider != nil {
                #expect(!engine.select(in: session))
                #expect(ProcessingEngine.current(for: session) == .apple)
            }
            setKeys(session, enabled: true)
            session.useGrokSTTMode()
            for (running, starting, paused) in [(true, false, false), (false, true, false), (true, false, true)] {
                session.isRunning = running
                session.isStarting = starting
                session.isPaused = paused
                for engine in ProcessingEngine.allCases {
                    #expect(!engine.select(in: session))
                    #expect(ProcessingEngine.current(for: session) == .grok)
                }
            }
        }
    }

    @Test func enabledModesSwitchAndPreserveGeminiPreference() throws {
        try withSession { session in
            setKeys(session, enabled: true)
            session.useGeminiMode(.gemini35TranscribeLive)
            for engine in ProcessingEngine.allCases {
                #expect(engine.select(in: session))
                #expect(ProcessingEngine.current(for: session) == engine)
                if engine == .gemini {
                    #expect(session.geminiTranslationModel == .gemini35TranscribeLive)
                }
            }
            #expect(ProcessingEngine.apple.select(in: session))
            #expect(ProcessingEngine.current(for: session) == .apple)
        }
    }

    @Test func onlineIndexSwitchesIndependentlyOfLocalTranslation() throws {
        try withSession { session in
            var config = session.localTranslation
            config.enabled = false
            config.baseURL = "http://localhost:1235/v1"
            config.modelID = "index-translate-9b"
            session.localTranslation = config
            let recognition = session.recognitionEngineTitle

            #expect(ProcessingEngine.indexOnline.select(in: session))
            #expect(ProcessingEngine.current(for: session) == .indexOnline)
            #expect(session.isUsingLocalTranslation)
            #expect(session.localTranslation.activeModelID == LocalTranslationConfiguration.indexModelID)
            #expect(session.recognitionEngineTitle == recognition)
            session.useLiveOutputMode(.transcription)
            #expect(ProcessingEngine.current(for: session) == .indexOnline)
            #expect(!session.isUsingLocalTranslation)
            session.useLiveOutputMode(.translation)
            #expect(session.isUsingLocalTranslation)

            #expect(ProcessingEngine.apple.select(in: session))
            #expect(ProcessingEngine.current(for: session) == .apple)
            #expect(session.localTranslation == config)

            session.enableLocalTranslation(true)
            #expect(ProcessingEngine.indexOnline.select(in: session))
            #expect(ProcessingEngine.apple.select(in: session))
            #expect(session.isUsingLocalTranslation)
            #expect(session.localTranslation.activeModelID == config.modelID)
        }
    }

    @Test func sameModeDoesNotResetOutputPreferences() throws {
        try withSession { session in
            setKeys(session, enabled: true)
            session.useAppleDefaultMode()
            session.useTranscribeOnlyMode()
            #expect(ProcessingEngine.apple.select(in: session))
            #expect(session.isTranscribeOnlyMode)
            for engine in [ProcessingEngine.nari, .grok] {
                #expect(engine.select(in: session))
                session.useTranslationMode()
                #expect(engine.select(in: session))
                #expect(!session.isTranscribeOnlyMode)
            }
        }
    }

    @Test func settingsRemainAccessibleWithoutKeysAndDuringCaptureWithoutSwitchingMode() throws {
        try withSession { session in
            session.useTranscribeOnlyMode()
            session.isStarting = true
            let source = session.sourceLanguage
            let target = session.targetLanguage
            let dubbing = session.isDubbingEnabled
            for engine in ProcessingEngine.allCases {
                engine.requestSettings(in: session)
                #expect(session.requestedSettingsCategoryID == (engine.credentialProvider == nil ? "general" : "apiKeys"))
                #expect(session.requestedAPIKeyProvider == engine.credentialProvider)
                #expect(ProcessingEngine.current(for: session) == .apple)
                #expect(session.isTranscribeOnlyMode)
                #expect(session.sourceLanguage == source && session.targetLanguage == target)
                #expect(session.isDubbingEnabled == dubbing)
            }
            session.requestAPIKeySettings()
            #expect(session.requestedAPIKeyProvider == nil)
        }
    }

    @Test func tooltipFollowsTheModelThatSelectingTheRowWillUse() throws {
        try withSession { session in
            let defaultNari = ProcessingEngine.nari.information(in: session)
            #expect(defaultNari.modelID == NariTranscriptionModel.qwen3ASRFast.rawValue)
            #expect(defaultNari.price.contains("0.12"))
            session.useNariSTTMode()
            session.nariTranscriptionModel = .qwen3ASR
            #expect(ProcessingEngine.nari.information(in: session).price.contains("0.06"))
            session.nariTranscriptionModel = .qwen3ASRFree
            let retired = ProcessingEngine.nari.information(in: session)
            #expect(!retired.price.contains("US$"))
            session.useAppleDefaultMode()
            #expect(ProcessingEngine.nari.information(in: session).modelID == defaultNari.modelID)

            session.useGeminiMode(.gemini35TranscribeLive)
            session.useAppleDefaultMode()
            let preferred = ProcessingEngine.gemini.information(in: session)
            #expect(preferred.modelID == GeminiTranslationModel.gemini35TranscribeLive.rawValue)
            #expect(preferred.price.contains("0.009"))
            #expect(ProcessingEngine.current(for: session) == .apple)
            #expect(session.requestedSettingsCategoryID == nil)
        }
    }

    @Test func tooltipPricesDistinguishStreamingEstimatesPromotionsAndRetiredModels() {
        #expect(ProcessingModeInfo.information(for: .grok).price.contains("0.20"))
        #expect(!ProcessingModeInfo.information(for: .grok).price.contains("0.10"))
        #expect(ProcessingModeInfo.information(for: .azure).price.contains("2026-12-31"))
        #expect(ProcessingModeInfo.information(for: .gemini).price.contains("0.0368"))
        for model in [NariTranscriptionModel.qwen3ASRFree, .qwen3ASRFastFree] {
            #expect(!ProcessingModeInfo.information(for: .nari, nariModel: model).price.contains("US$"))
        }
        for engine in ProcessingEngine.allCases {
            let info = ProcessingModeInfo.information(for: engine)
            #expect(info.tooltip.split(separator: "\n").count == 2)
        }
    }

}
