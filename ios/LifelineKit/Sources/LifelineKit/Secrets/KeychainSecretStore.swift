import Foundation
import Security

/// Generic-password Keychain items, readable after first unlock, never synced off the device.
/// Exercised on the device checklist, not in `swift test`: the macOS test host may prompt.
public struct KeychainSecretStore: SecretStore {
    public enum Error: Swift.Error, Equatable {
        case status(OSStatus)
    }

    private let service: String

    public init(service: String = "com.lifeline.secrets") { self.service = service }

    public func read(_ key: SecretKey) throws -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw Error.status(status)
        }
    }

    public func write(_ value: String, for key: SecretKey) throws {
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery(key)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw Error.status(addStatus) }
        } else if status != errSecSuccess {
            throw Error.status(status)
        }
    }

    public func delete(_ key: SecretKey) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Error.status(status) }
    }

    private func baseQuery(_ key: SecretKey) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key.rawValue]
    }
}
