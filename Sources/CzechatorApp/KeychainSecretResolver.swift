import CzechatorCore
import Foundation
import Security

/// The only place in the app that touches Security.framework. The core knows
/// nothing about it, which is what keeps the core buildable on Linux.
struct KeychainSecretResolver: SecretResolver {

    private let service = "cz.czechator.app"

    func resolve(_ ref: SecretRef) throws -> String {
        switch ref {
        case .literal(let value):
            return value
        case .environment(let name):
            return try EnvironmentSecretResolver().resolve(.environment(name: name))
        case .keychain(let account):
            return try read(account: account)
        }
    }

    private func read(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
            let data = item as? Data,
            let value = String(data: data, encoding: .utf8),
            !value.isEmpty
        else {
            throw SecretError.notFound(account)
        }
        return value
    }

    func store(_ value: String, account: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        var insert = base
        insert[kSecValueData as String] = Data(value.utf8)
        guard SecItemAdd(insert as CFDictionary, nil) == errSecSuccess else {
            throw SecretError.notFound(account)
        }
    }
}
