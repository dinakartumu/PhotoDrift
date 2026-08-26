// ASWebAuthenticationSession predates strict concurrency annotation; @preconcurrency keeps
// its un-annotated types from producing Sendable warnings at every use site.
@preconcurrency import AuthenticationServices
import SwiftData

actor AdobeAuthManager {
    static let shared = AdobeAuthManager()

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var didLogNetworkDiagnostics = false
    private var modelContainer: ModelContainer?
    private let tokenStore = KeychainTokenStore()
    private var activeSession: ASWebAuthenticationSession?
    private var activeAnchorProvider: AnchorProvider?
    private var authContinuation: CheckedContinuation<URL, Error>?
    /// Held only for the duration of one authorization request.
    private var pendingVerifier: String?
    private var pendingState: String?

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Builds the authorization request. Only the derived challenge travels to Adobe — the
    /// verifier stays on device until the token exchange proves we started the flow.
    static func authorizationURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: AdobeConfig.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AdobeConfig.clientID),
            URLQueryItem(name: "scope", value: AdobeConfig.scopes),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AdobeConfig.redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// Extracts the authorization code, rejecting callbacks whose `state` does not match the
    /// value we sent. Without this check a third party could feed us their own code.
    static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let value = { (name: String) in items?.first { $0.name == name }?.value }

        guard let state = value("state"), state == expectedState else {
            throw AdobeAuthError.stateMismatch
        }
        guard let code = value("code") else {
            throw AdobeAuthError.noAuthCode
        }
        return code
    }

    func signIn(from anchor: ASPresentationAnchor) async throws -> String {
        let pkce = PKCE.generate()
        let state = OAuthRandom.urlSafeString(byteCount: 16)
        pendingVerifier = pkce.verifier
        pendingState = state

        let authURL = Self.authorizationURL(pkce: pkce, state: state)
        let anchorProvider = AnchorProvider(anchor: anchor)
        self.activeAnchorProvider = anchorProvider

        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            self.authContinuation = continuation

            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: AdobeConfig.callbackScheme
            ) { [weak self] url, error in
                Task {
                    if let error {
                        await self?.resumeAuth(with: .failure(error))
                    } else if let url {
                        await self?.resumeAuth(with: .success(url))
                    } else {
                        await self?.resumeAuth(with: .failure(AdobeAuthError.noCallback))
                    }
                }
            }
            session.presentationContextProvider = anchorProvider
            session.prefersEphemeralWebBrowserSession = false
            self.activeSession = session

            DispatchQueue.main.async {
                session.start()
            }
        }

        defer { clearPendingAuth() }
        guard let expectedState = pendingState, let verifier = pendingVerifier else {
            throw AdobeAuthError.noCallback
        }
        let code = try Self.authorizationCode(from: callbackURL, expectedState: expectedState)

        return try await exchangeCodeForTokens(code: code, verifier: verifier)
    }

    /// Called from onOpenURL as a backup when ASWebAuthenticationSession
    /// doesn't intercept the callback.
    func handleCallback(url: URL) {
        guard url.scheme == AdobeConfig.callbackScheme else { return }
        resumeAuth(with: .success(url))
    }

    private func resumeAuth(with result: Result<URL, Error>) {
        guard let continuation = authContinuation else { return }
        authContinuation = nil
        clearSession()
        switch result {
        case .success(let url):
            continuation.resume(returning: url)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func clearPendingAuth() {
        pendingVerifier = nil
        pendingState = nil
    }

    private func exchangeCodeForTokens(code: String, verifier: String) async throws -> String {
        await logNetworkDiagnosticsIfNeeded()
        var request = URLRequest(url: AdobeConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=authorization_code",
            "client_id=\(AdobeConfig.clientID)",
            "code=\(code)",
            "code_verifier=\(verifier)",
            "redirect_uri=\(AdobeConfig.redirectURI)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AdobeAuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        guard let refresh = tokenResponse.refreshToken else {
            self.accessToken = nil
            self.refreshToken = nil
            self.tokenExpiry = nil
            persistTokens()
            throw AdobeAuthError.noRefreshToken
        }
        self.accessToken = tokenResponse.accessToken
        self.refreshToken = refresh
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        persistTokens()

        return tokenResponse.accessToken
    }

    func refreshAccessToken() async throws -> String {
        guard let refreshToken else {
            accessToken = nil
            tokenExpiry = nil
            persistTokens()
            throw AdobeAuthError.noRefreshToken
        }

        await logNetworkDiagnosticsIfNeeded()
        var request = URLRequest(url: AdobeConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "client_id=\(AdobeConfig.clientID)",
            "refresh_token=\(refreshToken)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AdobeAuthError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.accessToken = tokenResponse.accessToken
        if let newRefresh = tokenResponse.refreshToken {
            self.refreshToken = newRefresh
        }
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        persistTokens()

        return tokenResponse.accessToken
    }

    func getValidToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }
        return try await refreshAccessToken()
    }

    /// Loads persisted tokens, first moving across anything left behind in the pre-Keychain
    /// SwiftData fields.
    func restoreTokens() async {
        if let migrated = await migrateLegacyTokensIfNeeded() {
            apply(migrated)
            persistTokens()
            return
        }
        if let stored = try? tokenStore.load() {
            apply(stored)
        }
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
        try? tokenStore.clear()
    }

    var isSignedIn: Bool {
        currentTokens.isSignedIn()
    }

    private var currentTokens: AdobeTokens {
        AdobeTokens(accessToken: accessToken, refreshToken: refreshToken, expiry: tokenExpiry)
    }

    private func apply(_ tokens: AdobeTokens) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
        tokenExpiry = tokens.expiry
    }

    /// Reads the deprecated SwiftData token fields once, hands their contents to the Keychain
    /// and blanks them, so a plaintext refresh token does not linger in the store.
    private func migrateLegacyTokensIfNeeded() async -> AdobeTokens? {
        guard let modelContainer else { return nil }
        return await MainActor.run {
            let context = ModelContext(modelContainer)
            let settings = AppSettings.current(in: context)
            guard let legacy = AdobeTokens.legacy(
                accessToken: settings.adobeAccessToken,
                refreshToken: settings.adobeRefreshToken,
                expiry: settings.adobeTokenExpiry
            ) else { return nil }

            settings.adobeAccessToken = nil
            settings.adobeRefreshToken = nil
            settings.adobeTokenExpiry = nil
            try? context.save()
            return legacy
        }
    }

    private func clearSession() {
        activeSession = nil
        activeAnchorProvider = nil
    }

    private func persistTokens() {
        try? tokenStore.save(currentTokens)
    }

    private func logNetworkDiagnosticsIfNeeded() async {
        guard !didLogNetworkDiagnostics else { return }
        didLogNetworkDiagnostics = true
        let report = await AdobeNetworkDiagnostics.run(host: "ims-na1.adobelogin.com")
        print(report)
    }
}

nonisolated private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

nonisolated enum AdobeAuthError: Error, LocalizedError, Equatable {
    case noCallback
    case noAuthCode
    case tokenExchangeFailed
    case tokenRefreshFailed
    case noRefreshToken
    case stateMismatch

    var errorDescription: String? {
        switch self {
        case .noCallback: "Authentication callback not received"
        case .noAuthCode: "No authorization code in callback"
        case .stateMismatch: "Authentication response did not match this request. Please try signing in again."
        case .tokenExchangeFailed: "Failed to exchange code for tokens"
        case .tokenRefreshFailed: "Failed to refresh access token"
        case .noRefreshToken: "No refresh token available. Please sign in again."
        }
    }
}

nonisolated final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
