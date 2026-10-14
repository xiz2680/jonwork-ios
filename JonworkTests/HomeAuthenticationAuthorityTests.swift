@testable import Jonwork
import AuthenticationServices
import Foundation
import Testing
import UIKit

@Suite(.serialized) @MainActor
struct HomeAuthenticationAuthorityTests {
    private let origin = URL(string: "https://home-auth.fixture.test")!

    @Test(arguments: [200, 401, 403, 409])
    func suspendedOldReadCannotReturnOrDeleteNewCredentials(_ status: Int) async throws {
        let fixture = HomeRequestFixture()
        let store = MemoryHomeCredentials(tokens: tokens("a"))
        let authority = HomeAuthenticationAuthority()
        let session = fixture.session()
        defer { session.invalidateAndCancel(); HomeFixtureURLProtocol.fixture = nil }
        let old = HomeGatewayClient(origin: origin, session: session, authority: authority, credentials: store)
        _ = try await old.signIn(anchor: { ASPresentationAnchor() })
        fixture.suspendPath = "/v1/home/sessions"
        let read = Task { try await old.history() }
        try await waitUntil { fixture.hasSuspendedRequest }
        store.tokens = tokens("b")
        let new = HomeGatewayClient(origin: origin, session: session, authority: authority, credentials: store)
        _ = try await new.signIn(anchor: { ASPresentationAnchor() })
        fixture.release(status: status)
        do { _ = try await read.value; Issue.record("Old read returned after replacement") } catch {}
        #expect(store.tokens?.accessToken == tokens("b").accessToken)
        #expect(try await new.history().identity.subject == "fixture-subject")
    }

    @Test
    func oldSuspendedHandshakeFailureCannotDeleteNewCredentials() async throws {
        let fixture = HomeRequestFixture()
        let store = MemoryHomeCredentials(tokens: tokens("a"))
        let authority = HomeAuthenticationAuthority()
        let session = fixture.session()
        defer { session.invalidateAndCancel(); HomeFixtureURLProtocol.fixture = nil }
        fixture.suspendPath = "/v1/home/handshake"
        let old = HomeGatewayClient(origin: origin, session: session, authority: authority, credentials: store)
        let pending = Task { try await old.signIn(anchor: { ASPresentationAnchor() }) }
        try await waitUntil { fixture.hasSuspendedRequest }
        fixture.suspendPath = nil
        store.tokens = tokens("b")
        let new = HomeGatewayClient(origin: origin, session: session, authority: authority, credentials: store)
        _ = try await new.signIn(anchor: { ASPresentationAnchor() })
        fixture.release(status: 401)
        do { _ = try await pending.value; Issue.record("Old handshake returned") } catch {}
        #expect(store.tokens?.accessToken == tokens("b").accessToken)
    }

    @Test
    func logoutFencesNoncooperativeAuthorizationAndFailedRemoteRevokeAcrossClients() async throws {
        let fixture = HomeRequestFixture()
        let store = MemoryHomeCredentials(tokens: nil)
        let authority = HomeAuthenticationAuthority()
        let session = fixture.session()
        defer { session.invalidateAndCancel(); HomeFixtureURLProtocol.fixture = nil }
        let authorizer = SuspendedHomeAuthorizer()
        let old = HomeGatewayClient(origin: origin, session: session, authority: authority, credentials: store, authorizerFactory: { _, _ in authorizer })
        var invalidations = 0
        old.onIdentityInvalidated = { invalidations += 1 }
        let pending = Task { try await old.signIn(anchor: { ASPresentationAnchor() }) }
        try await waitUntil { authorizer.continuation != nil }
        store.tokens = tokens("b")
        let menu = HomeGatewayClient(origin: origin, session: session, authority: authority, credentials: store, authorizerFactory: { _, _ in authorizer })
        await #expect(throws: PiServiceError.gatewayUnavailable) { try await menu.signOut(anchor: { ASPresentationAnchor() }) }
        #expect(store.tokens == nil)
        #expect(authorizer.cancelled)
        #expect(authorizer.revocations == 1)
        authorizer.continuation?.resume(returning: tokens("a"))
        authorizer.continuation = nil
        await #expect(throws: CancellationError.self) { _ = try await pending.value }
        #expect(store.tokens == nil)
        #expect(invalidations >= 2)
        await #expect(throws: PiServiceError.authenticationRequired) { _ = try await old.history() }
    }

    @Test(arguments: [false, true])
    func freshRootAccountMenuRecognizesAndClearsHomeOnlyOrBothScopes(_ includesPi: Bool) async throws {
        let suite = "HomeRootLogout." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let piStore = MemoryPiAccountCredentials()
        let profile = PiServerProfileStore(defaults: defaults, credentials: piStore)
        if includesPi { try profile.save(baseURL: origin, token: "synthetic-pi-account-marker") }
        let coordinator = PiSessionCoordinator(defaults: defaults, renderOverride: { _, _ in })
        let domain = PiServerDomainCoordinator(profileStore: profile, sessionCoordinator: coordinator, serviceFactory: { _ in throw PiServiceError.gatewayUnavailable })
        let fixture = HomeRequestFixture()
        let session = fixture.session()
        defer { session.invalidateAndCancel(); HomeFixtureURLProtocol.fixture = nil }
        let homeStore = MemoryHomeCredentials(tokens: tokens("b"))
        let authorizer = SuspendedHomeAuthorizer()
        let authority = HomeAuthenticationAuthority()
        let live = HomeGatewayClient(origin: origin, session: session, authority: authority, credentials: homeStore)
        _ = try await live.signIn(anchor: { ASPresentationAnchor() })
        let fresh = HomeGatewayClient(origin: origin, session: session, authority: authority, credentials: homeStore, authorizerFactory: { _, _ in authorizer })
        let configuration = PiGatewayDeploymentConfiguration(environment: .debug, baseURL: origin)
        let menu = SettingController.SettingContent.PiServerController(profileStore: profile, gatewayConfiguration: configuration, autoConnect: false, domainCoordinator: domain, homeClient: fresh)
        menu.loadViewIfNeeded()
        #expect(menu.hasSavedToken)
        // Merely opening/dismissing the account confirmation cannot remove either scope.
        menu.confirmRemoveSavedToken()
        #expect(homeStore.tokens != nil)
        #expect(try profile.hasSavedToken() == includesPi)
        menu.dismiss(animated: false)
        await menu.removeSavedToken()
        #expect(homeStore.tokens == nil)
        #expect(try !profile.hasSavedToken())
        #expect(!menu.hasSavedToken)
        #expect(authorizer.revocations == 1)
        await #expect(throws: PiServiceError.authenticationRequired) { _ = try await live.history() }
    }

    @Test
    func historySignOutShowsFailedRevokeOnClearedUIKitSurface() async throws {
        let suite = "HomeHistoryLogout." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let profile = PiServerProfileStore(defaults: defaults, credentials: MemoryPiAccountCredentials())
        let coordinator = PiSessionCoordinator(defaults: defaults, renderOverride: { _, _ in })
        let domain = PiServerDomainCoordinator(profileStore: profile, sessionCoordinator: coordinator, serviceFactory: { _ in throw PiServiceError.gatewayUnavailable })
        let fixture = HomeRequestFixture()
        fixture.sessions = [["session_id": "private-history", "title": "Private account history"]]
        let session = fixture.session()
        defer { session.invalidateAndCancel(); HomeFixtureURLProtocol.fixture = nil }
        let store = MemoryHomeCredentials(tokens: tokens("a"))
        let authorizer = SuspendedHomeAuthorizer()
        let client = HomeGatewayClient(origin: origin, session: session, authority: HomeAuthenticationAuthority(), credentials: store, authorizerFactory: { _, _ in authorizer })
        let handshake = try await client.signIn(anchor: { ASPresentationAnchor() })
        let history = HomeConversationHistoryController(client: client, handshake: handshake, domainCoordinator: domain)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let nav = UINavigationController(rootViewController: history)
        window.rootViewController = nav
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        history.loadViewIfNeeded()
        try await waitUntil { history.tableView(history.tableView, numberOfRowsInSection: 0) == 1 }
        await history.signOutConfirmed()
        let alert = try #require(history.presentedViewController as? UIAlertController)
        #expect(alert.message == PiServiceError.gatewayUnavailable.localizedDescription)
        #expect(store.tokens == nil)
        #expect(authorizer.revocations == 1)
        #expect(history.tableView(history.tableView, numberOfRowsInSection: 0) == 0)
        #expect(nav.viewControllers.count == 1)
        await #expect(throws: PiServiceError.authenticationRequired) { _ = try await client.history() }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw HomeFixtureError.timeout }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func tokens(_ marker: String) -> HomeOAuthTokens {
        .init(accessToken: String(repeating: marker, count: 32), refreshToken: String(repeating: marker, count: 33), expiresAt: .distantFuture, refreshExpiresAt: .distantFuture, scope: "home.read")
    }
}

@MainActor private final class MemoryHomeCredentials: HomeCredentialStoring {
    var tokens: HomeOAuthTokens?
    init(tokens: HomeOAuthTokens?) { self.tokens = tokens }
    func load(origin: URL) throws -> HomeOAuthTokens? { tokens }
    func save(_ tokens: HomeOAuthTokens, origin: URL) throws { self.tokens = tokens }
    func remove(origin: URL) throws { tokens = nil }
}

@MainActor private final class SuspendedHomeAuthorizer: HomeOAuthAuthorizing {
    var continuation: CheckedContinuation<HomeOAuthTokens, Error>?
    var cancelled = false
    var revocations = 0
    func authorize(discovery: HomeDiscovery, origin: URL) async throws -> HomeOAuthTokens {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func refresh(_ tokens: HomeOAuthTokens, discovery: HomeDiscovery, origin: URL) async throws -> HomeOAuthTokens { tokens }
    func cancel() { cancelled = true } // Intentionally noncooperative fixture.
    func revoke(_ tokens: HomeOAuthTokens, discovery: HomeDiscovery, origin: URL) async throws {
        revocations += 1
        throw PiServiceError.gatewayUnavailable
    }
}

private final class HomeRequestFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var suspended: HomeFixtureURLProtocol?
    var sessions: [[String: String]] = []
    var suspendPath: String?
    var hasSuspendedRequest: Bool { lock.withLock { suspended != nil } }
    func session() -> URLSession {
        HomeFixtureURLProtocol.fixture = self
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HomeFixtureURLProtocol.self]
        return URLSession(configuration: configuration)
    }
    func handle(_ request: HomeFixtureURLProtocol) {
        if request.request.url?.path == suspendPath { lock.withLock { suspended = request }; return }
        DispatchQueue.global().async { self.respond(request, status: 200) }
    }
    func release(status: Int) {
        suspendPath = nil
        let request = lock.withLock { let value = suspended; suspended = nil; return value }
        if let request { respond(request, status: status) }
    }
    private func respond(_ request: HomeFixtureURLProtocol, status: Int) {
        let url = request.request.url!
        let identity: [String: Any] = ["subject": "fixture-subject", "scopeType": "personal", "scopeId": "", "workspaceId": "fixture-workspace", "generation": String(repeating: "a", count: 64)]
        var body: [String: Any] = ["contract": "jonwork-home/1.0", "identity": identity, "sessions": sessions]
        if url.path == "/.well-known/jonwork-home" {
            let origin = "https://home-auth.fixture.test"
            body = ["contract": "jonwork-home/1.0", "apiVersion": "1.0", "handshakePath": "/v1/home/handshake", "capabilities": ["mutations": false], "authentication": ["type": "oauth2_authorization_code", "clientId": "fixture-ios", "scopes": ["home.read"], "pkceMethods": ["S256"], "authorizationEndpoint": origin + "/v1/home/auth/authorize", "tokenEndpoint": origin + "/v1/home/auth/token", "revocationEndpoint": origin + "/v1/home/auth/revoke", "refreshTokenRotation": "required"]]
        } else if url.path == "/v1/home/handshake" {
            body["capabilities"] = ["history": true, "snapshot": true, "eventReplay": true, "mutations": false, "identitySwitch": false]
            body["blocked"] = []
        }
        let data = try! JSONSerialization.data(withJSONObject: body)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json", "Content-Length": String(data.count)])!
        request.client?.urlProtocol(request, didReceive: response, cacheStoragePolicy: .notAllowed)
        request.client?.urlProtocol(request, didLoad: data)
        request.client?.urlProtocolDidFinishLoading(request)
    }
}

private final class HomeFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var fixture: HomeRequestFixture?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "home-auth.fixture.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.fixture!.handle(self) }
    override func stopLoading() {} // Deliver late synthetic responses deliberately.
}

private final class MemoryPiAccountCredentials: PiCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?
    func saveToken(_ token: String, server: URL) throws { lock.withLock { value = token } }
    func token(server: URL) throws -> String? { lock.withLock { value } }
    func removeToken(server: URL) throws { lock.withLock { value = nil } }
}

private enum HomeFixtureError: Error { case timeout }
