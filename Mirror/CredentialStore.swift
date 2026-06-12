import Foundation
import AppKit
import Security

class CredentialStore {
    static let shared = CredentialStore()

    private let serviceName = "com.mirror.app"

    // MARK: - API Keys

    func saveAPIKey(_ key: String, provider: String) {
        let account = "api-key-\(provider)"
        saveToKeychain(service: serviceName, account: account, value: key)
    }

    func getAPIKey(provider: String) -> String? {
        let account = "api-key-\(provider)"
        return readFromKeychain(service: serviceName, account: account)
    }

    func deleteAPIKey(provider: String) {
        let account = "api-key-\(provider)"
        deleteFromKeychain(service: serviceName, account: account)
    }

    // MARK: - Generic Key/Value (for OAuth tokens)

    func save(key: String, value: String) {
        saveToKeychain(service: serviceName, account: key, value: value)
    }

    func get(key: String) -> String? {
        return readFromKeychain(service: serviceName, account: key)
    }

    func delete(key: String) {
        deleteFromKeychain(service: serviceName, account: key)
    }

    // MARK: - OAuth Tokens

    func saveOAuthToken(service: String, token: String) {
        let account = "oauth-\(service)"
        saveToKeychain(service: serviceName, account: account, value: token)
    }

    func getOAuthToken(service: String) -> String? {
        let account = "oauth-\(service)"
        return readFromKeychain(service: serviceName, account: account)
    }

    func deleteOAuthToken(service: String) {
        let account = "oauth-\(service)"
        deleteFromKeychain(service: serviceName, account: account)
    }

    func hasOAuthToken(service: String) -> Bool {
        return getOAuthToken(service: service) != nil
    }

    // MARK: - OAuth Flow (V1 — opens browser for user to manually connect)

    func startOAuthFlow(service: String, completion: @escaping (Bool) -> Void) {
        switch service {
        case "gmail":
            NSWorkspace.shared.open(URL(string: "https://myaccount.google.com/connections")!)
        case "google_sheets":
            NSWorkspace.shared.open(URL(string: "https://myaccount.google.com/connections")!)
        case "linkedin":
            NSWorkspace.shared.open(URL(string: "https://www.linkedin.com/psettings/third-party-applications")!)
        case "notion":
            NSWorkspace.shared.open(URL(string: "https://www.notion.so/my-integrations")!)
        case "slack":
            NSWorkspace.shared.open(URL(string: "https://api.slack.com/apps")!)
        default:
            break
        }
        // V1: Manual OAuth — user copies token and pastes into settings
        // V2: Full OAuth PKCE flow
        completion(true)
    }

    // MARK: - Keychain Primitives

    private func saveToKeychain(service: String, account: String, value: String) {
        let keyData = value.data(using: .utf8)!

        // Delete existing item first
        deleteFromKeychain(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("Keychain save failed: \(status)")
        }
    }

    private func readFromKeychain(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteFromKeychain(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
