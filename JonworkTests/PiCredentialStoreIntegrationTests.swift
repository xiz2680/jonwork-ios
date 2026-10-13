@testable import Jonwork
import Foundation
import Testing

/// Real Keychain access through the signed test host; no network or production accounts.
struct PiCredentialStoreIntegrationTests {
    @Test func signedHostCanSaveUpdateLoadAndDeleteKeychainCredentials() throws {
        let store = PiCredentialStore()
        let host = "keychain-fixture-" + UUID().uuidString.lowercased() + ".invalid"
        let server = try #require(URL(string: "https://\(host)"))
        let normalizedServer = try #require(URL(string: "https://\(host):443"))
        defer {
            do { try store.removeOAuthTokens(server: server) }
            catch { Issue.record(error, "Fixture Keychain cleanup failed") }
        }

        #expect(try store.token(server: server) == nil)
        #expect(try store.oauthTokens(server: server) == nil)
        try store.saveToken("dummy-keychain-first", server: server)
        #expect(try store.token(server: normalizedServer) == "dummy-keychain-first")
        try store.saveToken("dummy-keychain-updated", server: normalizedServer)
        #expect(try store.token(server: server) == "dummy-keychain-updated")

        let tokens = PiOAuthTokens(
            accessToken: "dummy-access-" + UUID().uuidString,
            refreshToken: "dummy-refresh-" + UUID().uuidString,
            expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
            refreshExpiresAt: Date(timeIntervalSince1970: 2_000_086_400)
        )
        try store.saveOAuthTokens(tokens, server: server)
        #expect(try store.oauthTokens(server: normalizedServer) == tokens)
        let rotated = PiOAuthTokens(
            accessToken: "dummy-rotated-access-" + UUID().uuidString,
            refreshToken: "dummy-rotated-refresh-" + UUID().uuidString,
            expiresAt: tokens.expiresAt.addingTimeInterval(600),
            refreshExpiresAt: tokens.refreshExpiresAt?.addingTimeInterval(600)
        )
        try store.saveOAuthTokens(rotated, server: normalizedServer)
        #expect(try store.oauthTokens(server: server) == rotated)

        try store.removeOAuthTokens(server: normalizedServer)
        #expect(try store.oauthTokens(server: server) == nil)
        #expect(try store.token(server: server) == nil)
        try store.removeOAuthTokens(server: server)
    }
}
