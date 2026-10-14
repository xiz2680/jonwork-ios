@testable import Jonwork
import Foundation
import Testing

@Suite(.serialized)
struct PiAuthenticationFlowTests {
    @Test
    func `authentication recovery requests credentials only for explicit expiry`() {
        #expect(PiAuthenticationRecoveryPolicy.requiresFreshSignIn(after: PiOAuthError.refreshUnavailable))
        #expect(PiAuthenticationRecoveryPolicy.requiresFreshSignIn(after: PiServiceError.authenticationRequired))
        #expect(!PiAuthenticationRecoveryPolicy.requiresFreshSignIn(after: PiServiceError.networkUnavailable))
        #expect(!PiAuthenticationRecoveryPolicy.requiresFreshSignIn(after: PiServiceError.timedOut))
        #expect(!PiAuthenticationRecoveryPolicy.requiresFreshSignIn(
            after: PiServiceError.transportFailure(code: URLError.serverCertificateUntrusted.rawValue)
        ))
    }

    @Test
    func `credential provider preserves tokens when refresh transport fails`() async throws {
        let credentials = AuthenticationCredentialStore()
        let defaults = UserDefaults(suiteName: "PiAuthenticationFlowTests.transport")!
        defer { defaults.removePersistentDomain(forName: "PiAuthenticationFlowTests.transport") }
        let baseURL = gatewayURL
        let old = PiOAuthTokens(
            accessToken: "old-access", refreshToken: "old-refresh",
            expiresAt: .distantPast, refreshExpiresAt: .distantFuture
        )
        let provider = PiCredentialProvider(
            baseURL: baseURL,
            tokens: old,
            authorizer: AuthenticationAuthorizer(error: PiServiceError.networkUnavailable),
            discovery: try discovery(),
            profileStore: PiServerProfileStore(defaults: defaults, credentials: credentials)
        )

        await #expect(throws: PiServiceError.networkUnavailable) {
            _ = try await provider.refresh(rejectedAccessToken: old.accessToken)
        }
        #expect(try await provider.accessToken() == old.accessToken)
        #expect(credentials.removalCount == 0)
    }

    @Test
    func `credential provider fails closed only when refresh is explicitly invalid`() async throws {
        let credentials = AuthenticationCredentialStore()
        let defaults = UserDefaults(suiteName: "PiAuthenticationFlowTests.invalid")!
        defer { defaults.removePersistentDomain(forName: "PiAuthenticationFlowTests.invalid") }
        let old = PiOAuthTokens(
            accessToken: "old-access", refreshToken: "old-refresh",
            expiresAt: .distantPast, refreshExpiresAt: .distantFuture
        )
        let provider = PiCredentialProvider(
            baseURL: gatewayURL,
            tokens: old,
            authorizer: AuthenticationAuthorizer(error: PiOAuthError.refreshUnavailable),
            discovery: try discovery(),
            profileStore: PiServerProfileStore(defaults: defaults, credentials: credentials)
        )

        await #expect(throws: PiServiceError.authenticationRequired) {
            _ = try await provider.refresh(rejectedAccessToken: old.accessToken)
        }
        await #expect(throws: PiServiceError.authenticationRequired) {
            _ = try await provider.accessToken()
        }
        #expect(credentials.removalCount > 0)
    }

    @Test
    func `default conversation policy prefers running then recent then creation`() {
        let recent = PiSessionPresentation(id: "recent", name: nil, messageCount: 1, isRunning: false)
        let running = PiSessionPresentation(id: "running", name: nil, messageCount: 2, isRunning: true)
        #expect(PiDefaultSessionPolicy.sessionID(in: [recent, running]) == "running")
        #expect(PiDefaultSessionPolicy.sessionID(in: [recent]) == "recent")
        #expect(PiDefaultSessionPolicy.sessionID(in: []) == nil)
    }

    @Test
    func `discovery absence is not reported as a missing conversation`() async throws {
        let service = try makeService(token: nil) { _ in .response(404, "not found", "text/plain") }
        await #expect(throws: PiServiceError.gatewayUnavailable) {
            try await service.discover()
        }
    }

    @Test
    func `session absence remains a missing conversation`() async throws {
        let service = try makeService { _ in .response(404, "not found", "text/plain") }
        await #expect(throws: PiServiceError.sessionUnavailable) {
            try await service.snapshot(sessionID: "missing")
        }
    }

    @Test
    func `gateway server failure and malformed discovery remain distinct`() async throws {
        let unavailable = try makeService(token: nil) { _ in .response(503, "offline", "text/plain") }
        await #expect(throws: PiServiceError.gatewayUnavailable) {
            try await unavailable.discover()
        }

        let incompatible = try makeService(token: nil) { _ in .response(200, "<html></html>", "text/html") }
        await #expect(throws: PiServiceError.invalidResponse) {
            try await incompatible.discover()
        }
    }

    @Test(arguments: [
        (401, PiAuthenticationExpectedError.invalidCredentials),
        (403, PiAuthenticationExpectedError.accessDenied),
        (404, PiAuthenticationExpectedError.gatewayUnavailable),
        (503, PiAuthenticationExpectedError.gatewayUnavailable),
    ])
    @MainActor
    func `password endpoint classifies HTTP failures`(
        status: Int,
        expected: PiAuthenticationExpectedError
    ) async throws {
        let client = passwordClient { _ in .response(status, #"{"error":"failure"}"#, "application/json") }
        do {
            _ = try await client.authorize(discovery: try discovery(), baseURL: gatewayURL)
            Issue.record("Expected sign-in to fail")
        } catch {
            #expect(expected.matches(error))
        }
    }

    @Test(arguments: [
        URLError.Code.notConnectedToInternet,
        .timedOut,
        .serverCertificateUntrusted,
    ])
    @MainActor
    func `password endpoint preserves typed transport failures`(_ code: URLError.Code) async throws {
        let client = passwordClient { _ in .failure(URLError(code)) }
        do {
            _ = try await client.authorize(discovery: try discovery(), baseURL: gatewayURL)
            Issue.record("Expected sign-in to fail")
        } catch let error as PiServiceError {
            switch (code, error) {
            case (.notConnectedToInternet, .networkUnavailable), (.timedOut, .timedOut):
                break
            case (.serverCertificateUntrusted, .transportFailure(let value)):
                #expect(value == code.rawValue)
            default:
                Issue.record("Unexpected mapping: \(error)")
            }
        }
    }

    private var gatewayURL: URL { URL(string: "https://gateway.example.test")! }

    private func discovery() throws -> PiGatewayWire.Discovery {
        let file = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "Fixtures/PiGatewayV1/discovery.json")
        return try JSONDecoder().decode(PiGatewayWire.Discovery.self, from: Data(contentsOf: file))
    }

    private func makeService(
        token: String? = "access-token",
        handler: @escaping @Sendable (URLRequest) -> PiAuthenticationStub.Result
    ) throws -> PiService {
        PiAuthenticationStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PiAuthenticationStub.self]
        return PiService(
            configuration: try PiServerConfiguration(baseURL: gatewayURL, token: token),
            session: URLSession(configuration: configuration)
        )
    }

    private func passwordClient(
        handler: @escaping @Sendable (URLRequest) -> PiAuthenticationStub.Result
    ) -> PiPasswordOAuthClient {
        PiAuthenticationStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PiAuthenticationStub.self]
        return PiPasswordOAuthClient(
            credentials: .init(email: "person@example.test", password: "password-123"),
            installationID: "ios-installation-01",
            session: URLSession(configuration: configuration)
        )
    }
}

enum PiAuthenticationExpectedError: Sendable {
    case invalidCredentials
    case accessDenied
    case gatewayUnavailable

    func matches(_ error: Error) -> Bool {
        switch self {
        case .invalidCredentials: error as? PiOAuthError == .invalidCredentials
        case .accessDenied: error as? PiServiceError == .accessDenied
        case .gatewayUnavailable: error as? PiServiceError == .gatewayUnavailable
        }
    }
}

private final class PiAuthenticationStub: URLProtocol, @unchecked Sendable {
    enum Result: Sendable {
        case response(Int, String, String)
        case failure(URLError)
    }

    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Result)?

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Self.handler?(request) ?? .failure(URLError(.unknown)) {
        case let .response(status, body, contentType):
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil,
                headerFields: ["Content-Type": contentType]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private struct AuthenticationAuthorizer: PiOAuthAuthorizing {
    let error: any Error & Sendable

    @MainActor
    func authorize(discovery _: PiGatewayWire.Discovery, baseURL _: URL) async throws -> PiOAuthTokens {
        throw error
    }

    func refresh(_: PiOAuthTokens, discovery _: PiGatewayWire.Discovery) async throws -> PiOAuthTokens {
        throw error
    }

    func revoke(_: PiOAuthTokens, discovery _: PiGatewayWire.Discovery) async throws {}
}

private final class AuthenticationCredentialStore: PiCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokenValue: String?
    private var oauthValue: PiOAuthTokens?
    private var removals = 0

    var removalCount: Int { lock.withLock { removals } }

    func saveToken(_ token: String, server _: URL) throws { lock.withLock { tokenValue = token } }
    func token(server _: URL) throws -> String? { lock.withLock { tokenValue } }
    func removeToken(server _: URL) throws { lock.withLock { tokenValue = nil; removals += 1 } }
    func saveOAuthTokens(_ tokens: PiOAuthTokens, server _: URL) throws { lock.withLock { oauthValue = tokens } }
    func oauthTokens(server _: URL) throws -> PiOAuthTokens? { lock.withLock { oauthValue } }
    func removeOAuthTokens(server _: URL) throws { lock.withLock { oauthValue = nil; removals += 1 } }
}
