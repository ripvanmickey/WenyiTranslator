import Foundation
import Security
import Testing
@testable import AirTranslate

@Suite(.serialized)
struct CloudflareTranslationTests {
    @Test @MainActor func cloudflareRecoveryOpensItsOwnConfigurationAndHasCorrectLabel() throws {
        for error in [CloudflareTranslationError.consent, .configuration, .missingKey, .http(401), .http(403)] {
            #expect(CaptureStartRecoveryAction.forFailure(error, audioInputSource: .microphone) == .cloudflareSettings)
        }
        #expect(CaptureStartRecoveryAction.forFailure(CloudflareTranslationError.timeout, audioInputSource: .microphone) == .retry)
        #expect(CaptureStartRecoveryAction.cloudflareSettings.title == CloudflareCopy.configure)
        #expect(!CaptureStartRecoveryAction.generalSettings.title.contains("Nari"))
        let name = "CloudflareRecovery.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults,
            transcriptsDirectoryURL: FileManager.default.temporaryDirectory.appendingPathComponent(name))
        CaptureStartRecoveryAction.cloudflareSettings.requestSettings(in: session)
        #expect(session.requestedAPIKeyProvider == .cloudflare)
        #expect(session.requestedSettingsCategoryID == "apiKeys")
    }
    private var valid: CloudflareConfiguration {
        .init(accountID: String(repeating: "a", count: 32), allowsTextSharing: true)
    }
    @Test func requestsUseAccountScopedFixedHostAndSeparateBearerToken() throws {
        let request = try CloudflareTranslationService.request("テスト", source: "ja-JP", target: "zh-CN", configuration: valid, key: "test-token")
        #expect(request.url?.absoluteString == "https://api.cloudflare.com/client/v4/accounts/" + String(repeating: "a", count: 32) + "/ai/v1/chat/completions")
        #expect(request.url?.query == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(request.timeoutInterval == 25)
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["model"] as? String == CloudflareConfiguration.defaultModel)
        #expect(json["stream"] as? Bool == false)
        #expect(json["audio"] == nil)
        #expect(!String(decoding: body, as: UTF8.self).contains("test-token"))
        let messages = try #require(json["messages"] as? [[String: String]])
        #expect(messages.last?["content"] == "テスト")
    }
    @Test func invalidAccountModelTokenAndMissingConsentNeverProduceRequests() {
        for account in ["", "https://example.com", "../" + String(repeating: "a", count: 32), String(repeating: "x", count: 32)] {
            var configuration = valid; configuration.accountID = account
            #expect(throws: CloudflareTranslationError.self) { try CloudflareTranslationService.request("Hello", source: "en", target: "zh", configuration: configuration, key: "test-token") }
        }
        for model in ["", "gpt-4.1", "@cf/meta/test?key=x", "@cf/meta/test\n"] {
            var configuration = valid; configuration.modelID = model
            // Trailing whitespace is intentionally trimmed, not treated as part of a model ID.
            if model.hasSuffix("\n") { configuration.modelID = "@cf/meta/te\nst" }
            #expect(throws: CloudflareTranslationError.self) { try CloudflareTranslationService.request("Hello", source: "en", target: "zh", configuration: configuration, key: "test-token") }
        }
        var noConsent = valid; noConsent.allowsTextSharing = false
        #expect(throws: CloudflareTranslationError.self) { try CloudflareTranslationService.request("Hello", source: "en", target: "zh", configuration: noConsent, key: "test-token") }
        for key: String? in [nil, "", "test\nvalue"] {
            #expect(throws: CloudflareTranslationError.self) { try CloudflareTranslationService.request("Hello", source: "en", target: "zh", configuration: valid, key: key) }
        }
    }
    @Test func onlyCompleteTranslationsAreAcceptedAndProviderErrorsAreSanitized() throws {
        let good = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":" 你好。 "}}]}"#.utf8)
        #expect(try CloudflareTranslationService.translation(good, status: 200) == "你好。")
        for invalid in [#"{"choices":[{"finish_reason":"length","message":{"content":"partial"}}]}"#,
                        #"{"choices":[{"finish_reason":"stop","message":{"content":""}}]}"#,
                        #"{"choices":[{"message":{"content":"unfinished"}}]}"#, #"{}"#] {
            #expect(throws: CloudflareTranslationError.self) { try CloudflareTranslationService.translation(Data(invalid.utf8), status: 200) }
        }
        do { _ = try CloudflareTranslationService.translation(Data("sensitive-token-echo".utf8), status: 403) }
        catch { #expect(!error.localizedDescription.contains("sensitive-token-echo")) }
    }
    @Test func accountAndModelSeparateCacheButConsentAndTokenAreNotInCacheIdentity() {
        var other = valid; other.modelID = CloudflareConfiguration.models[1]
        #expect(valid.cacheIdentity != other.cacheIdentity)
        other = valid; other.accountID = String(repeating: "b", count: 32)
        #expect(valid.cacheIdentity != other.cacheIdentity)
        other = valid; other.allowsTextSharing = false
        #expect(valid.cacheIdentity == other.cacheIdentity)
        #expect(!valid.cacheIdentity.contains(valid.accountID))
    }
    @Test func legacyLocalConfigurationStillDecodesWithoutEnablingCloudflare() throws {
        let data = Data(#"{"enabled":true,"baseURL":"http://localhost:1235/v1","modelID":"local-test","onlineIndex":true}"#.utf8)
        let decoded = try JSONDecoder().decode(LocalTranslationConfiguration.self, from: data)
        #expect(!decoded.usesCloudflare)
        #expect(decoded.usesOnlineIndex)
        #expect(try decoded.validatedBaseURL().host == "index-translate.bilibili.com")
        var config = decoded; config.onlineIndex = nil
        #expect(try config.validatedBaseURL().host == "localhost")
        config.baseURL = "https://api.cloudflare.com/v1"
        #expect(throws: LocalTranslationError.self) { try config.validatedBaseURL() }
    }
    @Test func networkFailureAndRateLimitDoNotRetryOrEchoTokens() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [CloudflareTestProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let service = CloudflareTranslationService(session: session)
        CloudflareTestProtocol.calls = 0; CloudflareTestProtocol.status = 429; CloudflareTestProtocol.failure = nil
        do { _ = try await service.translate("Hello", source: "en", target: "zh", configuration: valid, key: "fake-test-token"); Issue.record("Expected quota error") }
        catch let error as CloudflareTranslationError {
            if case .http(429) = error {} else { Issue.record("Expected HTTP 429") }
            #expect(!error.localizedDescription.contains("fake-test-token"))
        }
        #expect(CloudflareTestProtocol.calls == 1)
        CloudflareTestProtocol.failure = .timedOut
        do { _ = try await service.translate("Hello", source: "en", target: "zh", configuration: valid, key: "fake-test-token"); Issue.record("Expected timeout") }
        catch let error as CloudflareTranslationError { if case .timeout = error {} else { Issue.record("Expected timeout") } }
        #expect(CloudflareTestProtocol.calls == 2)
    }
    @Test @MainActor func providerSelectionRestoresAndSwitchesWithoutChangingRecognitionEngine() throws {
        let name = "CloudflareSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { defaults.removePersistentDomain(forName: name); try? FileManager.default.removeItem(at: directory) }
        let session = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        let engine = session.localRecognitionEngine
        var saved = session.localTranslation
        saved.cloudflareAccountID = valid.accountID; saved.cloudflareTextSharingAllowed = true
        session.localTranslation = saved
        session.useCloudflareTranslation()
        #expect(session.isUsingLocalTranslation)
        #expect(ProcessingEngine.current(for: session) == .cloudflare)
        #expect(session.localRecognitionEngine == engine)
        #expect(ProcessingEngine.cloudflare.usesOnDeviceRecognition)
        session.hasCloudflareAPIKey = true
        let media = VideoSubtitlePreloadStore(); media.captionSession = session
        media.videoURL = "https://www.youtube.com/watch?v=PMGSdzyRZUw"; media.translator = .cloudflare
        let firstKey = media.cacheSelectionKey
        saved = session.localTranslation; saved.cloudflareModelID = CloudflareConfiguration.models[1]; session.localTranslation = saved
        #expect(firstKey != media.cacheSelectionKey)
        let restored = TranslationSessionStore(modelAvailabilityProvider: { _, _ in [:] }, settingsDefaults: defaults, transcriptsDirectoryURL: directory)
        #expect(ProcessingEngine.current(for: restored) == .cloudflare)
        #expect(restored.localRecognitionEngine == engine)
        session.isRunning = true
        #expect(!ProcessingEngine.apple.select(in: session))
        session.isRunning = false
        session.enableOnlineIndexTranslation()
        #expect(!session.localTranslation.usesCloudflare)
        #expect(ProcessingEngine.current(for: session) == .indexOnline)
        session.useCloudflareTranslation(); session.useAppleDefaultMode()
        #expect(!session.localTranslation.usesCloudflare)
        #expect(session.localTranslation.cloudflareAccountID == valid.accountID)
    }
    @Test func activeProvidersHaveDistinctLocalBrandAssetsAndKeychainNamespace() {
        let logos = CredentialProvider.selectableCases.compactMap(\.logoName)
        #expect(logos.count == CredentialProvider.selectableCases.count)
        #expect(Set(logos).count == logos.count)
        let query = CloudflareAPIKeyStore.presenceQuery()
        #expect(query[kSecAttrService as String] as? String == "AirTranslate.Cloudflare")
        #expect(query[kSecReturnData as String] == nil)
    }
}

private final class CloudflareTestProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var calls = 0
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var failure: URLError.Code?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        if let failure = Self.failure { client?.urlProtocol(self, didFailWithError: URLError(failure)); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("fake-test-token-echo".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
