@testable import FlowDown
import Foundation
import Testing

@Suite(.serialized)
struct PiSessionCoordinatorTests {
    @Test
    @MainActor
    func `normal stream termination refetches an authoritative snapshot before reconnecting`() async throws {
        let connectedStream = ControlledEventStream()
        let service = PiServiceSpy(
            snapshots: [snapshot(title: "First", message: "old"), snapshot(title: "Second", message: "new")],
            streams: [finishedStream(), connectedStream.stream]
        )
        var rendered: [PiConversationState] = []
        let (coordinator, defaults) = makeCoordinator(service: service) { _, state in rendered.append(state) }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        bind(coordinator, conversationID: "conversation", sessionID: "session")
        try await waitUntil {
            service.stateCallCount == 2 && coordinator.viewState(for: "conversation")?.conversation.title == "Second"
        }

        #expect(rendered.map(\.title) == ["First", "Second"])
        #expect(rendered.last?.messages.first?.text == "new")
    }

    @Test
    @MainActor
    func `reconnect backoff resets only after receiving a stream event`() async throws {
        let connectedStream = ControlledEventStream()
        let initialState = snapshot(title: "One", message: "one")
        let service = PiServiceSpy(
            snapshots: [initialState, snapshot(title: "Two", message: "two"), snapshot(title: "Three", message: "three")],
            streams: [finiteStream([.initial(state: initialState, clientID: "ios-client", controllerClientID: nil, role: .viewer)]), finishedStream(), connectedStream.stream]
        )
        var delayAttempts: [Int] = []
        let (coordinator, defaults) = makeCoordinator(
            service: service,
            reconnectDelay: { delayAttempts.append($0) },
            render: { _, _ in }
        )
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        bind(coordinator, conversationID: "conversation", sessionID: "session")
        try await waitUntil { service.stateCallCount == 3 }

        #expect(delayAttempts == [1, 2])
    }

    @Test
    @MainActor
    func `failed stream termination also refetches authoritative state`() async throws {
        let connectedStream = ControlledEventStream()
        let service = PiServiceSpy(
            snapshots: [snapshot(title: "Before failure", message: "old"), snapshot(title: "Recovered", message: "new")],
            streams: [failedStream(), connectedStream.stream]
        )
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        bind(coordinator, conversationID: "conversation", sessionID: "session")
        try await waitUntil {
            service.stateCallCount == 2 && coordinator.viewState(for: "conversation")?.conversation.title == "Recovered"
        }

        #expect(coordinator.viewState(for: "conversation")?.conversation.messages.first?.text == "new")
        #expect(coordinator.viewState(for: "conversation")?.connection == .connected)
    }

    @Test
    @MainActor
    func `switching sessions ignores a cancelled noncooperative state response`() async throws {
        let service = SuspendedPiService()
        var renderedConversationIDs: [String] = []
        let (coordinator, defaults) = makeCoordinator(service: service) { conversationID, _ in
            renderedConversationIDs.append(conversationID)
        }
        defer {
            coordinator.unbind(conversationID: "a")
            coordinator.unbind(conversationID: "b")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        bind(coordinator, conversationID: "a", sessionID: "session-a")
        try await waitUntil { service.pendingSessionIDs.contains("session-a") }
        bind(coordinator, conversationID: "b", sessionID: "session-b")
        try await waitUntil { service.pendingSessionIDs.contains("session-b") }

        service.resume(sessionID: "session-a", with: snapshot(title: "Stale", message: "stale", sessionID: "session-a"))
        await Task.yield()
        #expect(!renderedConversationIDs.contains("a"))
        #expect(coordinator.viewState(for: "a")?.conversation.title == nil)

        service.resume(sessionID: "session-b", with: snapshot(title: "Current", message: "current", sessionID: "session-b"))
        try await waitUntil { renderedConversationIDs.contains("b") }
        #expect(coordinator.viewState(for: "b")?.conversation.title == "Current")
    }

    @Test
    @MainActor
    func `unbinding ignores a cancelled noncooperative state response`() async throws {
        let service = SuspendedPiService()
        var renderedConversationIDs: [String] = []
        let (coordinator, defaults) = makeCoordinator(service: service) { conversationID, _ in
            renderedConversationIDs.append(conversationID)
        }
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        bind(coordinator, conversationID: "conversation", sessionID: "session")
        try await waitUntil { service.pendingSessionIDs.contains("session") }
        coordinator.unbind(conversationID: "conversation")
        service.resume(sessionID: "session", with: snapshot(title: "Stale", message: "stale"))
        await Task.yield()

        #expect(coordinator.binding(for: "conversation") == nil)
        #expect(coordinator.viewState(for: "conversation") == nil)
        #expect(renderedConversationIDs.isEmpty)
    }

    @Test
    @MainActor
    func `unbind all clears every persisted binding`() {
        let service = PiServiceSpy(snapshots: [snapshot(title: "Unused", message: "unused")], streams: [pendingStream()])
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }

        bind(coordinator, conversationID: "a", sessionID: "session-a")
        bind(coordinator, conversationID: "b", sessionID: "session-b")
        coordinator.unbindAll()

        #expect(coordinator.binding(for: "a") == nil)
        #expect(coordinator.binding(for: "b") == nil)
    }

    @Test
    @MainActor
    func `viewer cannot send or abort through coordinator`() async throws {
        let stream = ControlledEventStream()
        let service = PiServiceSpy(
            snapshots: [snapshot(title: "Viewer", message: "history", streaming: true)],
            streams: [stream.stream]
        )
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        bind(coordinator, conversationID: "conversation", sessionID: "session")
        try await waitUntil { coordinator.viewState(for: "conversation")?.connection == .connected }

        await #expect(throws: PiCoordinatorError.viewer) {
            try await coordinator.send(text: "unsafe", delivery: .steer, conversationID: "conversation")
        }
        await #expect(throws: PiCoordinatorError.viewer) {
            try await coordinator.abort(conversationID: "conversation")
        }
        #expect(service.commands.isEmpty)
    }

    @Test
    @MainActor
    func `binding preserves create client identity for events and commands`() async throws {
        let stream = ControlledEventStream()
        let state = snapshot(title: "Identity", message: "history")
        let service = PiServiceSpy(snapshots: [state], streams: [stream.stream])
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "create-client")
        try await waitUntil { service.eventClientIDs == ["create-client"] }
        stream.yield(.initial(
            state: state,
            clientID: "create-client",
            controllerClientID: "create-client",
            role: .controller
        ))
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.role == .controller }
        try await coordinator.send(text: "hello", delivery: nil, conversationID: "conversation")

        #expect(coordinator.binding(for: "conversation")?.clientID == "create-client")
        #expect(coordinator.binding(for: "conversation")?.baseURL == URL(string: "https://pi.example.test"))
        #expect(service.commands == [.prompt(clientID: "create-client", text: "hello", delivery: nil)])
    }

    @Test
    @MainActor
    func `binding fails closed when active server profile differs`() async throws {
        let service = PiServiceSpy(snapshots: [snapshot(title: "Wrong", message: "wrong")], streams: [pendingStream()])
        let (coordinator, defaults) = makeCoordinator(
            service: service,
            reconnectDelay: { _ in try await Task.sleep(for: .seconds(60)) },
            render: { _, _ in }
        )
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        bind(
            coordinator,
            conversationID: "conversation",
            sessionID: "session",
            baseURL: URL(string: "https://other.example.test")!
        )
        try await waitUntil {
            guard let connection = coordinator.viewState(for: "conversation")?.connection else { return false }
            if case .offline = connection { return true }
            return false
        }

        #expect(service.stateCallCount == 0)
    }

    @MainActor
    private func makeCoordinator(
        service: any PiServiceProtocol,
        reconnectDelay: @escaping (Int) async throws -> Void = { _ in },
        render: @escaping (String, PiConversationState) -> Void
    ) -> (PiSessionCoordinator, UserDefaults) {
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defaults.removePersistentDomain(forName: defaultsSuite)
        let profile = PiServerProfile(baseURL: URL(string: "https://pi.example.test")!, token: nil)
        let coordinator = PiSessionCoordinator(
            defaults: defaults,
            profileProvider: { profile },
            serviceFactory: { _ in service },
            reconnectDelay: reconnectDelay,
            renderOverride: render
        )
        return (coordinator, defaults)
    }

    @MainActor
    private func bind(
        _ coordinator: PiSessionCoordinator,
        conversationID: String,
        sessionID: String,
        clientID: String = "ios-client",
        baseURL: URL = URL(string: "https://pi.example.test")!
    ) {
        coordinator.bind(
            conversationID: conversationID,
            sessionID: sessionID,
            repository: "/repo",
            clientID: clientID,
            baseURL: baseURL
        )
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw NSError(
            domain: "PiSessionCoordinatorTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for coordinator state."]
        )
    }

    private var defaultsSuite: String { "PiSessionCoordinatorTests" }
}

private func snapshot(
    title: String,
    message: String,
    sessionID: String = "session",
    streaming: Bool = false
) -> PiSessionState {
    PiSessionState(
        sessionId: sessionID,
        cwd: "/repo",
        sessionFile: nil,
        sessionName: title,
        isStreaming: streaming,
        model: nil,
        thinkingLevel: "off",
        steeringMode: .all,
        followUpMode: .all,
        stats: nil,
        contextUsage: nil,
        messages: [.object(["id": .string("message"), "role": .string("assistant"), "content": .string(message)])]
    )
}

private func finishedStream() -> AsyncThrowingStream<PiServerEvent, Error> {
    AsyncThrowingStream { $0.finish() }
}

private func failedStream() -> AsyncThrowingStream<PiServerEvent, Error> {
    AsyncThrowingStream { $0.finish(throwing: PiServiceError.connectionLost) }
}

private func finiteStream(_ events: [PiServerEvent]) -> AsyncThrowingStream<PiServerEvent, Error> {
    AsyncThrowingStream { continuation in
        events.forEach { continuation.yield($0) }
        continuation.finish()
    }
}

private func pendingStream() -> AsyncThrowingStream<PiServerEvent, Error> {
    AsyncThrowingStream { _ in }
}

private final class ControlledEventStream: @unchecked Sendable {
    let stream: AsyncThrowingStream<PiServerEvent, Error>
    private let continuation: AsyncThrowingStream<PiServerEvent, Error>.Continuation

    init() {
        var continuation: AsyncThrowingStream<PiServerEvent, Error>.Continuation!
        stream = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    func yield(_ event: PiServerEvent) {
        continuation.yield(event)
    }
}

private final class PiServiceSpy: PiServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [PiSessionState]
    private var streams: [AsyncThrowingStream<PiServerEvent, Error>]
    private var stateCalls = 0
    private var sentCommands: [PiCommand] = []
    private var connectedClientIDs: [String] = []

    init(snapshots: [PiSessionState], streams: [AsyncThrowingStream<PiServerEvent, Error>]) {
        self.snapshots = snapshots
        self.streams = streams
    }

    var stateCallCount: Int { lock.withLock { stateCalls } }
    var commands: [PiCommand] { lock.withLock { sentCommands } }
    var eventClientIDs: [String] { lock.withLock { connectedClientIDs } }

    func health() async throws {}
    func listModels() async throws -> [PiModel] { [] }
    func listRepositories() async throws -> [String] { [] }
    func listSessions(repository _: String?) async throws -> [PiSessionSummary] { [] }
    func createSession(repository _: String?, resumePath _: String?, clientID _: String) async throws -> String { "session" }

    func state(sessionID _: String) async throws -> PiSessionState {
        lock.withLock {
            let index = min(stateCalls, snapshots.count - 1)
            stateCalls += 1
            return snapshots[index]
        }
    }

    func events(sessionID _: String, clientID: String) -> AsyncThrowingStream<PiServerEvent, Error> {
        lock.withLock {
            connectedClientIDs.append(clientID)
            return streams.isEmpty ? pendingStream() : streams.removeFirst()
        }
    }

    func send(_ command: PiCommand, sessionID _: String) async throws {
        lock.withLock { sentCommands.append(command) }
    }

    func takeOver(sessionID _: String, clientID _: String) async throws {}
    func release(sessionID _: String, clientID _: String) async throws {}
}

private final class SuspendedPiService: PiServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let eventStream = ControlledEventStream()
    private var continuations: [String: CheckedContinuation<PiSessionState, Error>] = [:]

    var pendingSessionIDs: Set<String> { lock.withLock { Set(continuations.keys) } }

    func resume(sessionID: String, with state: PiSessionState) {
        lock.withLock { continuations.removeValue(forKey: sessionID) }?.resume(returning: state)
    }

    func health() async throws {}
    func listModels() async throws -> [PiModel] { [] }
    func listRepositories() async throws -> [String] { [] }
    func listSessions(repository _: String?) async throws -> [PiSessionSummary] { [] }
    func createSession(repository _: String?, resumePath _: String?, clientID _: String) async throws -> String { "session" }

    func state(sessionID: String) async throws -> PiSessionState {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { continuations[sessionID] = continuation }
        }
    }

    func events(sessionID _: String, clientID _: String) -> AsyncThrowingStream<PiServerEvent, Error> {
        eventStream.stream
    }

    func send(_: PiCommand, sessionID _: String) async throws {}
    func takeOver(sessionID _: String, clientID _: String) async throws {}
    func release(sessionID _: String, clientID _: String) async throws {}
}
