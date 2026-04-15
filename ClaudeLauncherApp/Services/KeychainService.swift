import Foundation
import Security

protocol SecretStore {
    func saveSecret(_ value: String, for key: String) throws
    func loadSecret(for key: String) -> String?
    func deleteSecret(for key: String)
}

final class KeychainService: SecretStore {
    func saveSecret(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "ClaudeLauncherGateway",
            kSecAttrAccount: key
        ]

        SecItemDelete(query as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "ClaudeLauncherGateway",
            kSecAttrAccount: key,
            kSecValueData: data
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainService", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "保存密钥失败。"])
        }
    }

    func loadSecret(for key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "ClaudeLauncherGateway",
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    func deleteSecret(for key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "ClaudeLauncherGateway",
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
