import Foundation

nonisolated enum AdobeConfig {
    static let clientID = "e81a12b37b6d43729261cd2cc7e23bce"

    static let authorizationEndpoint = URL(string: "https://ims-na1.adobelogin.com/ims/authorize/v2")!
    static let tokenEndpoint = URL(string: "https://ims-na1.adobelogin.com/ims/token/v3")!
    static let lightroomBaseURL = URL(string: "https://lr.adobe.io/v2/")!
    static let redirectURI = "adobe+184ab10f31827689d51676ba71185df424f3fa09://adobeid/e81a12b37b6d43729261cd2cc7e23bce"
    static let callbackScheme = "adobe+184ab10f31827689d51676ba71185df424f3fa09"
    static let scopes = "openid,offline_access,lr_partner_apis,lr_partner_rendition_apis"

    // PKCE parameters are deliberately absent here: they are generated per authorization
    // request by PKCE.generate(). A fixed verifier — especially one committed to a public
    // repository — lets anyone who intercepts an authorization code redeem it for tokens.
}
