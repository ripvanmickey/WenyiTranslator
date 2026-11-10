import Foundation
final class TitleMock: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var calls = 0
    nonisolated(unsafe) static var fallback = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        let data = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open(); defer { stream.close() }; var data = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }; return data
        }!
        let body = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let native = request.url!.path == "/api/v1/chat"
        precondition(request.url!.host == "localhost")
        precondition(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
        precondition(body["stream"] as? Bool == false)
        if native {
            precondition(body["max_output_tokens"] as? Int == 128)
            precondition(body["reasoning"] as? String == "off" && body["store"] as? Bool == false)
            precondition((body["input"] as! String).count < 2100)
            precondition((body["system_prompt"] as! String).contains("title"))
        } else {
            precondition(body["max_tokens"] as? Int == 128)
        }
        let status = Self.fallback && native ? 404 : 200
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        let response: [String: Any]
        if status == 404 { response = ["error": ["message": "route unsupported"]] }
        else if native { response = ["output": [["type": "message", "content": "“音乐创作与歌手成长”"]]] }
        else { response = ["choices": [["message": ["content": "音乐创作与歌手成长"], "finish_reason": "stop"]]] }
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: response))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct Checks {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral;config.protocolClasses = [TitleMock.self]
        let service = LocalTranslationService(session: URLSession(configuration: config))
        var model = LocalTranslationConfiguration();model.modelID = "qwen/test"
        let text = String(repeating: "日语访谈内容", count: 2000)
        let title = try await service.transcriptTitle(text, configuration: model, apiKey: "test-only")
        precondition(title == "音乐创作与歌手成长" && TitleMock.calls == 1)
        TitleMock.fallback = true
        let compatible = try await service.transcriptTitle(text, configuration: model, apiKey: "test-only")
        precondition(compatible == title && TitleMock.calls == 3)
        model.baseURL = "https://example.invalid/v1"
        do { _ = try await service.transcriptTitle(text, configuration: model, apiKey: "test-only");preconditionFailure("Remote URL must be rejected") } catch LocalTranslationError.invalidURL {}
        precondition(TitleMock.calls == 3)
        print("PASS title generation request, bounded transcript excerpts, thinking off, quote cleanup, legacy endpoint fallback and local-only destination")
    }
}
