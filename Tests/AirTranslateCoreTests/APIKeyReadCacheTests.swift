import Foundation
import Testing
@testable import AirTranslate

struct APIKeyReadCacheTests {
    private enum Failure: Error { case denied }

    @Test
    func concurrentCaptionRequestsAuthorizeOnce() async {
        final class Counter: @unchecked Sendable {
            let lock = NSLock()
            var count = 0
            func load() -> String? { lock.withLock { count += 1; return "test-credential" } }
        }
        let cache = APIKeyReadCache()
        let counter = Counter()
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<100 {
                group.addTask {
                    (try? cache.read(using: counter.load)) == "test-credential"
                }
            }
            for await correct in group { #expect(correct) }
        }
        #expect(counter.count == 1)
    }

    @Test
    func deniedAuthorizationWaitsForExplicitRetry() throws {
        let cache = APIKeyReadCache()
        var count = 0
        for _ in 0..<20 {
            #expect(throws: Failure.self) {
                try cache.read { count += 1; throw Failure.denied }
            }
        }
        #expect(count == 1)
        let recovered = try cache.read(retryAfterFailure: true) {
            count += 1
            return "recovered-test-credential"
        }
        #expect(recovered == "recovered-test-credential")
        #expect(count == 2)
        #expect(try cache.read { Issue.record("A successful retry must be reused"); return nil } == recovered)
    }

    @Test
    func saveDeleteAndFailedReplacementPreserveTheRightCredential() throws {
        let cache = APIKeyReadCache()
        _ = try cache.read { "old-test-credential" }
        #expect(throws: Failure.self) { try cache.replace { throw Failure.denied } }
        #expect(try cache.read { nil } == "old-test-credential")
        try cache.replace { "new-test-credential" }
        #expect(try cache.read { nil } == "new-test-credential")
        try cache.replace { nil }
        #expect(try cache.read { "deleted-test-credential" } == nil)
    }
}
