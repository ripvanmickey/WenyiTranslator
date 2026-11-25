import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct PausedProviderSettingsTests {
    private func withSession(_ preferences: [String: Any], body: (TranslationSessionStore) throws -> Void) throws {
        let name = "PausedProviderSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        for (key, value) in preferences { defaults.set(value, forKey: key) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] },
            settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        try body(session)
    }

    @Test func retiredSelectionsCannotBeActivatedEvenWithKeys() throws {
        try withSession([:]) { session in
            session.hasAzureSpeechAPIKey = true
            session.hasNariAPIKey = true
            for engine in [ProcessingEngine.azure, .nari] {
                #expect(!ProcessingEngine.selectableCases.contains(engine))
                #expect(!engine.select(in: session))
            }
            session.useAzureMAIMode()
            session.useNariSTTMode()
            #expect(!session.isUsingAzureMAI)
            #expect(!session.isUsingNariSTT)
            for provider in [CredentialProvider.azure, .nari, .jev] {
                #expect(!CredentialProvider.selectableCases.contains(provider))
                session.requestAPIKeySettings(provider: provider)
                #expect(session.requestedAPIKeyProvider == nil)
            }
        }
    }

    @Test func oldPreferencesCannotResumeRetiredServices() throws {
        for preferences: [String: Any] in [
            ["azureMAIEnabled": true],
            ["nariTranscriptionModelID": NariTranscriptionModel.qwen3ASRFast.rawValue,
             "selectedModelID": IntelligenceModel.appleSpeechOnly.rawValue],
            ["isJevSelectionEnabled": true]
        ] {
            try withSession(preferences) { session in
                #expect(!session.isUsingAzureMAI)
                #expect(!session.isUsingNariSTT)
                #expect(!session.isJevSelectionEnabled)
                #expect(!session.isJevSelectionAvailable)
                #expect(!session.isUsingJevSelection)
                #expect(ProcessingEngine.current(for: session) == .apple)
                session.isJevSelectionEnabled = true
                #expect(!session.isUsingJevSelection)
            }
        }
    }

    @Test func supportedProviderAndLanguagePreferencesArePreserved() throws {
        try withSession(["azureMAIEnabled": true, "isJevSelectionEnabled": true,
                         "geminiTranslationModelID": GeminiTranslationModel.gemini35LiveTranslate.rawValue,
                         "sourceLanguageID": "ja-JP", "targetLanguageID": "zh-CN"]) { session in
            #expect(ProcessingEngine.current(for: session) == .gemini)
            #expect(session.sourceLanguage.id == "ja-JP")
            #expect(session.targetLanguage.id == "zh-CN")
            #expect(!session.isUsingJevSelection)
        }
    }
}
