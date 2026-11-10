import Foundation
import Security
import LocalAuthentication

enum LocalTranslationAPIKeyStore {
    private static let service = "AirTranslate.LocalTranslation"
    private static let account = "LOCAL_TRANSLATION_API_KEY"

    static func hasAPIKey() -> Bool {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(presenceQuery() as CFDictionary, &item)
        return status == errSecSuccess
    }

    static func readAPIKey() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw LocalTranslationAPIKeyStoreError.keychainStatus(status)
        }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw LocalTranslationAPIKeyStoreError.invalidStoredKey
        }
        return key
    }

    static func saveAPIKey(_ key: String) throws {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, trimmedKey.utf8.count <= 16_384,
              trimmedKey.utf8.allSatisfy({ $0 >= 0x21 && $0 <= 0x7e }) else {
            throw LocalTranslationAPIKeyStoreError.emptyKey
        }
        guard let data = trimmedKey.data(using: .utf8) else {
            throw LocalTranslationAPIKeyStoreError.invalidStoredKey
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let update = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw LocalTranslationAPIKeyStoreError.keychainStatus(update) }

        var query = baseQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LocalTranslationAPIKeyStoreError.keychainStatus(status)
        }
    }

    static func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LocalTranslationAPIKeyStoreError.keychainStatus(status)
        }
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
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

enum LocalTranslationAPIKeyStoreError: LocalizedError {
    case emptyKey
    case invalidStoredKey
    case keychainStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyKey:
            "请输入有效的本地服务密钥"
        case .invalidStoredKey:
            "请输入有效的本地服务密钥"
        case let .keychainStatus(status):
            "本地翻译 钥匙串操作失败（\(status)）"
        }
    }
}
