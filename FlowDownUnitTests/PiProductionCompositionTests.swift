@testable import FlowDown
import Combine
import Foundation
import OrderedCollections
import Storage
import Testing

@Suite(.serialized)
struct PiProductionCompositionTests {
    @Test
    @MainActor
    func `create-session result binds the same client and server identity`() async throws {
        let service = ProductionPiServiceSpy(snapshot: makeSnapshot(text: "ready"))
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
            resumePath: "/resume.jsonl",
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
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake { $0.update(\.title, to: "Pi coalescing") }
        ConversationManager.shared.scanAll()
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        let stream = ProductionEventStream()
        let service = ProductionPiServiceSpy(snapshot: makeSnapshot(text: "one"), stream: stream.stream)
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
        try await waitUntil { session.messages.contains { $0.document == "one" } }
        let originalID = try #require(session.messages.first { $0.document == "one" }?.objectId)
        emissions = 0

        stream.yield(try agentMessageUpdate(text: "two"))
        stream.yield(try agentMessageUpdate(text: "three"))
        stream.yield(try agentMessageUpdate(text: "final"))
        try await waitUntil { session.message(for: originalID)?.document == "final" }

        #expect(session.messages.filter { $0.objectId == originalID }.count == 1)
        #expect(session.messages.filter { $0.document == "final" }.count == 1)
        #expect(emissions == 1)
        #expect(sdb.listMessages(within: conversation.id).allSatisfy { $0.objectId != originalID })
    }

    @Test
    @MainActor
    func `legacy persisted Pi row is deleted from database during transient migration`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
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
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
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

private func makeSnapshot(text: String) -> PiSessionState {
    PiSessionState(
        sessionId: "session",
        cwd: "/repo",
        sessionFile: nil,
        sessionName: "Pi",
        isStreaming: true,
        model: nil,
        thinkingLevel: "off",
        steeringMode: .all,
        followUpMode: .all,
        stats: nil,
        contextUsage: nil,
        messages: [.object(["id": .string("message"), "role": .string("assistant"), "content": .string(text)])]
    )
}

private func agentMessageUpdate(text: String) throws -> PiServerEvent {
    let data = Data(#"{"type":"message_update","message":{"id":"message","role":"assistant","content":"\#(text)"}}"#.utf8)
    return .agent(try JSONDecoder().decode(PiAgentEvent.self, from: data))
}

private final class ProductionEventStream: @unchecked Sendable {
    let stream: AsyncThrowingStream<PiServerEvent, Error>
    private let continuation: AsyncThrowingStream<PiServerEvent, Error>.Continuation

    init() {
        var continuation: AsyncThrowingStream<PiServerEvent, Error>.Continuation!
        stream = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    func yield(_ event: PiServerEvent) { continuation.yield(event) }
}

private final class ProductionPiServiceSpy: PiServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let snapshot: PiSessionState
    private let stream: AsyncThrowingStream<PiServerEvent, Error>
    private var createdClients: [String] = []
    private var eventClients: [String] = []

    init(snapshot: PiSessionState, stream: AsyncThrowingStream<PiServerEvent, Error> = AsyncThrowingStream { _ in }) {
        self.snapshot = snapshot
        self.stream = stream
    }

    var createdClientIDs: [String] { lock.withLock { createdClients } }
    var eventClientIDs: [String] { lock.withLock { eventClients } }
    func health() async throws {}
    func listModels() async throws -> [PiModel] { [] }
    func listRepositories() async throws -> [String] { [] }
    func listSessions(repository _: String?) async throws -> [PiSessionSummary] { [] }
    func createSession(repository _: String?, resumePath _: String?, clientID: String) async throws -> String {
        lock.withLock { createdClients.append(clientID) }
        return "created-session"
    }
    func state(sessionID _: String) async throws -> PiSessionState { snapshot }
    func events(sessionID _: String, clientID: String) -> AsyncThrowingStream<PiServerEvent, Error> {
        lock.withLock { eventClients.append(clientID) }
        return stream
    }
    func send(_: PiCommand, sessionID _: String) async throws {}
    func takeOver(sessionID _: String, clientID _: String) async throws {}
    func release(sessionID _: String, clientID _: String) async throws {}
}

private enum ProductionPiTestError: Error { case timedOut }
