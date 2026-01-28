import Foundation
import Security
import os

/// Service for securely storing and retrieving API keys in the macOS Keychain.
enum KeychainService {
    private static let logger = Logger(subsystem: "com.chrismatix.nuntius", category: "KeychainService")

    /// Saves an API key to the Keychain.
    /// - Parameter apiKey: The API key to store
    /// - Returns: True if saved successfully, false otherwise
    @discardableResult
    static func saveAPIKey(_ apiKey: String) -> Bool {
        guard let data = apiKey.data(using: .utf8) else {
            logger.error("Failed to encode API key as UTF-8")
            return false
        }

        // Delete any existing key first
        deleteAPIKey()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.OpenAI.keychainService,
            kSecAttrAccount as String: "apiKey",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecSuccess {
            logger.info("API key saved to Keychain")
            return true
        } else {
            logger.error("Failed to save API key to Keychain: \(status)")
            return false
        }
    }

    /// Loads the API key from the Keychain.
    /// - Returns: The stored API key, or nil if not found
    static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.OpenAI.keychainService,
            kSecAttrAccount as String: "apiKey",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            if status != errSecItemNotFound {
                logger.warning("Failed to load API key from Keychain: \(status)")
            }
            return nil
        }

        return apiKey
    }

    /// Deletes the API key from the Keychain.
    /// - Returns: True if deleted successfully (or didn't exist), false on error
    @discardableResult
    static func deleteAPIKey() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.OpenAI.keychainService,
            kSecAttrAccount as String: "apiKey"
        ]

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            if status == errSecSuccess {
                logger.info("API key deleted from Keychain")
            }
            return true
        } else {
            logger.error("Failed to delete API key from Keychain: \(status)")
            return false
        }
    }
}
