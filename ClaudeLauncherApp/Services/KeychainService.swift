import Foundation
import Security

protocol SecretStore {
    func saveSecret(_ value: String, for key: String) throws
    func loadSecret(for key: String) -> String?
    func deleteSecret(for key: String)
}

final class KeychainService: SecretStore {
    private let primaryService = "CClauncherGateway"
    private let legacyService = "ClaudeLauncherGateway"

    func saveSecret(_ value: String, for key: String) throws {
        let data = Data(value.utf8)
        SecItemDelete(query(for: key, service: primaryService) as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: primaryService,
            kSecAttrAccount: key,
            kSecValueData: data
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "KeychainService", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "保存密钥失败。"])
        }
    }

    func loadSecret(for key: String) -> String? {
        loadSecret(for: key, service: primaryService) ?? loadSecret(for: key, service: legacyService)
    }

    func deleteSecret(for key: String) {
        SecItemDelete(query(for: key, service: primaryService) as CFDictionary)
        SecItemDelete(query(for: key, service: legacyService) as CFDictionary)
    }

    private func loadSecret(for key: String, service: String) -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query(for: key, service: service) as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private func query(for key: String, service: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
    }
}
