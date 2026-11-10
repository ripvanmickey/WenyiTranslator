import Foundation
import Testing
@testable import AirTranslate

private final class LocalTranslationMockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct LocalTranslationServiceTests {
    private func client() -> LocalTranslationService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [LocalTranslationMockProtocol.self]
        return LocalTranslationService(session: URLSession(configuration: config))
    }
    private func config() -> LocalTranslationConfiguration {
        LocalTranslationConfiguration(enabled: true, baseURL: "http://localhost:1235/v1", modelID: "local/test")
    }

    @Test func acceptsOnlyLocalV1Addresses() throws {
        for address in ["http://localhost:1235/v1", "http://127.0.0.1:1235/v1/", "http://[::1]:1235/v1"] {
            var config = config(); config.baseURL = address
            _ = try config.validatedBaseURL()
        }
        for address in ["https://example.com/v1", "http://localhost.evil.test/v1", "file:///v1", "http://localhost/v1?key=secret", "http://user:pass@localhost/v1", "http://localhost/v1/chat/completions"] {
            var config = config(); config.baseURL = address
            #expect(throws: LocalTranslationError.self) { try config.validatedBaseURL() }
        }
    }

    @Test func discoversModelIDsAndUsesOptionalLocalCredential() async throws {
        LocalTranslationMockProtocol.handler = { request in
            #expect(request.url?.absoluteString == "http://localhost:1235/v1/models")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer local-secret")
            return (200, Data(#"{"data":[{"id":"qwen/b"},{"id":"qwen/a"},{"id":"qwen/b"}]}"#.utf8))
        }
        let models = try await client().models(configuration: config(), apiKey: "local-secret")
        #expect(models == ["qwen/a", "qwen/b"])
    }

    @Test func translatesWithoutLeakingReasoningIntoCaptions() async throws {
        LocalTranslationMockProtocol.handler = { request in
            #expect(request.url?.path == "/v1/chat/completions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            return (200, Data(#"{"choices":[{"message":{"content":"<think>private reasoning</think>今天天气很好。"},"finish_reason":"stop"}]}"#.utf8))
        }
        let result = try await client().translate("今日はいい天気です。", source: "ja-JP", target: "zh-CN", configuration: config())
        #expect(result == "今天天气很好。")
    }

    @Test func rejectsHTTPFailureMalformedEmptyAndTruncatedOutput() async {
        for (status, body) in [
            (401, "credential failure"), (500, "server failure"), (200, "not json"),
            (200, #"{"choices":[{"message":{"content":""},"finish_reason":"stop"}]}"#),
            (200, #"{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}"#),
            (200, #"{"choices":[{"message":{"content":"<think>unfinished"}}]}"#)
        ] {
            LocalTranslationMockProtocol.handler = { _ in (status, Data(body.utf8)) }
            await #expect(throws: LocalTranslationError.self) {
                try await client().translate("test", source: "ja-JP", target: "zh-CN", configuration: config())
            }
        }
    }

    @Test func rejectsMissingModelBeforeSendingRequest() async {
        var config = config(); config.modelID = "  "
        LocalTranslationMockProtocol.handler = { _ in Issue.record("Request must not be sent"); return (200, Data()) }
        await #expect(throws: LocalTranslationError.self) {
            try await client().translate("test", source: "ja-JP", target: "zh-CN", configuration: config)
        }
    }

    @Test func unpunctuatedJapaneseIsSplitWithoutLosingCharacters() {
        let text = String(repeating: "日本語の長い字幕", count: 70)
        let chunks = LocalTranslationService.captionChunks(text)
        #expect(chunks.count > 1)
        #expect(chunks.allSatisfy { $0.count <= 180 })
        #expect(chunks.joined() == text)
    }

    @Test func nativeQwenResponseExcludesReasoning() async throws {
        var config = config(); config.modelID = "qwen/local-test"
        LocalTranslationMockProtocol.handler = { request in
            #expect(request.url?.path == "/api/v1/chat")
            return (200, Data(#"{"output":[{"type":"reasoning","content":"private"},{"type":"message","content":"完整译文"}],"stats":{"total_output_tokens":8}}"#.utf8))
        }
        let result = try await client().translate("日文", source: "ja-JP", target: "zh-CN", configuration: config)
        #expect(result == "完整译文")
    }

    @Test func detailedModelLoadingFailureRetainsCauseAndRedactsCredential() async {
        var config = config(); config.modelID = "qwen/local-test"
        LocalTranslationMockProtocol.handler = { _ in
            (400, Data(#"{"error":{"message":"Failed to load model: context length below minimum; token local-secret"}}"#.utf8))
        }
        do {
            _ = try await client().translate("日文", source: "ja-JP", target: "zh-CN", configuration: config, apiKey: "local-secret")
            Issue.record("Expected model loading failure")
        } catch let error as LocalTranslationError {
            #expect(error.httpStatus == 400)
            #expect(error.localizedDescription.contains("context length"))
            #expect(!error.localizedDescription.contains("local-secret"))
        } catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func configurationPersistsWithoutCredentials() throws {
        let config = config()
        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(LocalTranslationConfiguration.self, from: data) == config)
        #expect(!String(decoding: data, as: UTF8.self).contains("apiKey"))
    }
}
