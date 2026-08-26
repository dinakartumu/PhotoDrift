import Testing
import Foundation
@testable import PhotoDrift

struct TokenStoreTests {

    /// Each test gets its own keychain service so runs cannot contaminate each other,
    /// or the real account.
    private func makeStore() -> KeychainTokenStore {
        KeychainTokenStore(service: "PhotoDriftTests-\(UUID().uuidString)")
    }

    // MARK: - Round trip

    @Test func savedTokensComeBackOut() throws {
        let store = makeStore()
        defer { try? store.clear() }

        let expiry = Date(timeIntervalSince1970: 1_700_000_000)
        let tokens = AdobeTokens(accessToken: "access-1", refreshToken: "refresh-1", expiry: expiry)
        try store.save(tokens)

        #expect(try store.load() == tokens)
    }

    @Test func loadingAnEmptyStoreReturnsNil() throws {
        let store = makeStore()
        defer { try? store.clear() }
        #expect(try store.load() == nil)
    }

    @Test func savingTwiceReplacesRatherThanDuplicating() throws {
        let store = makeStore()
        defer { try? store.clear() }

        try store.save(AdobeTokens(accessToken: "first", refreshToken: "r1", expiry: nil))
        try store.save(AdobeTokens(accessToken: "second", refreshToken: "r2", expiry: nil))

        #expect(try store.load()?.accessToken == "second")
    }

    @Test func clearingRemovesTheTokens() throws {
        let store = makeStore()
        try store.save(AdobeTokens(accessToken: "a", refreshToken: "r", expiry: nil))
        try store.clear()
        #expect(try store.load() == nil)
    }

    @Test func clearingAnEmptyStoreIsNotAnError() throws {
        let store = makeStore()
        try store.clear()
        try store.clear()
    }

    @Test func nilFieldsSurviveTheRoundTrip() throws {
        let store = makeStore()
        defer { try? store.clear() }

        try store.save(AdobeTokens(accessToken: nil, refreshToken: "only-refresh", expiry: nil))
        let loaded = try store.load()
        #expect(loaded?.accessToken == nil)
        #expect(loaded?.refreshToken == "only-refresh")
        #expect(loaded?.expiry == nil)
    }

    // MARK: - Migration off the SwiftData store

    @Test func legacyTokensAreDetectedWhenAnyFieldIsPresent() {
        let tokens = AdobeTokens.legacy(accessToken: nil, refreshToken: "r", expiry: nil)
        #expect(tokens?.refreshToken == "r")
    }

    @Test func legacyMigrationIsSkippedWhenNothingWasStored() {
        #expect(AdobeTokens.legacy(accessToken: nil, refreshToken: nil, expiry: nil) == nil)
    }

    @Test func legacyMigrationCarriesEveryField() throws {
        let expiry = Date(timeIntervalSince1970: 1_700_000_000)
        let tokens = try #require(
            AdobeTokens.legacy(accessToken: "a", refreshToken: "r", expiry: expiry)
        )
        #expect(tokens == AdobeTokens(accessToken: "a", refreshToken: "r", expiry: expiry))
    }

    // MARK: - Signed-in derivation

    @Test func aRefreshTokenMeansSignedIn() {
        let tokens = AdobeTokens(accessToken: nil, refreshToken: "r", expiry: nil)
        #expect(tokens.isSignedIn(now: Date()))
    }

    @Test func anUnexpiredAccessTokenMeansSignedIn() {
        let now = Date(timeIntervalSince1970: 1_000)
        let tokens = AdobeTokens(
            accessToken: "a", refreshToken: nil,
            expiry: now.addingTimeInterval(60)
        )
        #expect(tokens.isSignedIn(now: now))
    }

    @Test func anExpiredAccessTokenWithNoRefreshMeansSignedOut() {
        let now = Date(timeIntervalSince1970: 1_000)
        let tokens = AdobeTokens(
            accessToken: "a", refreshToken: nil,
            expiry: now.addingTimeInterval(-60)
        )
        #expect(!tokens.isSignedIn(now: now))
    }

    @Test func emptyTokensMeanSignedOut() {
        #expect(!AdobeTokens(accessToken: nil, refreshToken: nil, expiry: nil).isSignedIn(now: Date()))
    }
}
