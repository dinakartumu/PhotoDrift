import Foundation

enum AdobeConfig {
    static let clientID = "e81a12b37b6d43729261cd2cc7e23bce"

    static let authorizationEndpoint = URL(string: "https://ims-na1.adobelogin.com/ims/authorize/v2")!
    static let tokenEndpoint = URL(string: "https://ims-na1.adobelogin.com/ims/token/v3")!
    static let lightroomBaseURL = URL(string: "https://lr.adobe.io/v2/")!
    static let redirectURI = "adobe+184ab10f31827689d51676ba71185df424f3fa09://adobeid/e81a12b37b6d43729261cd2cc7e23bce"
    static let callbackScheme = "adobe+184ab10f31827689d51676ba71185df424f3fa09"
    static let codeVerifier = "NteKaJ2v80FNLDYNVwibA5EiboBLbE_s1F7IwGApexD705j2"
    static let codeChallenge = "nt-c5aVWPvukNLxU5MNc4bwVuujKIXpLRVFXlt1TKeI"
    static let scopes = "openid,offline_access,lr_partner_apis,lr_partner_rendition_apis"
}
