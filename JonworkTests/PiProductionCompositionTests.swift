@testable import Jonwork
import Combine
import Foundation
import OrderedCollections
import Storage
import Testing

@Suite(.serialized)
struct PiProductionCompositionTests {
    @Test
    func `production surface allows only bound Jonwork conversations`() {
        #expect(!JonworkSurfacePolicy.productionAllowsLegacyConversations)
        #expect(!JonworkSurfacePolicy.productionIncludesLegacyMenuCommands)
        #expect(!JonworkSurfacePolicy.productionAllowsLegacyProviderNetworking)
        #expect(!JonworkSurfacePolicy.permitsConversation(
            hasJonworkBinding: false,
            allowsLegacyConversations: JonworkSurfacePolicy.productionAllowsLegacyConversations
        ))
        #expect(JonworkSurfacePolicy.permitsConversation(
            hasJonworkBinding: true,
            allowsLegacyConversations: JonworkSurfacePolicy.productionAllowsLegacyConversations
        ))
        #expect(!JonworkSurfacePolicy.shouldCreateInitialConversation(
            isConversationListEmpty: true,
            allowsLegacyConversations: false
        ))
        #expect(!JonworkSurfacePolicy.permitsLegacyConversationActions(
            hasJonworkBinding: true,
            allowsLegacyConversations: true
        ))
    }

    @Test
    @MainActor
    func `production conversation list never creates an implicit local conversation`() async throws {
        try await JonworkTestContext.shared.ensureBootstrappedEnvironment()
        ConversationManager.shared.eraseAll()

        let selectionView = ConversationSelectionView(allowsLegacyConversations: false)
        selectionView.updateDataSource()

        #expect(ConversationManager.shared.conversations.value.isEmpty)
        #expect(selectionView.dataSource.snapshot().numberOfItems == 0)

        let onlyConversation = sdb.conversationMake { $0.update(\.title, to: "Temporary") }
        ConversationManager.shared.scanAll()
        selectionView.updateDataSource()
        #expect(selectionView.dataSource.snapshot().numberOfItems == 1)

        ConversationManager.shared.deleteConversation(identifier: onlyConversation.id)
        selectionView.updateDataSource()

        #expect(ConversationManager.shared.conversations.value.isEmpty)
        #expect(selectionView.dataSource.snapshot().numberOfItems == 0)
    }

    @Test
    @MainActor
    func `bound Jonwork conversation exposes no legacy menus providers models or tools`() async throws {
        try await JonworkTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake { $0.update(\.title, to: "Bound Jonwork") }
        ConversationManager.shared.scanAll()
        let baseURL = try #require(URL(string: "https://pi.example.test"))
        PiSessionCoordinator.shared.bind(
            conversationID: conversation.id,
            sessionID: "session",
            repository: "/repo",
            clientID: "client",
            baseURL: baseURL
        )
        defer {
            PiSessionCoordinator.shared.unbind(conversationID: conversation.id)
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
        }

        let view = ChatView(allowsLegacyConversations: false)
        view.use(conversation: conversation.id)

        var modelCompletionCalled = false
        var toolReloadCalled = false
        #expect(view.onRichEditorRequestCurrentModelName() == nil)
        #expect(view.onRichEditorRequestCurrentModelIdentifier() == nil)
        #expect(view.onRichEditorRequestObjectForRestore() == nil)
        #expect(view.onRichEditorBuildModelSelectionMenu { modelCompletionCalled = true }.isEmpty)
        #expect(view.onRichEditorBuildAlternativeModelMenu().isEmpty)
        #expect(view.onRichEditorBuildAlternativeToolsMenu(isEnabled: true) { _ in
            toolReloadCalled = true
        }.isEmpty)
        #expect(!view.onRichEditorCheckIfModelSupportsToolCall("unused"))
        #expect(!modelCompletionCalled)
        #expect(!toolReloadCalled)

        #expect(view.title.buildMenu() == nil)
        #expect(view.title.menuButton.isHidden)

        let cell = ConversationSelectionView.Cell(style: .default, reuseIdentifier: nil)
        cell.use(conversation, allowsLegacyConversations: false)
        let interaction = UIContextMenuInteraction(delegate: cell)
        #expect(cell.contextMenuInteraction(
            interaction,
            configurationForMenuAtLocation: .zero
        ) == nil)

        #expect(ConversationManager.shared.menu(
            forConversation: conversation.id,
            view: view,
            allowsLegacyConversations: false
        ) == nil)
    }

    @Test
    @MainActor
    func `production surface refuses unbound editor and provider actions`() async throws {
        try await JonworkTestContext.shared.ensureBootstrappedEnvironment()
        let view = ChatView(allowsLegacyConversations: false)
        let unboundConversationID = "unbound-\(UUID().uuidString)"

        view.use(conversation: unboundConversationID)

        #expect(view.conversationIdentifier == nil)
        #expect(!view.jonworkUnavailableView.isHidden)
        #expect(view.editor.isHidden)
        #expect(!view.editor.isUserInteractionEnabled)
        #expect(view.onRichEditorRequestCurrentModelIdentifier() == nil)
        #expect(view.onRichEditorBuildModelSelectionMenu {}.isEmpty)
        #expect(view.onRichEditorBuildAlternativeModelMenu().isEmpty)
        #expect(view.onRichEditorBuildAlternativeToolsMenu(isEnabled: true) { _ in }.isEmpty)

        var accepted: Bool?
        view.onRichEditorSubmit(object: .init(text: "must not send")) {
            accepted = $0
        }
        #expect(accepted == false)
    }

    @Test
    @MainActor
    func `Jonwork conversation hides legacy provider and attachment controls`() {
        let editor = RichEditorView()

        editor.setJonworkConversation(true)

        #expect(editor.quickSettingBar.isOpen == false)
        #expect(editor.inputEditor.bossButton.isHidden)
        #expect(editor.inputEditor.moreButton.isHidden)
        #expect(editor.quickSettingBar.browsingToggle.isOn == false)
        #expect(editor.quickSettingBar.toolsToggle.isOn == false)

        editor.setJonworkConversation(false)

        #expect(editor.quickSettingBar.isOpen)
        #expect(!editor.inputEditor.bossButton.isHidden)
        #expect(!editor.inputEditor.moreButton.isHidden)
    }

    @Test
    @MainActor
    func `streaming controller gets a direct stop action`() {
        let statusView = PiSessionStatusView()
        var state = PiConversationState()
        state.role = .controller
        state.isStreaming = true

        statusView.update(.init(conversation: state, connection: .connected))

        #expect(!statusView.stopButton.isHidden)
        #expect(statusView.stopButton.accessibilityLabel == String(localized: "Stop Response"))

        state.role = .viewer
        statusView.update(.init(conversation: state, connection: .connected))
        #expect(statusView.stopButton.isHidden)
    }

    @Test
    @MainActor
    func `header actions expose offline recovery without a persistent status label`() {
        let statusView = PiSessionStatusView()
        let error = "The connection was interrupted."

        statusView.update(.init(conversation: .init(), connection: .offline(error)))

        #expect(!statusView.isAccessibilityElement)
        #expect(statusView.actionButton.accessibilityHint == error)
        #expect(statusView.actionButton.isEnabled)
        #expect(statusView.actionButton.isAccessibilityElement)
        #expect(statusView.stopButton.isAccessibilityElement)
        statusView.update(.init(conversation: .init(), connection: .connected))
        #expect(statusView.actionButton.accessibilityHint == nil)
        #expect(statusView.actionButton.isEnabled)
    }

    @Test
    @MainActor
    func `create-session result binds the same client and server identity`() async throws {
        let service = ProductionPiServiceSpy(snapshot: makeSnapshot(text: "ready", sessionID: "created-session"))
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let baseURL = try #require(URL(string: "https://pi.example.test"))
        let coordinator = PiSessionCoordinator(
            defaults: defaults,
            profileProvider: { PiServerProfile(baseURL: baseURL, token: nil) },
            serviceFactory: { _ in service },
            reconnectDelay: { _ in },
            renderOverride: { _, _ in }
        )
        defer { coordinator.unbind(conversationID: "conversation") }

        let created = try await PiCreatedSession.create(
            service: service,
            repository: "/repo",
            resumeSessionID: nil,
            clientID: "created-client",
            baseURL: baseURL
        )
        created.bind(conversationID: "conversation", coordinator: coordinator)
        try await waitUntil { service.eventClientIDs == ["created-client"] }

        #expect(service.createdClientIDs == ["created-client"])
        #expect(coordinator.binding(for: "conversation") == .init(
            sessionID: "created-session",
            repository: "/repo",
            clientID: "created-client",
            baseURL: baseURL
        ))
    }

    @Test
    @MainActor
    func `stream bursts coalesce into one indexed transient-row update`() async throws {
        try await JonworkTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake { $0.update(\.title, to: "Pi coalescing") }
        ConversationManager.shared.scanAll()
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        let stream = ProductionEventStream()
        let service = ProductionPiServiceSpy(snapshot: makeSnapshot(text: ""), stream: stream.stream)
        let defaults = makeDefaults()
        let baseURL = try #require(URL(string: "https://pi.example.test"))
        let coordinator = PiSessionCoordinator(
            defaults: defaults,
            profileProvider: { PiServerProfile(baseURL: baseURL, token: nil) },
            serviceFactory: { _ in service },
            reconnectDelay: { _ in }
        )
        defer {
            coordinator.unbind(conversationID: conversation.id)
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        var emissions = 0
        let cancellable = session.messagesDidChange.dropFirst().sink { _ in emissions += 1 }
        _ = cancellable

        coordinator.bind(
            conversationID: conversation.id,
            sessionID: "session",
            repository: "/repo",
            clientID: "client",
            baseURL: baseURL
        )
        try await waitUntil { service.eventClientIDs == ["client"] }
        stream.yield(productionEvent(
            id: 1,
            type: "operation.accepted",
            data: ["operationId": "operation", "command": "prompt", "retryOfOperationId": NSNull()]
        ))
        stream.yield(productionEvent(
            id: 2,
            type: "turn.started",
            data: ["operationId": "operation", "turnId": "turn"]
        ))
        stream.yield(productionEvent(
            id: 3,
            type: "assistant.message.started",
            data: ["operationId": "operation", "turnId": "turn", "messageId": "message"]
        ))
        stream.yield(assistantTextDelta(id: 4, text: "one"))
        try await waitUntil { session.messages.contains { $0.document == "one" } }
        let originalID = try #require(session.messages.first { $0.document == "one" }?.objectId)
        emissions = 0

        stream.yield(assistantTextDelta(id: 5, text: "two"))
        stream.yield(assistantTextDelta(id: 6, text: "three"))
        stream.yield(assistantTextDelta(id: 7, text: "final"))
        try await waitUntil { session.message(for: originalID)?.document == "onetwothreefinal" }

        #expect(session.messages.filter { $0.objectId == originalID }.count == 1)
        #expect(session.messages.filter { $0.document == "onetwothreefinal" }.count == 1)
        #expect(emissions == 1)
        #expect(sdb.listMessages(within: conversation.id).allSatisfy { $0.objectId != originalID })
    }

    @Test
    @MainActor
    func `legacy persisted Pi row is deleted from database during transient migration`() async throws {
        try await JonworkTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake { $0.update(\.title, to: "Pi migration") }
        ConversationManager.shared.scanAll()
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        let legacy = session.appendNewMessage(role: .assistant) {
            $0.update(\.document, to: "legacy")
            $0.update(\.metadata, to: Data(#"{"remoteID":"message"}"#.utf8))
        }
        session.save()
        let service = ProductionPiServiceSpy(snapshot: makeSnapshot(text: "transient"))
        let defaults = makeDefaults()
        let baseURL = try #require(URL(string: "https://pi.example.test"))
        let coordinator = PiSessionCoordinator(
            defaults: defaults,
            profileProvider: { PiServerProfile(baseURL: baseURL, token: nil) },
            serviceFactory: { _ in service },
            reconnectDelay: { _ in }
        )
        defer {
            coordinator.unbind(conversationID: conversation.id)
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        coordinator.bind(
            conversationID: conversation.id,
            sessionID: "session",
            repository: "/repo",
            clientID: "client",
            baseURL: baseURL
        )
        try await waitUntil { session.messages.contains { $0.document == "transient" } }

        #expect(!sdb.listMessages(within: conversation.id).contains { $0.objectId == legacy.objectId })
        #expect(session.messages.contains { $0.document == "transient" && session.isTransientMessage($0.objectId) })
    }

    @Test
    @MainActor
    func `conversation-manager erase-all clears production Pi bindings before storage`() async throws {
        try await JonworkTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake { $0.update(\.title, to: "Pi erase all") }
        ConversationManager.shared.scanAll()
        PiSessionCoordinator.shared.bind(
            conversationID: conversation.id,
            sessionID: "session",
            repository: "/repo",
            clientID: "client",
            baseURL: try #require(URL(string: "https://pi.example.test"))
        )

        ConversationManager.shared.eraseAll()

        #expect(PiSessionCoordinator.shared.binding(for: conversation.id) == nil)
        #expect(sdb.conversationWith(identifier: conversation.id) == nil)
        #expect(ConversationManager.shared.conversations.value.isEmpty)
    }

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defaults.removePersistentDomain(forName: defaultsSuite)
        return defaults
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw ProductionPiTestError.timedOut
    }

    private var defaultsSuite: String { "PiProductionCompositionTests" }
}

private func makeSnapshot(text: String, sessionID: String = "session") -> PiGatewayWire.Snapshot {
    PiGatewayWire.Snapshot(
        contract: PiGatewayWire.contract,
        sessionId: sessionID,
        repositoryId: "/repo",
        revision: 1,
        lastEventId: "0",
        lifecycle: .idle,
        runtime: .running,
        run: .init(status: .idle, operationId: nil),
        controller: .init(clientId: nil, leaseExpiresAt: nil),
        configuration: .init(model: nil, thinkingLevel: .off),
        messages: text.isEmpty ? [] : [.init(
            id: "message",
            role: .assistant,
            status: .completed,
            content: [.init(type: .text, text: text, toolCallId: nil, attachmentId: nil)]
        )],
        attachments: []
    )
}

private func assistantTextDelta(id: Int, text: String) -> PiGatewayWire.Event {
    productionEvent(
        id: id,
        type: "assistant.text.delta",
        data: ["operationId": "operation", "turnId": "turn", "messageId": "message", "delta": text]
    )
}

private func productionEvent(id: Int, type: String, data: [String: Any]) -> PiGatewayWire.Event {
    let object: [String: Any] = [
        "contract": PiGatewayWire.contract,
        "id": String(id),
        "sessionId": "session",
        "sessionRevision": 1,
        "occurredAt": "2026-10-13T08:00:00.000Z",
        "type": type,
        "data": data,
    ]
    let encoded = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    return try! JSONDecoder.piGateway.decode(PiGatewayWire.Event.self, from: encoded)
}

private func productionDiscovery() -> PiGatewayWire.Discovery {
    .init(
        contract: PiGatewayWire.contract,
        apiVersion: "1.0",
        compatibility: .init(minimumApiVersion: "1.0", maximumApiVersion: "1.0"),
        authentication: .init(
            type: "oauth2_authorization_code",
            clientId: "pi-ios",
            authorizationEndpoint: URL(string: "https://pi.example.test/authorize")!,
            tokenEndpoint: URL(string: "https://pi.example.test/token")!,
            revocationEndpoint: URL(string: "https://pi.example.test/revoke")!,
            scopes: ["pi.gateway"],
            pkceMethods: ["S256"],
            accessTokenLifetimeSeconds: 900,
            refreshTokenRotation: "required"
        ),
        capabilities: .init(
            repositories: true, models: true, thinking: true, sessions: true,
            sessionSearch: true, sessionDelete: true, commands: true,
            sse: true, authoritativeSnapshot: true, eventIds: true, replay: true, idempotency: true,
            singleWriter: true, takeover: true, release: true, abort: true, retry: true,
            attachments: .init(
                images: true, files: false,
                sources: [.photoLibrary, .camera, .filePicker],
                mediaTypes: ["image/png"],
                modelCompatibilityField: "attachments.supported"
            )
        ),
        limits: .init(
            readTimeoutMs: 1_000, mutationTimeoutMs: 1_000, sseConnectTimeoutMs: 1_000,
            replayRetentionEvents: 100, replayRetentionSeconds: 100,
            idempotencyRetentionSeconds: 86_400, attachmentMaxBytes: 1_000_000,
            attachmentTotalBytes: 2_000_000, attachmentsPerPrompt: 4, attachmentUploadTimeoutMs: 1_000,
            attachmentDownloadTimeoutMs: 1_000, attachmentMediaTypes: ["image/png"],
            attachmentDigestAlgorithm: "sha-256"
        )
    )
}

private final class ProductionEventStream: @unchecked Sendable {
    let stream: AsyncThrowingStream<PiGatewayWire.Event, Error>
    private let continuation: AsyncThrowingStream<PiGatewayWire.Event, Error>.Continuation

    init() {
        var continuation: AsyncThrowingStream<PiGatewayWire.Event, Error>.Continuation!
        stream = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    func yield(_ event: PiGatewayWire.Event) { continuation.yield(event) }
}

private final class ProductionPiServiceSpy: PiServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let snapshotValue: PiGatewayWire.Snapshot
    private let stream: AsyncThrowingStream<PiGatewayWire.Event, Error>
    private var createdClients: [String] = []
    private var eventClients: [String] = []

    init(snapshot: PiGatewayWire.Snapshot, stream: AsyncThrowingStream<PiGatewayWire.Event, Error> = AsyncThrowingStream { _ in }) {
        snapshotValue = snapshot
        self.stream = stream
    }

    var createdClientIDs: [String] { lock.withLock { createdClients } }
    var eventClientIDs: [String] { lock.withLock { eventClients } }
    func discover() async throws -> PiGatewayWire.Discovery { productionDiscovery() }
    func listModels() async throws -> [PiGatewayWire.Model] { [] }
    func createSession(
        repositoryID _: String,
        name _: String?,
        clientID: String,
        idempotencyKey _: String
    ) async throws -> PiGatewayWire.Snapshot {
        lock.withLock { createdClients.append(clientID) }
        return snapshotValue
    }
    func snapshot(sessionID _: String) async throws -> PiGatewayWire.Snapshot { snapshotValue }
    func events(
        sessionID _: String,
        clientID: String,
        afterEventID _: String
    ) -> AsyncThrowingStream<PiGatewayWire.Event, Error> {
        lock.withLock { eventClients.append(clientID) }
        return stream
    }
}

private enum ProductionPiTestError: Error { case timedOut }
