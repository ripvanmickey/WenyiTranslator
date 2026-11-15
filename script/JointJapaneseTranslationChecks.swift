import Foundation

final class Mock: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var calls = 0
    nonisolated(unsafe) static var raw = "今天晴天。明天呢？\n[WENYI_JA]今日は晴れています。明日はどうでしょうか？"
    nonisolated(unsafe) static var retry: String?
    nonisolated(unsafe) static var streamResults: [(text: String, finish: String?, done: Bool)] = []
    nonisolated(unsafe) static var checkRequest: (([String: Any]) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.calls += 1
        let data = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open(); defer { stream.close() }; var data = Data(); var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let count = stream.read(&bytes, maxLength: bytes.count); if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count)) }; return data
        }!
        let body = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        Self.checkRequest?(body)
        if body["messages"] != nil {
            if request.url?.host == "index-translate.bilibili.com" {
                precondition(request.url?.absoluteString == LocalTranslationConfiguration.indexBaseURL + "/chat/completions")
                precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
                precondition(body["model"] as? String == LocalTranslationConfiguration.indexModelID)
            }
            let streaming = body["stream"] as? Bool == true
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if streaming {
                let result = Self.streamResults.isEmpty ? (Self.raw, "stop", true) : Self.streamResults.removeFirst()
                var choice: [String: Any] = ["delta": ["content": result.0]]
                if let finish = result.1 { choice["finish_reason"] = finish }
                let payload = ["choices": [choice]]
                let json = String(decoding: try! JSONSerialization.data(withJSONObject: payload), as: UTF8.self)
                let terminalEvent = result.2 ? "data: [DONE]\n\n" : ""
                client?.urlProtocol(self, didLoad: Data("data: \(json)\n\n\(terminalEvent)".utf8))
            } else {
                let payload = ["choices": [["message": ["content": Self.raw], "finish_reason": "stop"]]]
                client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload))
            }
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let usesFooter = (body["system_prompt"] as? String)?.contains("[WENYI_JA]") == true
        let output = usesFooter ? Self.raw : Self.retry!
        precondition(body["reasoning"] as? String == "off")
        let streaming = body["stream"] as? Bool == true
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json"])!, cacheStoragePolicy: .notAllowed)
        if streaming {
            for character in output {
                let event: [String: Any] = ["type": "message.delta", "content": String(character)]
                let json = String(data: try! JSONSerialization.data(withJSONObject: event), encoding: .utf8)!
                client?.urlProtocol(self, didLoad: Data("data: \(json)\n\n".utf8))
            }
            let event: [String: Any] = ["type": "chat.end", "result": ["output": [["type": "message", "content": output]]]]
            let json = String(data: try! JSONSerialization.data(withJSONObject: event), encoding: .utf8)!
            client?.urlProtocol(self, didLoad: Data("data: \(json)\n\n".utf8))
        } else {
            client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: ["output": [["type": "message", "content": output]]]))
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

        Mock.raw = "こうちょっと、今天晴天。明天呢？[ こうちょっと"
        Mock.retry = translated
        var mixedProgress: [String] = []
        let repaired = try await client.translate(original, source: "ja-JP", target: "zh-Hans", configuration: model,
            progress: { mixedProgress.append($0) })
        precondition(repaired == translated && Mock.calls == count + 2)
        precondition(mixedProgress.isEmpty, "A stream starting in Japanese must never reach the UI")

        Mock.raw = "今天晴天。明天呢？[ こうちょっと"
        Mock.retry = "今天晴天。ﾊｲ"
        do {
            _ = try await client.translate(original, source: "ja-JP", target: "zh-Hans", configuration: model,
                progress: { mixedProgress.append($0) })
            preconditionFailure("Kana in the retry must fail, even in halfwidth form")
        } catch LocalTranslationError.untranslatedJapanese {}
        precondition(Mock.calls == count + 4 && mixedProgress.allSatisfy { !$0.contains("こう") && !$0.contains("[") })

        Mock.raw = "今日は晴れています。"
        let japanese = try await client.translate(original, source: "ja-JP", target: "ja-JP", configuration: model)
        precondition(japanese == Mock.raw && Mock.calls == count + 5)

        let current = "次の話題に移りましょう。"
        let context = "Before: これまでのお話。"
        Mock.raw = #"进入下一个话题\n这是第二行\r\n还有第三行。"# + "\n[WENYI_JA]" + current
        Mock.checkRequest = { body in
            let prompt = body["system_prompt"] as! String
            let input = body["input"] as! String
            let fields = try! JSONDecoder().decode([String: String].self, from: Data(input.utf8))
            precondition(fields == ["context": context, "text": current])
            precondition(!prompt.contains("Translation naming policy") && !prompt.contains("standard Latin-script labels"))
        }
        var multiline: [String] = []
        let normalized = try await client.translate(current, source: "ja-JP", target: "zh-CN",
            configuration: model, context: context, progress: { multiline.append($0) })
        let expected = "进入下一个话题\n这是第二行\n还有第三行。"
        precondition(normalized == expected && Mock.calls == count + 6)
        precondition(multiline.contains(expected) && multiline.allSatisfy { !$0.contains("\\") })
        model.modelID = "index-translate-9b"
        Mock.checkRequest = { body in
            let messages = body["messages"] as! [[String: String]]
            precondition(messages[1]["content"] == current)
            precondition(messages[0]["content"]?.contains("[WENYI_JA]") == true)
            precondition(messages[0]["content"]?.contains("Translation naming policy") == false)
        }
        let compatible = try await client.translate(current, source: "ja-JP", target: "zh-CN", configuration: model)
        precondition(compatible == expected && Mock.calls == count + 7)

        let firstClause = String(repeating: "この資料を確認します", count: 7) + "、"
        let lastClause = "次の作業を始めます。"
        let whole = firstClause + lastClause
        let start = Mock.calls
        Mock.raw = "完成。"
        Mock.checkRequest = { body in
            precondition(body["stream"] as? Bool == true)
            let messages = body["messages"] as! [[String: String]]
            let expectedInput = [firstClause, lastClause, whole][Mock.calls - start - 1]
            precondition(messages[1]["content"] == expectedInput, "Index should send only the current block or whole final")
        }
        var previews: [String] = []
        _ = try await incremental.translate(whole, identity: "index-confirmation", source: "ja-JP", target: "zh-CN",
            configuration: model, apiKey: nil, progress: { previews.append($0) })
        precondition(Mock.calls == start + 2 && !previews.isEmpty)
        let previewCount = previews.count
        let final = try await incremental.translate(whole, identity: "index-confirmation", source: "ja-JP", target: "zh-CN",
            configuration: model, apiKey: nil, isFinal: true, progress: { previews.append($0) })
        precondition(final == "完成。" && Mock.calls == start + 3 && previews.count == previewCount)

        let legacy = try JSONDecoder().decode(LocalTranslationConfiguration.self,
            from: Data(#"{"enabled":true,"baseURL":"http://localhost:1235/v1","modelID":"index-translate-9b"}"#.utf8))
        precondition(!legacy.usesOnlineIndex && legacy.activeModelID == "index-translate-9b")
        var online = legacy
        online.onlineIndex = true
        online.baseURL = "https://example.invalid/v1"
        Mock.raw = "田中下周去东京。"
        Mock.checkRequest = { body in
            let messages = body["messages"] as! [[String: String]]
            precondition(messages.count == 1 && messages[0]["role"] == "user")
            precondition(messages[0]["content"]?.hasSuffix(current) == true)
            precondition(messages[0]["content"]?.contains(context) == false)
            precondition(messages[0]["content"]?.contains("[WENYI_JA]") == false)
        }
        var onlinePreview = ""
        let onlineResult = try await client.translate(current, source: "ja-JP", target: "zh-CN",
            configuration: online, apiKey: "local-test-key", context: context,
            progress: { onlinePreview = $0 })
        precondition(onlineResult == Mock.raw && onlinePreview == Mock.raw)
        let longCaption = "コンサートでは、客席のみなさんと同じ時間を過ごせます。でも曲を書いているときは、まだ誰にも聴いてもらっていません。曲が少しずつ出来上がってきたときに、この曲はどんな人に届くのかなとか、どこで聴いてほしいかなとか考えることはありますか。それとも、まずは自分が歌いたいものを自由に作るほうですか？"
        precondition((121...180).contains(longCaption.count))
        let longResult = "演唱会上能和观众共享同一段时光。但创作时还没有人听过这首歌。歌曲逐渐成形时，你会想它会传到哪些人耳中、希望他们在哪里听到吗？还是更倾向于自由地创作自己想唱的内容？"
        Mock.checkRequest = { body in
            let messages = body["messages"] as! [[String: String]]
            precondition(messages.count == 1 && messages[0]["content"]?.hasSuffix(longCaption) == true)
        }
        Mock.streamResults = [(longResult, "stop", false)]
        let longStart = Mock.calls
        let longPreview = try await incremental.translate(longCaption, identity: "index-online-long",
            source: "ja-JP", target: "zh-CN", configuration: online, apiKey: nil, progress: { _ in })
        let longFinal = try await incremental.translate(longCaption, identity: "index-online-long",
            source: "ja-JP", target: "zh-CN", configuration: online, apiKey: nil, isFinal: true, progress: { _ in })
        precondition(longPreview == longResult && longFinal == longResult && Mock.calls == longStart + 1)
        let longer = longCaption + longCaption
        let chunks = LocalTranslationService.onlineCaptionChunks(longer)
        precondition(chunks.count == 2 && chunks.joined() == longer && chunks.allSatisfy { $0.count <= 180 })
        let interrupted = "演唱会上能和观众共享同一段时光。"
        Mock.streamResults = [(interrupted, nil, false), (longResult, "stop", true)]
        var recoveryPreviews: [String] = []
        let recovered = try await client.translate(longCaption, source: "ja-JP", target: "zh-CN",
            configuration: online, progress: { recoveryPreviews.append($0) })
        precondition(recovered == longResult && recoveryPreviews == [interrupted])

        Mock.checkRequest = nil
        Mock.streamResults = [(current, "stop", true), ("田中下周去东京。", "stop", true)]
        var echoPreviews: [String] = []
        let corrected = try await client.translate(current, source: "ja-JP", target: "zh-CN",
            configuration: online, progress: { echoPreviews.append($0) })
        precondition(corrected == "田中下周去东京。" && echoPreviews.isEmpty)
        Mock.streamResults = [(current, "stop", true), (current, "stop", true)]
        do {
            _ = try await client.translate(current, source: "ja-JP", target: "zh-CN", configuration: online)
            preconditionFailure("Japanese echo must not be marked complete")
        } catch LocalTranslationError.indexWrongLanguage {}

        let truncatedStart = Mock.calls
        Mock.streamResults = [(interrupted, "length", true), (longResult, "stop", true)]
        Mock.checkRequest = { body in
            let budget = body["max_tokens"] as! Int
            precondition((Mock.calls == truncatedStart + 1) == (budget < 1_024))
        }
        let afterTruncation = try await client.translate(longCaption, source: "ja-JP", target: "zh-CN", configuration: online)
        precondition(afterTruncation == longResult && Mock.calls == truncatedStart + 2)
        print("PASS online long caption uses one request, accepts explicit stop, retries a broken stream or output limit once, and filters Japanese echo")

        online.onlineIndex = nil
        do {
            _ = try online.validatedBaseURL()
            preconditionFailure("Local mode must reject a non-loopback URL")
        } catch LocalTranslationError.invalidURL {}
        print("PASS joint response, one request, streaming marker fragmentation, no footer leak, source validation and incremental cache reuse")
        print("PASS mixed Japanese hidden from progress, one translation-only retry, halfwidth kana rejected and Japanese target preserved")
        print("PASS escaped line breaks in previews and final output; no previous bilingual captions or naming policy")
        print("PASS Index previews omit neighboring source; final replaces the preview using one whole-caption request")
        print("PASS explicit online Index route uses a fixed host, current fragment only, and no local credentials")
    }
}
