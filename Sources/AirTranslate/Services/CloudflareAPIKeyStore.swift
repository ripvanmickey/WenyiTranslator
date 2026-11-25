import Foundation
import Security

enum CloudflareAPIKeyStore {
    private static let service = "AirTranslate.Cloudflare"
    private static let account = "CLOUDFLARE_API_TOKEN"
    private static let cache = APIKeyReadCache()

    static func hasAPIKey() -> Bool {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(presenceQuery() as CFDictionary, &item)
        return status == errSecSuccess
    }

    static func readAPIKey(retryAfterFailure: Bool = false) throws -> String? {
        try cache.read(retryAfterFailure: retryAfterFailure, using: readFromKeychain)
    }

    private static func readFromKeychain() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CloudflareAPIKeyStoreError.keychainStatus(status)
        }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw CloudflareAPIKeyStoreError.invalidStoredKey
        }
        return key
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedKey.contains(where: { $0.isWhitespace || $0.isNewline }) else { throw CloudflareAPIKeyStoreError.emptyKey }
        guard let data = trimmedKey.data(using: .utf8) else {
            throw CloudflareAPIKeyStoreError.invalidStoredKey
        }
        try cache.replace {
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            let update = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
            if update == errSecSuccess { return trimmedKey }
            guard update == errSecItemNotFound else {
                throw CloudflareAPIKeyStoreError.keychainStatus(update)
            }
            var query = baseQuery()
            query.merge(attributes) { _, new in new }
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw CloudflareAPIKeyStoreError.keychainStatus(status) }
            return trimmedKey
        }
    }

    static func deleteAPIKey() throws {
        try cache.replace {
            let status = SecItemDelete(baseQuery() as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CloudflareAPIKeyStoreError.keychainStatus(status)
            }
            return nil
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func presenceQuery() -> [String: Any] {
        var query = baseQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        return query
    }
}

enum CloudflareAPIKeyStoreError: LocalizedError {
    case emptyKey
    case invalidStoredKey
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            CloudflareTranslationError.missingKey.localizedDescription
        case .invalidStoredKey:
            CloudflareTranslationError.missingKey.localizedDescription
        case let .keychainStatus(status):
            AppText.ui("Cloudflare 密钥存取失败（\(status)）。", "Cloudflare key storage failed (\(status)).", "Cloudflare キーの保存・読込に失敗しました（\(status)）。")
        }
    }
}
