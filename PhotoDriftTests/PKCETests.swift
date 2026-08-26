import Testing
import Foundation
@testable import PhotoDrift

struct PKCETests {

    // MARK: - Challenge derivation

    @Test func challengeMatchesTheRFC7636TestVector() {
        // RFC 7636 Appendix B.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pkce.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func challengeIsBase64URLWithoutPadding() {
        let challenge = PKCE.generate().challenge
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
        #expect(!challenge.contains("="))
    }

    // MARK: - Verifier generation

    @Test func generatedVerifierIsFreshEveryTime() {
        // The whole point of PKCE: a fixed verifier baked into a shipped binary lets
        // anyone who intercepts an authorization code redeem it.
        let verifiers = Set((0..<50).map { _ in PKCE.generate().verifier })
        #expect(verifiers.count == 50)
    }

    @Test func generatedVerifierMeetsRFC7636LengthBounds() {
        let verifier = PKCE.generate().verifier
        #expect(verifier.count >= 43)
        #expect(verifier.count <= 128)
    }

    @Test func generatedVerifierUsesOnlyUnreservedCharacters() {
        // RFC 7636 section 4.1: ALPHA / DIGIT / "-" / "." / "_" / "~"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        for scalar in PKCE.generate().verifier.unicodeScalars {
            #expect(allowed.contains(scalar), "disallowed character '\(scalar)' in verifier")
        }
    }

    @Test func randomStateIsFreshEveryTime() {
        let states = Set((0..<50).map { _ in OAuthRandom.urlSafeString() })
        #expect(states.count == 50)
    }

    // MARK: - Authorization URL

    @Test func authorizationURLCarriesTheDerivedChallengeNotTheVerifier() throws {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        let url = AdobeAuthManager.authorizationURL(pkce: pkce, state: "state-123")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let value = { (name: String) in items.first { $0.name == name }?.value }

        #expect(value("code_challenge") == pkce.challenge)
        #expect(value("code_challenge_method") == "S256")
        // The verifier must never leave the device until the token exchange.
        #expect(!url.absoluteString.contains(pkce.verifier))
    }

    @Test func authorizationURLCarriesStateForCSRFProtection() throws {
        let url = AdobeAuthManager.authorizationURL(pkce: .generate(), state: "state-abc")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first { $0.name == "state" }?.value == "state-abc")
    }

    @Test func authorizationURLCarriesTheStandardOAuthParameters() throws {
        let url = AdobeAuthManager.authorizationURL(pkce: .generate(), state: "s")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let value = { (name: String) in items.first { $0.name == name }?.value }

        #expect(value("response_type") == "code")
        #expect(value("client_id") == AdobeConfig.clientID)
        #expect(value("redirect_uri") == AdobeConfig.redirectURI)
        #expect(value("scope") == AdobeConfig.scopes)
    }

    // MARK: - Callback validation

    @Test func callbackWithMatchingStateYieldsTheCode() throws {
        let url = URL(string: "app://callback?code=abc123&state=expected")!
        let code = try AdobeAuthManager.authorizationCode(from: url, expectedState: "expected")
        #expect(code == "abc123")
    }

    @Test func callbackWithMismatchedStateIsRejected() {
        let url = URL(string: "app://callback?code=abc123&state=attacker")!
        #expect(throws: AdobeAuthError.stateMismatch) {
            try AdobeAuthManager.authorizationCode(from: url, expectedState: "expected")
        }
    }

    @Test func callbackWithoutStateIsRejected() {
        let url = URL(string: "app://callback?code=abc123")!
        #expect(throws: AdobeAuthError.stateMismatch) {
            try AdobeAuthManager.authorizationCode(from: url, expectedState: "expected")
        }
    }

    @Test func callbackWithoutCodeIsRejected() {
        let url = URL(string: "app://callback?state=expected")!
        #expect(throws: AdobeAuthError.noAuthCode) {
            try AdobeAuthManager.authorizationCode(from: url, expectedState: "expected")
        }
    }
}
