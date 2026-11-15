import Foundation

private final class ReviewProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        precondition(request.url?.path == "/api/v1/chat")
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        let answer = #"{"segment":0,"original":"機会","replacement":"機械","evidence":"機械の修理の話です","translation":"我把机器送去修了。"}"#
        let body = try! JSONSerialization.data(withJSONObject: ["output": [["type": "message", "content": answer]]])
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@main struct Checks {
    static func main() async throws {
        let sources = ["機会を修理に出しました。", "機械の修理の話です。"]
        let settings = URLSessionConfiguration.ephemeral
        settings.protocolClasses = [ReviewProtocol.self]
        let service = LocalTranslationService(session: URLSession(configuration: settings))
        let config = LocalTranslationConfiguration(enabled: true, modelID: "qwen/test")
        let result = try await service.reviewCaptionContext(sources, source: "ja-JP", target: "zh-Hans",
                                                            configuration: config, apiKey: nil)
        precondition(result?.index == 0 && result?.source == "機械を修理に出しました。")
        precondition(result?.translation == "我把机器送去修了。")

        func checked(_ index: Int, _ old: String, _ new: String, _ quote: String, sources: [String]) -> Bool {
            CaptionContextCorrection(segment: index, original: old, replacement: new,
                                     evidence: quote, translation: "我把机器送去修了。").validated(in: sources) != nil
        }
        precondition(!checked(1, "機会", "機械", "機械の修理の話です", sources: sources))
        precondition(!checked(0, "機会", "機械", "機械の購入の話です", sources: sources))
        precondition(!checked(0, "機会", "機械", "機械の修理の話です", sources: ["機会か機会", sources[1]]))
        precondition(!checked(0, "2", "3", "3台の機械", sources: ["2台の機会", "3台の機械"]))
        precondition(!checked(0, "機会", "機械", "機械の修理の話です", sources: ["機会を2台", sources[1]]))
        precondition((try! JSONDecoder().decode(CaptionContextCorrection.self, from: Data("{}".utf8))).validated(in: sources) == nil)

        var history = FloatingCaptionHistory()
        let old = FloatingCaptionIdentity.line(UUID())
        let new = FloatingCaptionIdentity.line(UUID())
        let start = Date()
        history.presentSource(sources[0], identity: old, keepsHistory: true, now: start)
        history.presentSource(sources[1], identity: new, keepsHistory: true, now: start)
        history.correctPrevious(identity: old, source: result!.source, translation: result!.translation, now: start.addingTimeInterval(2))
        precondition(history.source?.text == sources[1] && history.previousSource?.caption.text == result?.source)
        precondition(history.previousSource?.retiredAt == start)
        history.correctPrevious(identity: old, source: result!.source, translation: result!.translation, now: start.addingTimeInterval(9))
        precondition(history.previousSource == nil)
        print("PASS explicit later evidence, atomic bilingual edit, rejection of unsafe replacements, floating history expiry")
    }
}
