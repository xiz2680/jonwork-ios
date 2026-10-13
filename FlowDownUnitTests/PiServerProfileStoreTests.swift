@testable import FlowDown
import Foundation
import Testing
import UIKit

@Suite(.serialized)
struct PiServerProfileStoreTests {
    @Test
    func `blank token preserves credential for the same server`() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let url = try #require(URL(string: "https://pi.example.test"))

        try context.store.save(baseURL: url, token: "secret")
        try context.store.save(baseURL: url, token: nil)

        #expect(try context.store.load() == PiServerProfile(baseURL: url, token: "secret"))
        #expect(context.credentials.removedServers.isEmpty)
    }

    @Test
    func `replacing server removes previous credential`() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let first = try #require(URL(string: "https://first.example.test"))
        let second = try #require(URL(string: "https://second.example.test"))

        try context.store.save(baseURL: first, token: "secret")
        try context.store.save(baseURL: second, token: nil)

        #expect(context.credentials.removedServers.contains(first))
        #expect(try context.store.load() == PiServerProfile(baseURL: second, token: nil))
    }

    @Test
    func `failed previous credential removal rolls back replacement atomically`() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let first = try #require(URL(string: "https://first.example.test"))
        let second = try #require(URL(string: "https://second.example.test"))
        try context.store.save(baseURL: first, token: "first-secret")
        context.credentials.failNextRemoval(of: first)

        #expect(throws: PiCredentialTestError.failed) {
            try context.store.save(baseURL: second, token: "second-secret")
        }

        #expect(try context.store.load() == PiServerProfile(baseURL: first, token: "first-secret"))
        #expect(try context.credentials.token(server: second) == nil)
    }

    @Test
    func `failed same-server replacement preserves existing credential`() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let url = try #require(URL(string: "https://pi.example.test"))
        try context.store.save(baseURL: url, token: "original")
        context.credentials.failNextSave(to: url)

        #expect(throws: PiCredentialTestError.failed) {
            try context.store.save(baseURL: url, token: "replacement")
        }
        #expect(try context.store.load()?.token == "original")
    }

    @Test
    func `explicit saved-token removal preserves server profile`() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let url = try #require(URL(string: "https://pi.example.test"))
        try context.store.save(baseURL: url, token: "secret")

        try context.store.removeSavedToken()

        #expect(try context.store.load() == PiServerProfile(baseURL: url, token: nil))
        #expect(try context.store.hasSavedToken() == false)
    }

    @Test
    func `OAuth access refresh and expiry metadata remain distinct from legacy token`() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let url = try #require(URL(string: "https://pi.example.test"))
        let tokens = PiOAuthTokens(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3_600)
        )

        try context.store.save(baseURL: url, oauthTokens: tokens)

        #expect(try context.store.load()?.token == "access")
        #expect(try context.store.oauthTokens(baseURL: url) == tokens)
        #expect(try context.store.hasSavedToken())
    }

    @Test
    @MainActor
    func `server screen exposes explicit saved-token removal without revealing token`() async throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let url = try #require(URL(string: "https://pi.example.test"))
        try context.store.save(baseURL: url, token: "secret")
        let controller = SettingController.SettingContent.PiServerController(
            profileStore: context.store,
            autoConnect: false
        )
        controller.loadViewIfNeeded()

        let cell = controller.tableView(
            controller.tableView,
            cellForRowAt: IndexPath(row: 2, section: 0)
        )
        #expect((cell.contentConfiguration as? UIListContentConfiguration)?.text == String(localized: "Remove Saved Token"))
        #expect(controller.hasSavedToken)

        await controller.removeSavedToken()
        #expect(!controller.hasSavedToken)
        #expect(try context.store.load()?.token == nil)
    }

    @Test
    @MainActor
    func `sign out invalidates suspended authentication before credentials or connection can resume`() async throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let url = try #require(URL(string: "https://pi.example.test"))
        let service = SuspendedAuthenticationService()
        let authorizer = SuspendedAuthorizer()
        let coordinatorSuite = "PiAuthRace.\(UUID().uuidString)"
        let coordinatorDefaults = UserDefaults(suiteName: coordinatorSuite)!
        defer { coordinatorDefaults.removePersistentDomain(forName: coordinatorSuite) }
        let sessionCoordinator = PiSessionCoordinator(
            defaults: coordinatorDefaults,
            profileProvider: { nil },
            serviceFactory: { _ in service },
            pendingMutationStore: ProfilePendingStore(),
            reconnectDelay: { _ in },
            renderOverride: { _, _ in }
        )
        let domain = PiServerDomainCoordinator(
            profileStore: context.store,
            sessionCoordinator: sessionCoordinator,
            pendingMutationStore: ProfilePendingStore(),
            serviceFactory: { _ in service }
        )
        let authentication = Task {
            try await domain.authenticate(baseURL: url, authorizer: authorizer)
        }
        while !authorizer.isSuspended { await Task.yield() }

        try await domain.signOut()
        authorizer.resume(with: .init(
            accessToken: String(repeating: "a", count: 32),
            refreshToken: String(repeating: "b", count: 32),
            expiresAt: Date().addingTimeInterval(900)
        ))

        await #expect(throws: CancellationError.self) { _ = try await authentication.value }
        let hasSavedToken = try context.store.hasSavedToken()
        #expect(!hasSavedToken)
        #expect(service.listRepositoryCallCount == 0)
        #expect(!domain.presentation.isConnected)
    }

    @Test
    @MainActor
    func `ambiguous restore looks up receipt then replays the exact original request only when missing`() async throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let url = try #require(URL(string: "https://pi.example.test"))
        let service = CreationRecoveryService(mode: .restoreNotFound)
        let pendingStore = ProfilePendingStore()
        let domain = makeDomain(
            profileStore: context.store,
            service: service,
            pendingStore: pendingStore
        )
        _ = try await domain.authenticate(baseURL: url, authorizer: ImmediateAuthorizer())

        let created = try await domain.createOrRestoreSession(clientID: "ios-client", resumeSessionID: "session")

        #expect(created.sessionID == "session")
        #expect(service.restoreContexts.count == 2)
        #expect(service.restoreContexts[0] == service.restoreContexts[1])
        #expect(service.receiptLookups.count == 1)
        let pendingCreation = try pendingStore.loadCreation()
        #expect(pendingCreation == nil)
    }

    @Test
    @MainActor
    func `ambiguous create remains fail closed across coordinator reconstruction`() async throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let url = try #require(URL(string: "https://pi.example.test"))
        let service = CreationRecoveryService(mode: .createTimedOut)
        let pendingStore = ProfilePendingStore()
        let first = makeDomain(profileStore: context.store, service: service, pendingStore: pendingStore)
        _ = try await first.authenticate(baseURL: url, authorizer: ImmediateAuthorizer())
        await #expect(throws: PiServerDomainError.creationRecoveryRequired) {
            _ = try await first.createOrRestoreSession(clientID: "ios-client", resumeSessionID: nil)
        }
        let firstKey = try #require(service.createKeys.first)

        let second = makeDomain(profileStore: context.store, service: service, pendingStore: pendingStore)
        _ = try await second.authenticate(baseURL: url, authorizer: ImmediateAuthorizer())
        await #expect(throws: PiServerDomainError.creationRecoveryRequired) {
            _ = try await second.createOrRestoreSession(clientID: "ios-client", resumeSessionID: nil)
        }

        #expect(service.createKeys == [firstKey])
        let pendingCreation = try pendingStore.loadCreation()
        #expect(pendingCreation?.idempotencyKey == firstKey)
    }

    @MainActor
    private func makeDomain(
        profileStore: PiServerProfileStore,
        service: any PiServiceProtocol,
        pendingStore: any PiPendingMutationStoring
    ) -> PiServerDomainCoordinator {
        let suite = "PiDomainRecovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return PiServerDomainCoordinator(
            profileStore: profileStore,
            sessionCoordinator: PiSessionCoordinator(
                defaults: defaults,
                profileProvider: { nil },
                serviceFactory: { _ in service },
                pendingMutationStore: ProfilePendingStore(),
                reconnectDelay: { _ in },
                renderOverride: { _, _ in }
            ),
            pendingMutationStore: pendingStore,
            serviceFactory: { _ in service }
        )
    }

    private func makeContext() -> (
        store: PiServerProfileStore,
        credentials: PiCredentialStoreSpy,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "PiServerProfileStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let credentials = PiCredentialStoreSpy()
        return (
            PiServerProfileStore(defaults: defaults, credentials: credentials),
            credentials,
            defaults,
            suiteName
        )
    }
}

private final class SuspendedAuthorizer: PiOAuthAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<PiOAuthTokens, Error>?
    var isSuspended: Bool { lock.withLock { continuation != nil } }

    @MainActor
    func authorize(discovery _: PiGatewayWire.Discovery, baseURL _: URL) async throws -> PiOAuthTokens {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { self.continuation = continuation }
        }
    }

    func refresh(_ tokens: PiOAuthTokens, discovery _: PiGatewayWire.Discovery) async throws -> PiOAuthTokens {
        tokens
    }

    func resume(with tokens: PiOAuthTokens) {
        let value = lock.withLock { () -> CheckedContinuation<PiOAuthTokens, Error>? in
            defer { continuation = nil }
            return continuation
        }
        value?.resume(returning: tokens)
    }
}

private final class SuspendedAuthenticationService: PiServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var repositoryCalls = 0
    var listRepositoryCallCount: Int { lock.withLock { repositoryCalls } }

    func discover() async throws -> PiGatewayWire.Discovery { authRaceDiscovery() }
    func listRepositories() async throws -> [PiGatewayWire.Repository] {
        lock.withLock { repositoryCalls += 1 }
        return []
    }
}

private struct ImmediateAuthorizer: PiOAuthAuthorizing {
    @MainActor
    func authorize(discovery _: PiGatewayWire.Discovery, baseURL _: URL) async throws -> PiOAuthTokens {
        .init(
            accessToken: String(repeating: "a", count: 32),
            refreshToken: String(repeating: "b", count: 32),
            expiresAt: Date().addingTimeInterval(900)
        )
    }

    func refresh(_ tokens: PiOAuthTokens, discovery _: PiGatewayWire.Discovery) async throws -> PiOAuthTokens { tokens }
}

private final class CreationRecoveryService: PiServiceProtocol, @unchecked Sendable {
    enum Mode: Equatable { case restoreNotFound, createTimedOut }
    private let lock = NSLock()
    private let mode: Mode
    private var restores: [PiMutationContext] = []
    private var creations: [String] = []
    private var lookups: [(String, String)] = []

    init(mode: Mode) { self.mode = mode }
    var restoreContexts: [PiMutationContext] { lock.withLock { restores } }
    var createKeys: [String] { lock.withLock { creations } }
    var receiptLookups: [(String, String)] { lock.withLock { lookups } }

    func discover() async throws -> PiGatewayWire.Discovery { authRaceDiscovery() }
    func listRepositories() async throws -> [PiGatewayWire.Repository] { [.init(id: "/repo", displayName: "Repo")] }
    func listSessions(repositoryID _: String?) async throws -> [PiGatewayWire.SessionSummary] { [] }
    func snapshot(sessionID: String) async throws -> PiGatewayWire.Snapshot { recoverySnapshot(sessionID: sessionID) }

    func createSession(
        repositoryID _: String,
        name _: String?,
        clientID _: String,
        idempotencyKey: String
    ) async throws -> PiGatewayWire.Snapshot {
        lock.withLock { creations.append(idempotencyKey) }
        if mode == .createTimedOut { throw PiServiceError.timedOut }
        return recoverySnapshot(sessionID: "created")
    }

    func restoreSession(
        sessionID: String,
        clientID _: String,
        context: PiMutationContext
    ) async throws -> PiGatewayWire.Snapshot {
        let count = lock.withLock { () -> Int in
            restores.append(context)
            return restores.count
        }
        if mode == .restoreNotFound, count == 1 { throw PiServiceError.connectionLost }
        return recoverySnapshot(sessionID: sessionID)
    }

    func mutationReceipt(
        sessionID: String,
        idempotencyKey: String,
        clientID _: String
    ) async throws -> PiGatewayWire.MutationReceiptLookup {
        lock.withLock { lookups.append((sessionID, idempotencyKey)) }
        throw PiServiceError.mutationNotFound
    }
}

private func recoverySnapshot(sessionID: String) -> PiGatewayWire.Snapshot {
    .init(
        contract: PiGatewayWire.contract, sessionId: sessionID, repositoryId: "/repo", revision: 1,
        lastEventId: "0", runtime: .running, run: .init(status: .idle, operationId: nil),
        controller: .init(clientId: nil, leaseExpiresAt: nil),
        configuration: .init(model: nil, thinkingLevel: .off), messages: [], attachments: []
    )
}

private final class ProfilePendingStore: PiPendingMutationStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: PiPendingMutationRecord] = [:]
    private var creation: PiPendingCreationRecord?
    func load() throws -> [String: PiPendingMutationRecord] { lock.withLock { records } }
    func save(_ value: [String: PiPendingMutationRecord]) throws { lock.withLock { records = value } }
    func loadCreation() throws -> PiPendingCreationRecord? { lock.withLock { creation } }
    func saveCreation(_ value: PiPendingCreationRecord?) throws { lock.withLock { creation = value } }
}

private func authRaceDiscovery() -> PiGatewayWire.Discovery {
    .init(
        contract: PiGatewayWire.contract,
        apiVersion: "1.0",
        authentication: .init(
            type: "oauth2_authorization_code", clientId: "pi-ios",
            authorizationEndpoint: URL(string: "https://pi.example.test/authorize")!,
            tokenEndpoint: URL(string: "https://pi.example.test/token")!,
            revocationEndpoint: URL(string: "https://pi.example.test/revoke")!,
            scopes: ["pi.gateway"], pkceMethods: ["S256"], accessTokenLifetimeSeconds: 900,
            refreshTokenRotation: "required"
        ),
        capabilities: .init(
            repositories: true, models: true, thinking: true, sessions: true, commands: true,
            sse: true, authoritativeSnapshot: true, eventIds: true, replay: true, idempotency: true,
            singleWriter: true, takeover: true, release: true, abort: true, retry: true,
            attachments: .init(images: true, files: true)
        ),
        limits: .init(
            readTimeoutMs: 1_000, mutationTimeoutMs: 1_000, sseConnectTimeoutMs: 1_000,
            replayRetentionEvents: 100, replayRetentionSeconds: 100, idempotencyRetentionSeconds: 86_400,
            attachmentMaxBytes: 1_000_000, attachmentTotalBytes: 2_000_000, attachmentsPerPrompt: 4,
            attachmentUploadTimeoutMs: 1_000, attachmentDownloadTimeoutMs: 1_000,
            attachmentMediaTypes: ["image/png"], attachmentDigestAlgorithm: "sha-256"
        )
    )
}

private final class PiCredentialStoreSpy: PiCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [URL: String] = [:]
    private var oauth: [URL: PiOAuthTokens] = [:]
    private var removals: [URL] = []
    private var failedSave: URL?
    private var failedRemoval: URL?

    var removedServers: [URL] { lock.withLock { removals } }

    func failNextSave(to server: URL) { lock.withLock { failedSave = server } }
    func failNextRemoval(of server: URL) { lock.withLock { failedRemoval = server } }

    func saveToken(_ token: String, server: URL) throws {
        try lock.withLock {
            if failedSave == server {
                failedSave = nil
                throw PiCredentialTestError.failed
            }
            tokens[server] = token
        }
    }

    func token(server: URL) throws -> String? {
        lock.withLock { tokens[server] }
    }

    func removeToken(server: URL) throws {
        try lock.withLock {
            if failedRemoval == server {
                failedRemoval = nil
                throw PiCredentialTestError.failed
            }
            tokens[server] = nil
            removals.append(server)
        }
    }

    func saveOAuthTokens(_ tokens: PiOAuthTokens, server: URL) throws {
        lock.withLock { oauth[server] = tokens }
    }

    func oauthTokens(server: URL) throws -> PiOAuthTokens? {
        lock.withLock { oauth[server] }
    }

    func removeOAuthTokens(server: URL) throws {
        try lock.withLock {
            if failedRemoval == server {
                failedRemoval = nil
                throw PiCredentialTestError.failed
            }
            oauth[server] = nil
            tokens[server] = nil
            removals.append(server)
        }
    }
}

private enum PiCredentialTestError: Error {
    case failed
}
