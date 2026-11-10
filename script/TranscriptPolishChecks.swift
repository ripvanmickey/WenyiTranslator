import Foundation
final class PolishMock: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var calls = 0
    nonisolated(unsafe) static var truncated = false
    nonisolated(unsafe) static var summary = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        let data = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open(); defer { stream.close() }; var data = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(contentsOf: bytes.prefix(n)) }; return data
        }!
        let body = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let native = request.url!.path == "/api/v1/chat"
        precondition(request.url!.host == "localhost")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
        precondition(body["stream"] as? Bool == false)
        let input: String
        if native {
            precondition(body["reasoning"] as? String == "off" && body["store"] as? Bool == false)
            input = body["input"] as! String
        } else {
            let messages = body["messages"] as! [[String:String]]
            precondition(messages[0]["content"]!.contains("Do not summarize"))
            input = messages[1]["content"]!.replacingOccurrences(of: "\n/no_think", with: "")
        }
        precondition(input.count <= 900)
        let status = native ? 404 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        let response: [String: Any] = native ? ["error": ["message": "unsupported"]] : ["choices": [["message": ["content": Self.summary ? "概要" : input + "。\n\n"], "finish_reason": Self.truncated ? "length" : "stop"]]]
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: response))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct Checks {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [PolishMock.self]
        let service = LocalTranslationService(session: URLSession(configuration: config))
        var model = LocalTranslationConfiguration(); model.modelID = "qwen/test"
        let text = String(repeating: "今日は音楽について話します", count: 200)
        let chunks = LocalTranslationService.transcriptPolishChunks(text)
        precondition(chunks.count > 1 && chunks.allSatisfy { $0.count <= 900 } && chunks.joined() == text)
        let result = try await service.polishTranscript(text, configuration: model, apiKey: "test-only")
        precondition(result.replacingOccurrences(of: "。", with: "").replacingOccurrences(of: "\n", with: "") == text)
        precondition(PolishMock.calls == chunks.count * 2)
        let empty = try await service.polishTranscript("  ", configuration: model, apiKey: nil)
        precondition(empty == "")
        PolishMock.truncated = true
        do { _ = try await service.polishTranscript("今日は音楽について話します", configuration: model, apiKey: "test-only"); preconditionFailure() } catch LocalTranslationError.truncated {}
        PolishMock.truncated = false; PolishMock.summary = true
        do { _ = try await service.polishTranscript(text, configuration: model, apiKey: "test-only"); preconditionFailure() } catch { }
        model.baseURL = "https://example.invalid/v1"
        do { _ = try await service.polishTranscript(text, configuration: model, apiKey: nil); preconditionFailure() } catch LocalTranslationError.invalidURL {}
        print("PASS bounded Japanese chunks, complete content, local-only endpoint, native fallback, truncation and summary rejection")
    }
}
