import AuthenticationServices
import CryptoKit
import Foundation
import Storage

enum PiServerDomainError: Error, Equatable, LocalizedError {
    case invalidServerURL
    case creationRecoveryRequired
    case mutationPending

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            String(localized: "The Jonwork connection is not configured correctly.")
        case .creationRecoveryRequired:
            String(localized: "The previous conversation creation must be reconciled on the server before trying again.")
        case .mutationPending:
            String(localized: "The previous conversation change is still being confirmed. Try again in a moment.")
        }
    }
}

struct PiRepositoryPresentation: Equatable, Identifiable, Sendable {
    let id: String
    let displayName: String
}

struct PiSessionPresentation: Equatable, Identifiable, Sendable {
    let id: String
    let name: String?
    let messageCount: Int
    let isRunning: Bool
}

struct PiServerPresentation: Equatable, Sendable {
    var repositories: [PiRepositoryPresentation] = []
    var sessions: [PiSessionPresentation] = []
    var selectedRepositoryID: String?
    var baseURL: URL?
    var isConnected = false
}

struct PiCreatedSession: Equatable, Sendable {
    let sessionID: String
    let repository: String
    let clientID: String
    let baseURL: URL

    static func create(
        service: any PiServiceProtocol,
        repository: String,
        resumeSessionID: String?,
        clientID: String,
        baseURL: URL
    ) async throws -> Self {
        let snapshot: PiGatewayWire.Snapshot
        if let resumeSessionID {
            let current = try await service.snapshot(sessionID: resumeSessionID)
            snapshot = try await service.restoreSession(
                sessionID: resumeSessionID,
                clientID: clientID,
                context: .init(idempotencyKey: UUID().uuidString, revision: current.revision)
            )
        } else {
            snapshot = try await service.createSession(
                repositoryID: repository,
                name: nil,
                clientID: clientID,
                idempotencyKey: UUID().uuidString
            )
        }
        return .init(sessionID: snapshot.sessionId, repository: repository, clientID: clientID, baseURL: baseURL)
    }

    @MainActor
    func bind(conversationID: Conversation.ID) {
        bind(conversationID: conversationID, coordinator: .shared)
    }

    @MainActor
    func bind(conversationID: Conversation.ID, coordinator: PiSessionCoordinator) {
        coordinator.bind(
            conversationID: conversationID,
            sessionID: sessionID,
            repository: repository,
            clientID: clientID,
            baseURL: baseURL
        )
    }
}

@MainActor
final class PiServerDomainCoordinator {
    private let profileStore: PiServerProfileStore
    private let sessionCoordinator: PiSessionCoordinator
    private let pendingMutationStore: any PiPendingMutationStoring
    private let serviceFactory: (PiServerProfile) throws -> any PiServiceProtocol
    private var service: (any PiServiceProtocol)?
    private let revocationAuthorizer: any PiOAuthAuthorizing
    private var oauthContext: (authorizer: any PiOAuthAuthorizing, discovery: PiGatewayWire.Discovery)?
    private var pendingCreation: PiPendingCreationRecord?
    private var pendingCreationStoreLoadFailed = false
    private var discovery: PiGatewayWire.Discovery?
    private var creationInFlight = false
    private var authenticationGeneration: UInt64 = 0
    private var sharedAuthenticationEpoch: UInt64?
    private var authenticationTask: Task<PiServerPresentation, Error>?
    private var credentialProvider: PiCredentialProvider?
    private var authenticatedServiceFactory: (() throws -> any PiServiceProtocol)?
    private(set) var presentation = PiServerPresentation()

    init(
        profileStore: PiServerProfileStore = .init(),
        sessionCoordinator: PiSessionCoordinator? = nil,
        pendingMutationStore: any PiPendingMutationStoring = PiPendingMutationStore(),
        revocationAuthorizer: (any PiOAuthAuthorizing)? = nil,
        serviceFactory: @escaping (PiServerProfile) throws -> any PiServiceProtocol = {
            try PiService(configuration: .init(baseURL: $0.baseURL, token: $0.token))
        }
    ) {
        self.profileStore = profileStore
        self.revocationAuthorizer = revocationAuthorizer ?? PiPasswordOAuthClient()
        self.sessionCoordinator = sessionCoordinator ?? .shared
        self.pendingMutationStore = pendingMutationStore
        self.serviceFactory = serviceFactory
        do {
            pendingCreation = try pendingMutationStore.loadCreation()
        } catch {
            pendingCreationStoreLoadFailed = true
            pendingCreation = nil
        }
    }

    func savedProfile() throws -> PiServerProfile? { try profileStore.load() }
    func hasSavedCredentials() throws -> Bool { try profileStore.hasSavedToken() }


    func connect(baseURL: URL, accessToken: String) async throws -> PiServerPresentation {
        authenticationGeneration &+= 1
        let generation = authenticationGeneration
        sharedAuthenticationEpoch = sessionCoordinator.beginAuthenticationEpoch()
        if try profileStore.load() != PiServerProfile(baseURL: baseURL, token: accessToken) {
            try await purgePreviousAuthenticatedState(generation: generation)
        }
        return try await connectAuthenticated(baseURL: baseURL, accessToken: accessToken, persistLegacyToken: true, authenticationGeneration: generation)
    }

    func authenticate(baseURL: URL, authorizer: any PiOAuthAuthorizing) async throws -> PiServerPresentation {
        authenticationGeneration &+= 1
        sharedAuthenticationEpoch = sessionCoordinator.beginAuthenticationEpoch()
        let generation = authenticationGeneration
        authenticationTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.performAuthentication(
                baseURL: baseURL,
                authorizer: authorizer,
                generation: generation
            )
        }
        authenticationTask = task
        defer {
            if authenticationGeneration == generation { authenticationTask = nil }
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performAuthentication(
        baseURL: URL,
        authorizer: any PiOAuthAuthorizing,
        generation: UInt64
    ) async throws -> PiServerPresentation {
        let discoveryService = try serviceFactory(.init(baseURL: baseURL, token: nil))
        PiAuthenticationDiagnostics.phase("discovery")
        let discovery = try await discoveryService.discover()
        try validateAuthentication(generation)
        try discovery.validate(baseURL: baseURL)
        PiAuthenticationDiagnostics.phase("discovery-validated")
        let stored = try profileStore.oauthTokens(baseURL: baseURL)
        let tokens = try await resolveTokens(
            stored: stored,
            authorizer: authorizer,
            discovery: discovery,
            baseURL: baseURL,
            generation: generation
        )
        try validateAuthentication(generation)
        try profileStore.save(baseURL: baseURL, oauthTokens: tokens)
        try await configureAuthenticatedServices(
            baseURL: baseURL,
            tokens: tokens,
            authorizer: authorizer,
            discovery: discovery,
            generation: generation
        )
        oauthContext = (authorizer, discovery)
        do {
            return try await connectAuthenticated(
                baseURL: baseURL,
                accessToken: tokens.accessToken,
                persistLegacyToken: false,
                authenticationGeneration: generation
            )
        } catch let error where PiAuthenticationRecoveryPolicy.requiresFreshSignIn(after: error) {
            try validateAuthentication(generation)
            try profileStore.removeOAuthTokens(baseURL: baseURL)
            let replacement = try await authorizer.authorize(discovery: discovery, baseURL: baseURL)
            try validateAuthentication(generation)
            try await purgePreviousAuthenticatedState(generation: generation)
            try profileStore.save(baseURL: baseURL, oauthTokens: replacement)
            try await configureAuthenticatedServices(
                baseURL: baseURL,
                tokens: replacement,
                authorizer: authorizer,
                discovery: discovery,
                generation: generation
            )
            return try await connectAuthenticated(
                baseURL: baseURL,
                accessToken: replacement.accessToken,
                persistLegacyToken: false,
                authenticationGeneration: generation
            )
        }
    }

    private func resolveTokens(
        stored: PiOAuthTokens?,
        authorizer: any PiOAuthAuthorizing,
        discovery: PiGatewayWire.Discovery,
        baseURL: URL,
        generation: UInt64
    ) async throws -> PiOAuthTokens {
        if let stored, !stored.requiresRefresh {
            return stored
        }
        if let stored, stored.canRefresh {
            do {
                let refreshed = try await authorizer.refresh(stored, discovery: discovery)
                try validateAuthentication(generation)
                return refreshed
            } catch let error where PiAuthenticationRecoveryPolicy.requiresFreshSignIn(after: error) {
                try validateAuthentication(generation)
                try profileStore.removeOAuthTokens(baseURL: baseURL)
                let replacement = try await authorizer.authorize(discovery: discovery, baseURL: baseURL)
                try validateAuthentication(generation)
                try await purgePreviousAuthenticatedState(generation: generation)
                return replacement
            }
        }
        let authorized = try await authorizer.authorize(discovery: discovery, baseURL: baseURL)
        try validateAuthentication(generation)
        try await purgePreviousAuthenticatedState(generation: generation)
        return authorized
    }

    private func connectAuthenticated(
        baseURL: URL,
        accessToken: String,
        persistLegacyToken: Bool,
        authenticationGeneration: UInt64? = nil
    ) async throws -> PiServerPresentation {
        let profile = PiServerProfile(baseURL: baseURL, token: accessToken)
        let service = if !persistLegacyToken, let authenticatedServiceFactory {
            try authenticatedServiceFactory()
        } else {
            try serviceFactory(profile)
        }
        let discovery = try await service.discover()
        if let authenticationGeneration { try validateAuthentication(authenticationGeneration) }
        let repositories = try await service.listRepositories()
        if let authenticationGeneration { try validateAuthentication(authenticationGeneration) }
        if persistLegacyToken { try profileStore.save(baseURL: baseURL, token: accessToken) }
        self.service = service
        self.discovery = discovery
        presentation = .init(
            repositories: repositories.map { .init(id: $0.id, displayName: $0.displayName) },
            sessions: [],
            selectedRepositoryID: repositories.first?.id,
            baseURL: baseURL,
            isConnected: true
        )
        if let repositoryID = presentation.selectedRepositoryID {
            let sessions = try await service.listSessions(repositoryID: repositoryID)
            if let authenticationGeneration { try validateAuthentication(authenticationGeneration) }
            presentation.sessions = sessions.map {
                .init(id: $0.sessionId, name: $0.name, messageCount: $0.messageCount, isRunning: $0.isActive)
            }
        }
        return presentation
    }

    @discardableResult
    func selectRepository(_ repositoryID: String) async throws -> PiServerPresentation {
        let generation = authenticationGeneration
        guard let service, presentation.repositories.contains(where: { $0.id == repositoryID }) else {
            throw PiServiceError.invalidResponse
        }
        let sessions = try await service.listSessions(repositoryID: repositoryID)
        try validateAuthentication(generation)
        presentation.selectedRepositoryID = repositoryID
        presentation.sessions = sessions.map {
            .init(
                id: $0.sessionId,
                name: $0.name,
                messageCount: $0.messageCount,
                isRunning: $0.isActive
            )
        }
        return presentation
    }

    func searchSessions(query: String, limit: Int = 100) async throws -> [PiSessionPresentation] {
        let generation = authenticationGeneration
        guard let service else { throw PiServiceError.invalidResponse }
        let sessions = try await service.searchSessions(
            repositoryID: presentation.selectedRepositoryID,
            query: query,
            state: nil,
            limit: limit
        )
        try validateAuthentication(generation)
        return sessions.map {
            .init(id: $0.sessionId, name: $0.name, messageCount: $0.messageCount, isRunning: $0.isActive)
        }
    }

    func createOrRestoreSession(clientID: String, resumeSessionID: String?) async throws -> PiCreatedSession {
        let generation = authenticationGeneration
        guard !pendingCreationStoreLoadFailed else { throw PiServiceError.invalidResponse }
        guard !creationInFlight else { throw PiCoordinatorError.mutationInFlight }
        creationInFlight = true
        defer { creationInFlight = false }
        guard let service,
              let repositoryID = presentation.selectedRepositoryID,
              let baseURL = presentation.baseURL
        else { throw PiServiceError.invalidResponse }

        let creation: PiPendingCreationRecord
        if let pendingCreation {
            guard pendingCreation.repositoryID == repositoryID,
                  pendingCreation.resumeSessionID == resumeSessionID,
                  pendingCreation.clientID == clientID,
                  pendingCreation.baseURL == baseURL
            else {
                throw PiCoordinatorError.mutationInFlight
            }
            guard pendingCreation.requestDigest == Self.creationDigest(pendingCreation) else {
                throw PiServiceError.invalidResponse
            }
            guard pendingCreation.expiresAt > Date() else {
                throw PiServerDomainError.creationRecoveryRequired
            }
            if pendingCreation.resumeSessionID == nil {
                throw PiServerDomainError.creationRecoveryRequired
            }
            creation = pendingCreation
        } else if let resumeSessionID {
            let current = try await service.snapshot(sessionID: resumeSessionID)
            try validateAuthentication(generation)
            guard let retention = discovery?.limits.idempotencyRetentionSeconds else {
                throw PiServiceError.invalidResponse
            }
            let draft = PiPendingCreationRecord(
                baseURL: baseURL,
                repositoryID: repositoryID,
                resumeSessionID: resumeSessionID,
                clientID: clientID,
                idempotencyKey: UUID().uuidString,
                revision: current.revision,
                requestDigest: "",
                createdAt: Date(),
                expiresAt: Date().addingTimeInterval(TimeInterval(retention))
            )
            creation = Self.withCreationDigest(draft)
            pendingCreation = creation
            try pendingMutationStore.saveCreation(creation)
        } else {
            guard let retention = discovery?.limits.idempotencyRetentionSeconds else {
                throw PiServiceError.invalidResponse
            }
            let draft = PiPendingCreationRecord(
                baseURL: baseURL,
                repositoryID: repositoryID,
                resumeSessionID: nil,
                clientID: clientID,
                idempotencyKey: UUID().uuidString,
                revision: nil,
                requestDigest: "",
                createdAt: Date(),
                expiresAt: Date().addingTimeInterval(TimeInterval(retention))
            )
            creation = Self.withCreationDigest(draft)
            pendingCreation = creation
            try pendingMutationStore.saveCreation(creation)
        }

        do {
            let snapshot: PiGatewayWire.Snapshot
            if let sessionID = creation.resumeSessionID, let revision = creation.revision {
                snapshot = try await service.restoreSession(
                    sessionID: sessionID,
                    clientID: creation.clientID,
                    context: .init(idempotencyKey: creation.idempotencyKey, revision: revision)
                )
            } else {
                snapshot = try await service.createSession(
                    repositoryID: creation.repositoryID,
                    name: nil,
                    clientID: creation.clientID,
                    idempotencyKey: creation.idempotencyKey
                )
            }
            try validateAuthentication(generation)
            try pendingMutationStore.saveCreation(nil)
            pendingCreation = nil
            return .init(
                sessionID: snapshot.sessionId,
                repository: creation.repositoryID,
                clientID: creation.clientID,
                baseURL: baseURL
            )
        } catch {
            if Self.isAmbiguous(error) {
                if creation.resumeSessionID == nil {
                    throw PiServerDomainError.creationRecoveryRequired
                }
                return try await resolveAmbiguousRestore(
                    creation,
                    service: service,
                    baseURL: baseURL,
                    generation: generation
                )
            }
            try pendingMutationStore.saveCreation(nil)
            pendingCreation = nil
            throw error
        }
    }

    @discardableResult
    func deleteSession(sessionID: String, clientID: String) async throws -> PiServerPresentation {
        let generation = authenticationGeneration
        guard let service else { throw PiServiceError.invalidResponse }
        var snapshot = try await service.snapshot(sessionID: sessionID)
        try validateAuthentication(generation)
        if snapshot.controller.clientId != clientID {
            _ = try await service.mutate(
                .takeOver,
                sessionID: sessionID,
                clientID: clientID,
                context: .init(idempotencyKey: UUID().uuidString, revision: snapshot.revision)
            )
            try validateAuthentication(generation)
            snapshot = try await service.snapshot(sessionID: sessionID)
            try validateAuthentication(generation)
            guard snapshot.controller.clientId == clientID else { throw PiServiceError.accessDenied }
        }
        let receipt = try await service.deleteSession(
            sessionID: sessionID,
            clientID: clientID,
            context: .init(idempotencyKey: UUID().uuidString, revision: snapshot.revision)
        )
        try validateAuthentication(generation)
        guard receipt.deleted else { throw PiServiceError.invalidResponse }
        presentation.sessions.removeAll { $0.id == sessionID }
        return presentation
    }

    func signOut(preservingHomePreferences: Bool = false) async throws {
        try await prepareSignOut(preservingHomePreferences: preservingHomePreferences)()
    }

    /// Prepare both namespaces before any remote operation can suspend.
    func signOut(homeClient: HomeGatewayClient, anchor: @escaping () -> ASPresentationAnchor) async throws {
        let piRevocation = prepareSignOut()
        let homeRevocation = homeClient.prepareSignOut(anchor: anchor)
        var failure: Error?
        do { try await piRevocation() } catch { failure = error }
        do { try await homeRevocation() } catch { if failure == nil { failure = error } }
        if let failure { throw failure }
    }

    private func prepareSignOut(preservingHomePreferences: Bool = false) -> @MainActor () async throws -> Void {
        PiSharingConsent.shared.revokeAll()
        authenticationGeneration &+= 1
        let credentialProvider = credentialProvider
        self.credentialProvider = nil
        authenticatedServiceFactory = nil
        sessionCoordinator.clearAuthenticatedServiceFactory()
        let authenticationTask = authenticationTask
        self.authenticationTask = nil
        authenticationTask?.cancel()
        let activeService = service
        let profile = try? profileStore.load()
        let tokens: PiOAuthTokens?
        if let profile {
            tokens = try? profileStore.oauthTokens(baseURL: profile.baseURL)
        } else {
            tokens = nil
        }
        let oauthContext = oauthContext
        service = nil
        discovery = nil
        self.oauthContext = nil
        pendingCreation = nil
        var pendingCleanupError: Error?
        do {
            try pendingMutationStore.save([:])
            try pendingMutationStore.saveCreation(nil)
            try pendingMutationStore.saveAttachmentUploads([:])
            pendingCreationStoreLoadFailed = false
        } catch {
            pendingCreationStoreLoadFailed = true
            pendingCleanupError = error
        }
        creationInFlight = false
        presentation = .init()
        let clearProviders = sessionCoordinator.prepareCredentialRevocation(preservingHomePreferences: preservingHomePreferences)
        do { try profileStore.removeSavedToken() } catch { if pendingCleanupError == nil { pendingCleanupError = error } }
        let cleanupError = pendingCleanupError
        return { [self] in
            await credentialProvider?.invalidate()
            await activeService?.cancelAllRequests()
            await clearProviders()
            var revocationError: Error?
            if let tokens {
                do {
                    if let oauthContext {
                        try await oauthContext.authorizer.revoke(tokens, discovery: oauthContext.discovery)
                    } else if let profile {
                        // A fresh account menu may never have connected. Discover without
                        // opening sign-in UI, and never send saved tokens to another origin.
                        let discoveryService = try serviceFactory(.init(baseURL: profile.baseURL, token: nil))
                        do {
                            let discovered = try await discoveryService.discover()
                            try discovered.validate(baseURL: profile.baseURL)
                            guard Self.sameOrigin(discovered.authentication.revocationEndpoint, profile.baseURL) else {
                                throw PiServiceError.unsupportedAuthentication
                            }
                            try await revocationAuthorizer.revoke(tokens, discovery: discovered)
                            await discoveryService.cancelAllRequests()
                        } catch {
                            await discoveryService.cancelAllRequests()
                            throw error
                        }
                    }
                } catch {
                    revocationError = error
                }
            }
            if let revocationError { throw revocationError }
            if let cleanupError { throw cleanupError }
        }
    }

    private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
        func port(_ url: URL) -> Int? { url.port ?? (url.scheme?.lowercased() == "https" ? 443 : 80) }
        return lhs.scheme?.lowercased() == rhs.scheme?.lowercased()
            && lhs.host?.lowercased() == rhs.host?.lowercased() && port(lhs) == port(rhs)
    }

    private func configureAuthenticatedServices(
        baseURL: URL,
        tokens: PiOAuthTokens,
        authorizer: any PiOAuthAuthorizing,
        discovery: PiGatewayWire.Discovery,
        generation: UInt64
    ) async throws {
        try validateAuthentication(generation)
        await credentialProvider?.invalidate()
        try validateAuthentication(generation)
        let fence = sessionCoordinator.authenticationFence
        guard let epoch = sharedAuthenticationEpoch else { throw CancellationError() }
        let profileStore = profileStore
        let provider = PiCredentialProvider(
            baseURL: baseURL,
            tokens: tokens,
            authorizer: authorizer,
            discovery: discovery,
            profileStore: profileStore,
            authorizationIsCurrent: { fence.isCurrent(epoch) },
            persistCredentials: { value in
                try fence.perform(epoch: epoch) { try profileStore.save(baseURL: baseURL, oauthTokens: value) }
            },
            removeCredentials: {
                try fence.perform(epoch: epoch) { try profileStore.removeOAuthTokens(baseURL: baseURL) }
            }
        )
        let serviceFactory = serviceFactory
        let factory = {
            try PiRefreshingService(
                baseURL: baseURL,
                accessToken: tokens.accessToken,
                discovery: discovery,
                credentialProvider: provider,
                serviceFactory: serviceFactory,
                authenticationFailure: { @MainActor [weak self] in
                    guard let self, self.authenticationGeneration == generation,
                          self.sharedAuthenticationEpoch == self.sessionCoordinator.authenticationEpoch else { return }
                    await self.failClosedAuthentication()
                }
            )
        }
        credentialProvider = provider
        authenticatedServiceFactory = factory
        sessionCoordinator.installAuthenticatedServiceFactory(baseURL: baseURL, credentialProvider: provider, factory: factory)
    }

    private func failClosedAuthentication() async {
        PiSharingConsent.shared.revokeAll()
        authenticationGeneration &+= 1
        authenticationTask?.cancel()
        authenticationTask = nil
        credentialProvider = nil
        authenticatedServiceFactory = nil
        service = nil
        discovery = nil
        oauthContext = nil
        creationInFlight = false
        presentation = .init()
        sessionCoordinator.clearAuthenticatedServiceFactory()
        await sessionCoordinator.revokeAllCredentialsAndState()
    }

    private func validateAuthentication(_ generation: UInt64) throws {
        guard generation == authenticationGeneration,
              sharedAuthenticationEpoch == sessionCoordinator.authenticationEpoch,
              !Task.isCancelled else {
            throw CancellationError()
        }
    }

    private func purgePreviousAuthenticatedState(generation: UInt64) async throws {
        try validateAuthentication(generation)
        await sessionCoordinator.revokeAllCredentialsAndState(advancingAuthenticationEpoch: false)
        try validateAuthentication(generation)
        sharedAuthenticationEpoch = sessionCoordinator.beginAuthenticationEpoch()
    }

    private func resolveAmbiguousRestore(
        _ creation: PiPendingCreationRecord,
        service: any PiServiceProtocol,
        baseURL: URL,
        generation: UInt64
    ) async throws -> PiCreatedSession {
        guard let sessionID = creation.resumeSessionID,
              let revision = creation.revision
        else { throw PiServerDomainError.creationRecoveryRequired }
        do {
            let lookup = try await service.mutationReceipt(
                sessionID: sessionID,
                idempotencyKey: creation.idempotencyKey,
                clientID: creation.clientID
            )
            try validateAuthentication(generation)
            switch lookup {
            case let .pending(receiptSessionID):
                guard receiptSessionID == sessionID else { throw PiServiceError.invalidResponse }
                throw PiServerDomainError.mutationPending
            case let .applied(receipt):
                guard receipt.sessionId == sessionID,
                      (200 ..< 300).contains(receipt.responseStatus)
                else { throw PiServiceError.invalidResponse }
                let snapshot = try await service.snapshot(sessionID: sessionID)
                try validateAuthentication(generation)
                guard snapshot.sessionId == sessionID,
                      snapshot.revision >= receipt.revision
                else { throw PiServiceError.invalidResponse }
                try pendingMutationStore.saveCreation(nil)
                pendingCreation = nil
                return .init(
                    sessionID: snapshot.sessionId,
                    repository: creation.repositoryID,
                    clientID: creation.clientID,
                    baseURL: baseURL
                )
            }
        } catch PiServiceError.mutationNotFound {
            let snapshot = try await service.restoreSession(
                sessionID: sessionID,
                clientID: creation.clientID,
                context: .init(idempotencyKey: creation.idempotencyKey, revision: revision)
            )
            try validateAuthentication(generation)
            try pendingMutationStore.saveCreation(nil)
            pendingCreation = nil
            return .init(
                sessionID: snapshot.sessionId,
                repository: creation.repositoryID,
                clientID: creation.clientID,
                baseURL: baseURL
            )
        }
    }

    private static func withCreationDigest(_ record: PiPendingCreationRecord) -> PiPendingCreationRecord {
        .init(
            baseURL: record.baseURL,
            repositoryID: record.repositoryID,
            resumeSessionID: record.resumeSessionID,
            clientID: record.clientID,
            idempotencyKey: record.idempotencyKey,
            revision: record.revision,
            requestDigest: creationDigest(record),
            createdAt: record.createdAt,
            expiresAt: record.expiresAt
        )
    }

    private static func creationDigest(_ record: PiPendingCreationRecord) -> String {
        struct Canonical: Encodable {
            let baseURL: URL
            let repositoryID: String
            let resumeSessionID: String?
            let clientID: String
            let idempotencyKey: String
            let revision: Int?
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(Canonical(
            baseURL: record.baseURL,
            repositoryID: record.repositoryID,
            resumeSessionID: record.resumeSessionID,
            clientID: record.clientID,
            idempotencyKey: record.idempotencyKey,
            revision: record.revision
        ))) ?? Data()
        return Data(SHA256.hash(data: data)).base64EncodedString()
    }

    private static func isAmbiguous(_ error: Error) -> Bool {
        guard let error = error as? PiServiceError else { return false }
        switch error {
        case .timedOut, .connectionLost, .networkUnavailable, .transportFailure:
            return true
        default:
            return false
        }
    }

}

enum PiAuthenticationRecoveryPolicy {
    static func requiresFreshSignIn(after error: Error) -> Bool {
        if error as? PiOAuthError == .refreshUnavailable { return true }
        if error as? PiServiceError == .authenticationRequired { return true }
        return false
    }
}
