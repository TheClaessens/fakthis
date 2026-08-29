import Foundation
import Security
import Testing
import Fakthis

@Test func keychainSecretsStoresTwoItemsKeyedOffTheBundleID() async throws {
    let bundleID = "com.fakthis.tests.\(UUID().uuidString)"
    defer { deleteKeychainItems(service: bundleID) }
    let secrets = KeychainSecrets(bundleID: bundleID)

    try await secrets.storeJiraToken("jira-secret")
    try await secrets.storeModelKey("model-secret")

    #expect(try await secrets.jiraToken() == "jira-secret")
    #expect(try await secrets.modelKey() == "model-secret")

    try await secrets.storeJiraToken("jira-secret-rotated")
    #expect(try await secrets.jiraToken() == "jira-secret-rotated")
    #expect(try await secrets.modelKey() == "model-secret")
}

private func deleteKeychainItems(service: String) {
    SecItemDelete(
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary
    )
}
