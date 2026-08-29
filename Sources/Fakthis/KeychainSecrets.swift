import Foundation
import Security

public struct KeychainSecrets: Secrets, Sendable {
    private let bundleID: String

    public init(bundleID: String) {
        self.bundleID = bundleID
    }

    public func storeJiraToken(_ token: String) async throws {
        try store(account: "jira-token", value: token)
    }

    public func storeModelKey(_ key: String) async throws {
        try store(account: "model-key", value: key)
    }

    public func jiraToken() async throws -> String {
        try read(account: "jira-token")
    }

    public func modelKey() async throws -> String {
        try read(account: "model-key")
    }

    private func store(account: String, value: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: bundleID,
            kSecAttrAccount as String: account,
        ]
        let existing = SecItemCopyMatching(query as CFDictionary, nil)
        if existing == errSecSuccess {
            let status = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData as String: data] as CFDictionary
            )
            guard status == errSecSuccess else { throw SecretAccessFailed() }
            return
        }
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretAccessFailed() }
    }

    private func read(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: bundleID,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
            let value = String(data: data, encoding: .utf8)
        else {
            throw SecretAccessFailed()
        }
        return value
    }
}
