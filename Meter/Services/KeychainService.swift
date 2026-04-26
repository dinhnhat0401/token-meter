import Foundation
import Security

public protocol KeychainReading: Sendable {
    /// Returns the OAuth access token stored by the official `claude` CLI.
    func readClaudeOAuthToken() throws -> String
}

public enum KeychainError: Error, Equatable {
    case itemNotFound
    case unexpectedFormat
    case unhandled(OSStatus)
}

public struct KeychainService: KeychainReading {
    private let service: String

    public init(service: String = "Claude Code-credentials") {
        self.service = service
    }

    public func readClaudeOAuthToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw KeychainError.unexpectedFormat
            }
            return try Self.parseToken(from: data)
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unhandled(status)
        }
    }

    /// Parses the JSON payload stored in the Keychain item.
    /// `internal` so unit tests can exercise it without the real Keychain.
    static func parseToken(from data: Data) throws -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let inner = object["claudeAiOauth"] as? [String: Any],
            let token = inner["accessToken"] as? String,
            !token.isEmpty
        else {
            throw KeychainError.unexpectedFormat
        }
        return token
    }
}
