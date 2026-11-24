import Foundation
import Security

enum OpenAIAPIKeyStore {
    private static let service = "AirTranslate.OpenAI"
    private static let account = "OPENAI_API_KEY"
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
            throw OpenAIAPIKeyStoreError.keychainStatus(status)
        }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw OpenAIAPIKeyStoreError.invalidStoredKey
        }
        return key
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw OpenAIAPIKeyStoreError.emptyKey }
        guard let data = trimmedKey.data(using: .utf8) else {
            throw OpenAIAPIKeyStoreError.invalidStoredKey
        }
        try cache.replace {
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            let update = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
            if update == errSecSuccess { return trimmedKey }
            guard update == errSecItemNotFound else {
                throw OpenAIAPIKeyStoreError.keychainStatus(update)
            }
            var query = baseQuery()
            query.merge(attributes) { _, new in new }
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else { throw OpenAIAPIKeyStoreError.keychainStatus(status) }
            return trimmedKey
        }
    }

    static func deleteAPIKey() throws {
        try cache.replace {
            let status = SecItemDelete(baseQuery() as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw OpenAIAPIKeyStoreError.keychainStatus(status)
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

enum OpenAIAPIKeyStoreError: LocalizedError {
    case emptyKey
    case invalidStoredKey
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            AppText.openAIAPIKeyEmpty
        case .invalidStoredKey:
            AppText.openAIAPIKeyInvalidStoredValue
        case let .keychainStatus(status):
            if status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed {
                AppText.ui(
                    "未能取得 OpenAI 密钥的钥匙串授权。请在设置 → API 密钥 → OpenAI 中查看或重新保存密钥，再开始聆听。",
                    "OpenAI Keychain access was not granted. Show or save the key in Settings → API Keys → OpenAI, then start listening again.",
                    "OpenAI キーのキーチェーン認証を取得できませんでした。「設定 → API キー → OpenAI」でキーを表示または保存してから、聞き取りを再開してください。"
                )
            } else {
                AppText.openAIAPIKeychainFailed(status)
            }
        }
    }
}
