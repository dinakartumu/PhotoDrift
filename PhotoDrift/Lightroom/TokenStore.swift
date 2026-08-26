import Foundation
import Security

/// The Adobe OAuth credential set.
///
/// These previously lived on the SwiftData `AppSettings` model as plain strings, which put a
/// long-lived refresh token into an unencrypted SQLite file inside the app container. They
/// belong in the Keychain.
nonisolated struct AdobeTokens: Codable, Equatable, Sendable {
    var accessToken: String?
    var refreshToken: String?
    var expiry: Date?

    /// Tokens recovered from the pre-Keychain SwiftData fields, or nil if nothing was stored.
    static func legacy(accessToken: String?, refreshToken: String?, expiry: Date?) -> AdobeTokens? {
        guard accessToken != nil || refreshToken != nil else { return nil }
        return AdobeTokens(accessToken: accessToken, refreshToken: refreshToken, expiry: expiry)
    }

    /// A refresh token keeps the session alive indefinitely; without one the access token is
    /// only good until it expires.
    func isSignedIn(now: Date = Date()) -> Bool {
        if refreshToken != nil { return true }
        if accessToken != nil, let expiry { return now < expiry }
        return false
    }
}

nonisolated enum TokenStoreError: Error, LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
            return "Keychain access failed (\(status)): \(message)"
        }
    }
}

/// Stores the Adobe token set as a single JSON blob in one generic-password item, so reads and
/// writes stay atomic across the three related values.
nonisolated struct KeychainTokenStore: Sendable {
    private let service: String
    private let account = "adobe-oauth"

    init(service: String = "com.dinakartumu.PhotoDrift.AdobeTokens") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() throws -> AdobeTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TokenStoreError.keychain(status) }
        guard let data = item as? Data else { return nil }
        return try JSONDecoder().decode(AdobeTokens.self, from: data)
    }

    func save(_ tokens: AdobeTokens) throws {
        let data = try JSONEncoder().encode(tokens)

        // Update in place when the item already exists, so repeated saves never duplicate.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw TokenStoreError.keychain(updateStatus) }

        var insert = baseQuery
        insert[kSecValueData as String] = data
        // Tokens are only needed while the user is using the Mac, and should never sync.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw TokenStoreError.keychain(addStatus) }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychain(status)
        }
    }
}
