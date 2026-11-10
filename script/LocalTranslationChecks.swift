import Foundation

final class MockProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (code, body) = try Self.handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code,
                httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
func check(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
@main struct Checks {
    static func main() async throws {
        var config = LocalTranslationConfiguration(enabled: true, baseURL: "http://localhost:1235/v1", modelID: "local/test")
        for address in ["http://localhost:1235/v1", "http://127.0.0.1:1235/v1/", "http://[::1]:1235/v1"] {
            var candidate = config; candidate.baseURL = address; _ = try candidate.validatedBaseURL()
        }
        for address in ["https://example.com/v1", "http://localhost.evil.test/v1", "file:///v1", "http://localhost/v1?key=secret", "http://user:pass@localhost/v1", "http://localhost/v1/chat/completions"] {
            var candidate = config; candidate.baseURL = address
            do { _ = try candidate.validatedBaseURL(); fatalError("Accepted remote/invalid address") }
            catch is LocalTranslationError {}
        }
        print("PASS local address validation (9 cases)")
        let data = try JSONEncoder().encode(config)
        check(try JSONDecoder().decode(LocalTranslationConfiguration.self, from: data) == config, "Persistence")
        print("PASS configuration round trip")
        let network = URLSessionConfiguration.ephemeral; network.protocolClasses = [MockProtocol.self]
        let client = LocalTranslationService(session: URLSession(configuration: network))
        MockProtocol.handler = { request in
            check(request.url?.absoluteString == "http://localhost:1235/v1/models", "models endpoint")
            check(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret", "auth")
            return (200, #"{"data":[{"id":"qwen/b"},{"id":"qwen/a"},{"id":"qwen/b"}]}"#)
        }
        check(try await client.models(configuration: config, apiKey: "secret") == ["qwen/a", "qwen/b"], "model IDs")
        print("PASS model discovery and optional authentication")
        MockProtocol.handler = { request in
            check(request.url?.path == "/v1/chat/completions", "translation endpoint")
            check(request.httpMethod == "POST", "POST")
            check(request.value(forHTTPHeaderField: "Authorization") == nil, "unexpected auth")
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count))
                }
            }
            let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            check(json["model"] as? String == "local/test", "model request")
            check(json["stream"] as? Bool == false, "stream option")
            let messages = json["messages"] as! [[String: String]]
            check(messages.last?["content"] == "今日はいい天気です。\n/no_think", "source content")
            check(messages.first!["content"]!.contains("ja-JP to zh-CN"), "translation direction")
            return (200, #"{"choices":[{"message":{"content":"<think>reasoning</think>今天天气很好。"},"finish_reason":"stop"}]}"#)
        }
        check(try await client.translate("今日はいい天気です。", source: "ja-JP", target: "zh-CN", configuration: config) == "今天天气很好。", "translation")
        print("PASS request model, direction, source text and reasoning filtering")
        for (status, body) in [(401, "secret error"), (500, "error"), (200, "not json"),
            (200, #"{"choices":[{"message":{"content":""}}]}"#),
            (200, #"{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}"#),
            (200, #"{"choices":[{"message":{"content":"<think>unfinished"}}]}"#)] {
            MockProtocol.handler = { _ in (status, body) }
            do { _ = try await client.translate("x", source: "ja-JP", target: "zh-CN", configuration: config); fatalError("Accepted invalid response") }
            catch is LocalTranslationError {}
        }
        print("PASS HTTP, malformed, empty, truncated and unfinished reasoning errors (6 cases)")
        config.modelID = "qwen/test"
        var nativeCalls = 0
        MockProtocol.handler = { request in
            check(request.url?.path == "/api/v1/chat", "native endpoint")
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count))
                }
            }
            let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            check(json["context_length"] as? Int == 8192, "explicit caption context length")
            check(json["reasoning"] as? String == "off", "explicit reasoning off")
            check(json["store"] as? Bool == false, "no stored chat")
            check((json["integrations"] as? [String])?.isEmpty == true, "no tools")
            check(json["max_output_tokens"] as? Int == 4096, "output budget")
            check((json["input"] as! String).count <= 180, "hard source chunk limit")
            nativeCalls += 1
            return (200, #"{"output":[{"type":"reasoning","content":"must not display"},{"type":"message","content":"完整译文"}],"stats":{"total_output_tokens":12}}"#)
        }
        let unpunctuated = String(repeating: "日", count: 421)
        let chunks = LocalTranslationService.captionChunks(unpunctuated)
        check(chunks.joined() == unpunctuated && chunks.allSatisfy { $0.count <= 180 }, "lossless Japanese chunks")
        let longResult = try await client.translate(unpunctuated, source: "ja-JP", target: "zh-CN", configuration: config)
        check(nativeCalls == 3 && longResult == "完整译文\n完整译文\n完整译文", "long native translation")
        print("PASS native reasoning off, no storage/tools, bounded Japanese chunks and reasoning exclusion")
        var fallbackCalls = 0
        MockProtocol.handler = { request in
            fallbackCalls += 1
            if request.url?.path == "/api/v1/chat" { return (404, "unsupported route") }
            check(request.url?.path == "/v1/chat/completions", "compatibility fallback")
            return (200, #"{"choices":[{"message":{"content":"兼容译文"},"finish_reason":"stop"}]}"#)
        }
        check(try await client.translate("短句", source: "ja-JP", target: "zh-CN", configuration: config) == "兼容译文", "native 404 fallback")
        check(fallbackCalls == 2, "one fallback only")
        print("PASS explicit route-unavailable compatibility fallback")
        var retryCalls = 0
        MockProtocol.handler = { _ in
            retryCalls += 1
            if retryCalls == 1 { return (200, #"{"output":[],"stats":{"total_output_tokens":4096}}"#) }
            return (200, #"{"output":[{"type":"message","content":"短段译文"}],"stats":{"total_output_tokens":9}}"#)
        }
        let recovered = try await client.translate(String(repeating: "日", count: 180), source: "ja-JP", target: "zh-CN", configuration: config)
        check(retryCalls == 3 && recovered == "短段译文\n短段译文", "truncation split retry")
        print("PASS truncation recovery without displaying incomplete output")
        MockProtocol.handler = { _ in (400, #"{"error":{"message":"Failed to load model: context length below minimum; token secret"}}"#) }
        do {
            _ = try await client.translate("短句", source: "ja-JP", target: "zh-CN", configuration: config, apiKey: "secret")
            fatalError("Detailed error ignored")
        } catch let error as LocalTranslationError {
            check(error.httpStatus == 400, "detailed status")
            check(error.localizedDescription.contains("context length"), "preserve actionable load error")
            check(!error.localizedDescription.contains("secret"), "redact local key")
        }
        print("PASS detailed model-loading errors and credential redaction")
        var deniedCalls = 0
        MockProtocol.handler = { _ in deniedCalls += 1; return (400, "reasoning off unsupported") }
        do { _ = try await client.translate("短句", source: "ja-JP", target: "zh-CN", configuration: config); fatalError("400 accepted") }
        catch is LocalTranslationError {}
        check(deniedCalls == 1, "must not silently reenable reasoning after 400")
        print("PASS rejected native settings do not silently fall back")
        config.modelID = " "
        MockProtocol.handler = { _ in fatalError("Must not send request without model") }
        do { _ = try await client.translate("x", source: "ja-JP", target: "zh-CN", configuration: config); fatalError("Missing model accepted") }
        catch is LocalTranslationError {}
        print("PASS model validation before sending")
        config.modelID = "local/test"
        let cancellationConfiguration = config
        let cancelled = Task { () throws -> [String] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.models(configuration: cancellationConfiguration)
        }
        do { _ = try await cancelled.value; fatalError("Cancellation ignored") } catch is CancellationError {}
        print("PASS cancellation before sending")
        func event(_ json: String) -> String { "data: " + json + "\n\n" }
        let start = event(#"{"type":"chat.start"}"#)
        let reasoning = event(#"{"type":"reasoning.delta","content":"never display"}"#)
        let first = event(#"{"type":"message.delta","content":"今天"}"#)
        let second = event(#"{"type":"message.delta","content":"天气好。"}"#)
        let end = event(#"{"type":"chat.end","result":{"output":[{"type":"message","content":"今天天气好。"}],"stats":{"total_output_tokens":8}}}"#)
        var parser = LocalTranslationStreamParser(native: true)
        var firstPreview: String?
        for line in (start + reasoning + first).components(separatedBy: "\n") {
            if let preview = try parser.receive(line), !preview.isEmpty { firstPreview = preview }
        }
        check(firstPreview == "今天" && !parser.finished, "preview must arrive before completion")
        for line in (second + end).components(separatedBy: "\n") { _ = try parser.receive(line) }
        check(parser.finished && parser.text == "今天天气好。", "native authoritative final")
        print("PASS preview before end and exclusion of reasoning events")
        config.modelID = "qwen/test"
        MockProtocol.handler = { _ in (200, start + reasoning + first + second + end) }
        var previews: [String] = []
        let streamed = try await client.translate("日文", source: "ja-JP", target: "zh-CN", configuration: config,
            progress: { previews.append($0) })
        check(streamed == "今天天气好。" && previews.first == "今天" && previews.last == streamed, "native AsyncBytes transport")
        print("PASS real AsyncBytes SSE transport delivers first delta and final result")
        MockProtocol.handler = { _ in (200, first) }
        do {
            _ = try await client.translate("日文", source: "ja-JP", target: "zh-CN", configuration: config, progress: { _ in })
            fatalError("Premature EOF accepted")
        } catch is LocalTranslationError {}
        print("PASS interrupted stream is not marked complete")
        var compatibility = LocalTranslationStreamParser(native: false)
        let splitThinking = [#"{"choices":[{"delta":{"content":"<thi"}}]}"#,
            #"{"choices":[{"delta":{"content":"nk>hidden"}}]}"#,
            #"{"choices":[{"delta":{"content":"</think>中文"}}]}"#,
            #"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#]
        var visible: [String] = []
        for json in splitThinking {
            for line in event(json).components(separatedBy: "\n") {
                if let value = try compatibility.receive(line) { visible.append(value) }
            }
        }
        _ = try compatibility.receive("data: [DONE]"); _ = try compatibility.receive("")
        check(compatibility.finished && !visible.contains(where: { $0.contains("hidden") || $0.contains("<thi") }), "split reasoning tag filtering")
        check(visible.contains("中文"), "compatibility content")
        var truncated = LocalTranslationStreamParser(native: false)
        do {
            for line in event(#"{"choices":[{"delta":{"content":"partial"},"finish_reason":"length"}]}"#).components(separatedBy: "\n") { _ = try truncated.receive(line) }
            fatalError("Truncated stream accepted")
        } catch LocalTranslationError.truncated {}
        print("PASS compatibility SSE, split reasoning tags, and truncated-output rejection")
        var incrementalCalls = 0
        var sawContext = false
        MockProtocol.handler = { request in
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 8192)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; body.append(contentsOf: buffer.prefix(count))
                }
            }
            let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
            var input = json["input"] as! String
            if let data = input.data(using: .utf8),
               let contextual = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                check(contextual["context"]!.count <= 160, "bounded context")
                sawContext = true; input = contextual["text"]!
            }
            incrementalCalls += 1
            let content = "T:" + input
            let delta = String(decoding: try JSONSerialization.data(withJSONObject: ["type": "message.delta", "content": content]), as: UTF8.self)
            let result = String(decoding: try JSONSerialization.data(withJSONObject: ["type": "chat.end", "result": ["output": [["type": "message", "content": content]], "stats": ["total_output_tokens": 20]]]), as: UTF8.self)
            return (200, event(delta) + event(result))
        }
        let incremental = IncrementalLocalTranslator(client: client)
        let firstInput = "The first sentence is complete. Another"
        let nextInput = "The first sentence is complete. Another sentence is now complete."
        _ = try await incremental.translate(firstInput, identity: "utterance", source: "en-US", target: "zh-CN", configuration: config, apiKey: nil, progress: { _ in })
        let firstCalls = incrementalCalls
        let revised = try await incremental.translate(nextInput, identity: "utterance", source: "en-US", target: "zh-CN", configuration: config, apiKey: nil, progress: { _ in })
        check(incrementalCalls == firstCalls + 1, "stable first sentence must not be translated again")
        check(sawContext && revised.contains("Another sentence is now complete."), "context and new tail")
        let beforeDuplicate = incrementalCalls
        _ = try await incremental.translate(nextInput, identity: "utterance", source: "en-US", target: "zh-CN", configuration: config, apiKey: nil, progress: { _ in })
        check(incrementalCalls == beforeDuplicate, "identical final must reuse all chunks")
        let corrected = try await incremental.translate("A correction changes the opening. Another sentence is now complete.", identity: "utterance", source: "en-US", target: "zh-CN", configuration: config, apiKey: nil, progress: { _ in })
        check(!corrected.contains("The first sentence"), "corrected source must invalidate the translated suffix")
        let raw = "日本語の文章です。前の文章を残して、新しい部分だけを翻訳します。"
        let plan = IncrementalCaptionPlan(text: raw, previous: [])
        check(plan.blocks.joined() == raw, "incremental plan must not lose source characters")
        let timeline = AudioInputTimeline()
        timeline.append(duration: 0.1, arrival: 10)
        timeline.append(duration: 0.1, arrival: 10.1)
        check(abs(timeline.uptime(at: 0.15)! - 10.05) < 0.001, "audio frame time mapping")
        timeline.append(duration: 0.1, arrival: 20)
        check(abs(timeline.uptime(at: 0.3)! - 20) < 0.001, "pause gap must not corrupt audio timing")
        timeline.reset(); check(timeline.uptime(at: 0.1) == nil, "session reset")
        print("PASS incremental prefix reuse, duplicate final, source correction, bounded context, lossless Japanese plan and frame timing")
        print("ALL LOCAL CLIENT CHECKS PASSED")
    }
}
