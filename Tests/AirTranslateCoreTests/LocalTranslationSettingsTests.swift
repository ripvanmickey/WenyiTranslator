import Foundation
import Testing
@testable import AirTranslate

@Suite(.serialized)
@MainActor
struct LocalTranslationSettingsTests {
    @Test func localConfigurationRestoresAndDoesNotOverrideCloudAudioMode() throws {
        let name = "LocalTranslationSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
        defer { session.prepareForTermination() }
        session.sourceLanguage = .english
        session.targetLanguage = .korean
        session.localTranslation.modelID = "qwen/local-test"
        session.enableLocalTranslation(true)
        #expect(session.isUsingLocalTranslation)
        #expect(!session.isUsingAppleTextTranslation)
        #expect(!session.isUsingJevSelection)
        #expect(!session.isDubbingEnabled)
        let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
        defer { restored.prepareForTermination() }
        #expect(restored.localTranslation == session.localTranslation)
        restored.useGPTTranscriptionMode()
        #expect(!restored.isUsingLocalTranslation)
        #expect(restored.localTranslation.enabled)
    }

    @Test func configurationIsLockedDuringCapture() throws {
        let name = "LocalTranslationLockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults)
        defer { session.prepareForTermination() }
        session.localTranslation.modelID = "qwen/local-test"
        _ = session.activateLiveCallbackPipelineForTesting()
        let locked = session.localTranslation
        session.localTranslation.baseURL = "http://localhost:9999/v1"
        session.enableLocalTranslation(true)
        #expect(session.localTranslation == locked)
    }
}
