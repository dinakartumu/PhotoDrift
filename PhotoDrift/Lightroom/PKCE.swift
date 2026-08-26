import CryptoKit
import Foundation

nonisolated enum OAuthRandom {
    /// Cryptographically random, URL-safe string derived from `byteCount` random bytes.
    static func urlSafeString(byteCount: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        if SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes) != errSecSuccess {
            // SecRandomCopyBytes only fails if the system entropy source is unavailable.
            // Continuing with predictable bytes would silently weaken the exchange.
            fatalError("Unable to read cryptographically secure random bytes")
        }
        return Data(bytes).base64URLEncodedString()
    }
}

/// RFC 7636 Proof Key for Code Exchange parameters.
///
/// A fresh verifier must be generated for every authorization request. A fixed one —
/// especially one committed to a public repository or shipped inside a binary — defeats
/// PKCE completely, because anyone who intercepts an authorization code can then redeem
/// it for tokens.
nonisolated struct PKCE: Sendable {
    let verifier: String

    init(verifier: String) {
        self.verifier = verifier
    }

    /// 32 random bytes, base64url-encoded to 43 characters — within RFC 7636's 43...128 bound
    /// and drawn entirely from the unreserved character set.
    static func generate() -> PKCE {
        PKCE(verifier: OAuthRandom.urlSafeString(byteCount: 32))
    }

    /// BASE64URL(SHA256(ASCII(verifier))), sent as `code_challenge` with method S256.
    var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

nonisolated extension Data {
    /// base64url per RFC 4648 section 5: no padding, `-` and `_` for `+` and `/`.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
