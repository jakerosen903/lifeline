import Foundation
import Synchronization

public enum SecretKey: String, Sendable {
    case anthropicAPIKey = "anthropic-api-key"
}

/// Where secrets live. The Keychain on device; memory in tests and UI runs.
public protocol SecretStore: Sendable {
    func read(_ key: SecretKey) throws -> String?
    func write(_ value: String, for key: SecretKey) throws
    func delete(_ key: SecretKey) throws
}

public final class InMemorySecretStore: SecretStore, Sendable {
    private let values = Mutex<[SecretKey: String]>([:])

    public init(_ initial: [SecretKey: String] = [:]) { values.withLock { $0 = initial } }

    public func read(_ key: SecretKey) throws -> String? { values.withLock { $0[key] } }
    public func write(_ value: String, for key: SecretKey) throws { values.withLock { $0[key] = value } }
    public func delete(_ key: SecretKey) throws { values.withLock { $0[key] = nil } }
}

/// A cheap shape check so a pasted key with a stray space or the wrong prefix is caught in
/// Settings, not as a 401 mid-session. It proves nothing about validity.
public enum APIKeyFormat {
    public static let prefix = "sk-ant-"
    public static let minimumLength = 20

    public static func looksValid(_ raw: String) -> Bool {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.hasPrefix(prefix) && key.count >= minimumLength && !key.contains(where: \.isWhitespace)
    }

    public static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
