import Foundation

/// Serialize credential access, including failures, so concurrent caption requests
/// cannot repeatedly open Keychain authorization dialogs. Values live only in memory.
final class APIKeyReadCache: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<String?, Error>?

    func read(retryAfterFailure: Bool = false, using load: () throws -> String?) throws -> String? {
        try lock.withLock {
            if retryAfterFailure, case .failure = result { result = nil }
            if let result { return try result.get() }
            let loaded = Result(catching: load)
            result = loaded
            return try loaded.get()
        }
    }

    func replace(using update: () throws -> String?) throws {
        try lock.withLock {
            // A failed save must retain the previously loaded credential.
            let updated = try update()
            result = .success(updated)
        }
    }
}
