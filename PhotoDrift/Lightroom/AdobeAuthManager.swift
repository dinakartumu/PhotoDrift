import AuthenticationServices
import SwiftData

actor AdobeAuthManager {
    static let shared = AdobeAuthManager()

    private var accessToken: String?
    private var refreshToken: String?
    private var tokenExpiry: Date?
    private var didLogNetworkDiagnostics = false
    private var modelContainer: ModelContainer?
    private var activeSession: ASWebAuthenticationSession?
    private var activeAnchorProvider: AnchorProvider?
    private var authContinuation: CheckedContinuation<URL, Error>?

    func configure(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func signIn(from anchor: ASPresentationAnchor) async throws -> String {
        var components = URLComponents(url: AdobeConfig.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: AdobeConfig.clientID),
            URLQueryItem(name: "scope", value: AdobeConfig.scopes),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: AdobeConfig.redirectURI),
            URLQueryItem(name: "code_challenge", value: AdobeConfig.codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        let authURL = components.url!
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

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AdobeAuthError.noAuthCode
        }

        return try await exchangeCodeForTokens(code: code)
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

    private func exchangeCodeForTokens(code: String) async throws -> String {
        await logNetworkDiagnosticsIfNeeded()
        var request = URLRequest(url: AdobeConfig.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=authorization_code",
            "client_id=\(AdobeConfig.clientID)",
            "code=\(code)",
            "code_verifier=\(AdobeConfig.codeVerifier)",
            "redirect_uri=\(AdobeConfig.redirectURI)",
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw AdobeAuthError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        self.accessToken = tokenResponse.accessToken
        self.refreshToken = tokenResponse.refreshToken
        self.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
        await persistTokensIfPossible()

        return tokenResponse.accessToken
    }

    func refreshAccessToken() async throws -> String {
        guard let refreshToken else {
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
        await persistTokensIfPossible()

        return tokenResponse.accessToken
    }

    func getValidToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, Date() < expiry {
            return token
        }
        return try await refreshAccessToken()
    }

    func loadTokens(accessToken: String?, refreshToken: String?, tokenExpiry: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenExpiry = tokenExpiry
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        tokenExpiry = nil
    }

    var isSignedIn: Bool {
        accessToken != nil
    }

    private func clearSession() {
        activeSession = nil
        activeAnchorProvider = nil
    }

    private func persistTokensIfPossible() async {
        guard let modelContainer else { return }
        let accessToken = self.accessToken
        let refreshToken = self.refreshToken
        let tokenExpiry = self.tokenExpiry
        await MainActor.run {
            let context = ModelContext(modelContainer)
            let settings = AppSettings.current(in: context)
            settings.adobeAccessToken = accessToken
            settings.adobeRefreshToken = refreshToken
            settings.adobeTokenExpiry = tokenExpiry
            try? context.save()
        }
    }

    private func logNetworkDiagnosticsIfNeeded() async {
        guard !didLogNetworkDiagnostics else { return }
        didLogNetworkDiagnostics = true
        let report = await AdobeNetworkDiagnostics.run(host: "ims-na1.adobelogin.com")
        print(report)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum AdobeAuthError: Error, LocalizedError, Equatable {
    case noCallback
    case noAuthCode
    case tokenExchangeFailed
    case tokenRefreshFailed
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .noCallback: "Authentication callback not received"
        case .noAuthCode: "No authorization code in callback"
        case .tokenExchangeFailed: "Failed to exchange code for tokens"
        case .tokenRefreshFailed: "Failed to refresh access token"
        case .noRefreshToken: "No refresh token available. Please sign in again."
        }
    }
}

final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
