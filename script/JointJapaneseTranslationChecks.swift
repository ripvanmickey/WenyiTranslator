import Foundation

final class Mock: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var calls = 0
    nonisolated(unsafe) static var raw = "今天晴天。明天呢？\n[WENYI_JA]今日は晴れています。明日はどうでしょうか？"
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        let data = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open(); defer { stream.close() }; var data = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }; return data
        }!
        let body = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition((body["system_prompt"] as? String)?.contains("[WENYI_JA]") == true)
        precondition(body["reasoning"] as? String == "off")
        let streaming = body["stream"] as? Bool == true
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json"])!, cacheStoragePolicy: .notAllowed)
        if streaming {
            for character in Self.raw {
                let event: [String: Any] = ["type": "message.delta", "content": String(character)]
                let json = String(data: try! JSONSerialization.data(withJSONObject: event), encoding: .utf8)!
                client?.urlProtocol(self, didLoad: Data("data: \(json)\n\n".utf8))
            }
            let event: [String: Any] = ["type": "chat.end", "result": ["output": [["type": "message", "content": Self.raw]]]]
            let json = String(data: try! JSONSerialization.data(withJSONObject: event), encoding: .utf8)!
            client?.urlProtocol(self, didLoad: Data("data: \(json)\n\n".utf8))
        } else {
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: ["output": [["type": "message", "content": Self.raw]]]))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@main struct Checks {
    @MainActor static func main() async throws {
        let original = "今日は晴れています明日はどうでしょうか"
        let translated = "今天晴天。明天呢？"
        for count in 1..<JapaneseTranslationEnvelope.marker.count {
            precondition(JapaneseTranslationEnvelope.translation(translated + "\n" + JapaneseTranslationEnvelope.marker.prefix(count)) == translated)
        }
        precondition(JapaneseTranslationEnvelope.source(Mock.raw, original: original) != nil)
        precondition(JapaneseTranslationEnvelope.source("好。\n[WENYI_JA]今日は雨です。", original: original) == nil)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [Mock.self]
        let client = LocalTranslationService(session: URLSession(configuration: config))
        var model = LocalTranslationConfiguration(); model.modelID = "qwen/test"
        let result = try await client.translate(original, source: "ja-JP", target: "zh-Hans", configuration: model)
        precondition(result == translated && Mock.calls == 1, "One request supplies both outputs")
        let restored = await client.punctuatedSource(original, configuration: model)
        precondition(restored == "今日は晴れています。明日はどうでしょうか？")
        let incremental = IncrementalLocalTranslator(client: client)
        var visible: [String] = []; var punctuated = ""
        let completed = try await incremental.translate(original, identity: "test", source: "ja-JP", target: "zh-Hans", configuration: model, apiKey: nil,
            punctuation: { punctuated = $0 }, progress: { visible.append($0) })
        precondition(completed == translated && punctuated == restored)
        precondition(visible.allSatisfy { !$0.contains("[") && !$0.contains("今日は") }, "Footer must never leak to translation")
        let count = Mock.calls
        _ = try await incremental.translate(original, identity: "test", source: "ja-JP", target: "zh-Hans", configuration: model, apiKey: nil,
            punctuation: { punctuated = $0 }, progress: { _ in })
        precondition(Mock.calls == count, "Cached clauses retain punctuation without extra requests")
        print("PASS joint response, one request, streaming marker fragmentation, no footer leak, source validation and incremental cache reuse")
    }
}
