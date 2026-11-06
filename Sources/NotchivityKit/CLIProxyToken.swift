import Foundation
import Security

public enum CLIProxyToken {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Notchivity.CLIProxy",
        kSecAttrAccount as String: "usage-limits",
    ]

    public static func load() throws -> String {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(lookup as CFDictionary, &result)
        if status == errSecItemNotFound { return "" }
        guard status == errSecSuccess, let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
            throw UsageError.other("CLI proxy token could not be read from Keychain")
        }
        return token
    }

    public static func save(_ token: String) throws {
        if token.isEmpty {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw UsageError.other("CLI proxy token could not be removed from Keychain")
            }
            return
        }
        let attributes = [kSecValueData as String: Data(token.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw UsageError.other("CLI proxy token could not be saved to Keychain")
        }
    }
}
