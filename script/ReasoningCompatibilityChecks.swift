import Foundation
final class ReasoningMock: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var calls = 0
    nonisolated(unsafe) static var rejectsReasoning = false
    nonisolated(unsafe) static var compatible = false
    nonisolated(unsafe) static var unrelated = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var buf = [UInt8](repeating: 0, count: 4096)
            while true { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(contentsOf: buf.prefix(n)) }
        }
        let b = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        let native = request.url!.path == "/api/v1/chat"
        let reasoning = b["reasoning"] != nil || b["reasoning_effort"] != nil || b["chat_template_kwargs"] != nil
        let coder = (b["model"] as! String).contains("coder")
        if coder {
            precondition(!reasoning)
            if let messages = b["messages"] as? [[String: String]] { precondition(!messages.last!["content"]!.contains("/no_think")) }
        }
        let streaming = b["stream"] as? Bool == true
        var status = 200
        var payload: Data
        if native && Self.compatible { status = 404; payload = Data() }
        else if Self.unrelated || (Self.rejectsReasoning && reasoning) {
            status = 400
            payload = try! JSONSerialization.data(withJSONObject: ["error": ["message": Self.unrelated ? "Invalid context length" : "Model does not expose reasoning configuration."]])
        } else if streaming {
            payload = Data((native ? "data: {\"type\":\"message.delta\",\"content\":\"你好。\"}\n\ndata: {\"type\":\"chat.end\",\"result\":{\"output\":[{\"type\":\"message\",\"content\":\"你好。\"}]}}\n\n" : "data: {\"choices\":[{\"delta\":{\"content\":\"你好。\"},\"finish_reason\":null}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n").utf8)
        } else {
            payload = try! JSONSerialization.data(withJSONObject: native ? ["output": [["type": "message", "content": "你好。"]]] : ["choices": [["message": ["content": "你好。"], "finish_reason": "stop"]]])
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct Checks {
    @MainActor static func main() async throws {
        for compatible in [false, true] {
            for streaming in [false, true] {
                for coder in [false, true] {
                    ReasoningMock.calls = 0; ReasoningMock.compatible = compatible
                    ReasoningMock.rejectsReasoning = true; ReasoningMock.unrelated = false
                    let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [ReasoningMock.self]
                    let client = LocalTranslationService(session: URLSession(configuration: c))
                    var model = LocalTranslationConfiguration(); model.modelID = coder ? "qwen3-coder-30b-a3b-instruct-mlx" : "qwen/unknown"
                    var progress: LocalTranslationService.Progress?
                    if streaming { progress = { _ in } }
                    for i in 0..<2 {
                        let result = try await client.translate(i == 0 ? "Hello" : "Hi", source: "en", target: "zh-Hans", configuration: model, progress: progress)
                        precondition(result == "你好。")
                    }
                    let expected = (compatible ? 4 : 2) + (coder ? 0 : 1)
                    precondition(ReasoningMock.calls == expected, "Bounded retry and capability cache")
                }
                ReasoningMock.calls = 0; ReasoningMock.unrelated = true
                let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [ReasoningMock.self]
                let client = LocalTranslationService(session: URLSession(configuration: c))
                var model = LocalTranslationConfiguration(); model.modelID = "qwen/unknown"
                var progress: LocalTranslationService.Progress?
                if streaming { progress = { _ in } }
                do { _ = try await client.translate("Hello", source: "en", target: "zh-Hans", configuration: model, progress: progress); preconditionFailure() }
                catch { precondition((error as? LocalTranslationError)?.httpStatus == 400) }
                precondition(ReasoningMock.calls == (compatible ? 2 : 1), "Other HTTP 400 must not retry")
            }
        }
        print("PASS Coder, capability fallback/cache, native/compatible, streaming/nonstreaming, unrelated 400 propagation")
    }
}
