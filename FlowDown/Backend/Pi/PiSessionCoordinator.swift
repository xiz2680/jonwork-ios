import Foundation
import Storage

extension Notification.Name {
    static let piSessionDidChange = Notification.Name("PiSessionDidChange")
}

@MainActor
final class PiSessionCoordinator {
    static let shared = PiSessionCoordinator()

    struct Binding: Codable, Equatable, Sendable {
        let sessionID: String
        let repository: String
        let clientID: String
        let baseURL: URL
    }

    enum ConnectionPhase: Equatable, Sendable {
        case connecting
        case connected
        case offline(String)
    }

    struct ViewState: Equatable, Sendable {
        let conversation: PiConversationState
        let connection: ConnectionPhase
    }

    private let bindingsKey = "Pi.Session.Bindings"
    private let defaults: UserDefaults
    private let profileProvider: () throws -> PiServerProfile?
    private let serviceFactory: (PiServerProfile) throws -> any PiServiceProtocol
    private let reconnectDelay: (Int) async throws -> Void
    private let renderOverride: ((Conversation.ID, PiConversationState) -> Void)?
    private var bindings: [Conversation.ID: Binding]
    private var reducers: [Conversation.ID: PiSessionReducer] = [:]
    private var phases: [Conversation.ID: ConnectionPhase] = [:]
    private var services: [Conversation.ID: any PiServiceProtocol] = [:]
    private var eventTasks: [Conversation.ID: Task<Void, Never>] = [:]
    private var renderTasks: [Conversation.ID: Task<Void, Never>] = [:]
    private var generations: [Conversation.ID: UInt64] = [:]
    private var remoteMessageIndex: [Conversation.ID: [String: Message.ID]] = [:]
    private var projectedMessages: [Conversation.ID: [String: PiPresentationMessage]] = [:]
    private var migratedConversations: Set<Conversation.ID> = []
    private var activeConversationID: Conversation.ID?

    init(
        defaults: UserDefaults = .standard,
        profileProvider: (() throws -> PiServerProfile?)? = nil,
        serviceFactory: ((PiServerProfile) throws -> any PiServiceProtocol)? = nil,
        reconnectDelay: @escaping (Int) async throws -> Void = { attempt in
            let milliseconds = min(8_000, 500 * (1 << min(attempt - 1, 4)))
            try await Task.sleep(for: .milliseconds(milliseconds))
        },
        renderOverride: ((Conversation.ID, PiConversationState) -> Void)? = nil
    ) {
        let profileStore = PiServerProfileStore(defaults: defaults)
        self.defaults = defaults
        self.profileProvider = profileProvider ?? { try profileStore.load() }
        self.serviceFactory = serviceFactory ?? { profile in
            try PiService(configuration: .init(baseURL: profile.baseURL, token: profile.token))
        }
        self.reconnectDelay = reconnectDelay
        self.renderOverride = renderOverride
        bindings = Self.decodeBindings(defaults.data(forKey: bindingsKey))
    }

    func binding(for conversationID: Conversation.ID?) -> Binding? {
        guard let conversationID else { return nil }
        return bindings[conversationID]
    }

    func viewState(for conversationID: Conversation.ID?) -> ViewState? {
        guard let conversationID,
              let binding = bindings[conversationID]
        else { return nil }
        var conversation = reducers[conversationID]?.state ?? PiConversationState()
        if conversation.sessionID.isEmpty {
            conversation.sessionID = binding.sessionID
            conversation.repository = binding.repository
            conversation.clientID = binding.clientID
        }
        return .init(
            conversation: conversation,
            connection: phases[conversationID] ?? .connecting
        )
    }

    func bind(
        conversationID: Conversation.ID,
        sessionID: String,
        repository: String,
        clientID: String,
        baseURL: URL
    ) {
        cancelConnection(conversationID)
        bindings[conversationID] = .init(
            sessionID: sessionID,
            repository: repository,
            clientID: clientID,
            baseURL: baseURL
        )
        reducers[conversationID] = nil
        phases[conversationID] = nil
        clearProjection(conversationID)
        persistBindings()
        activate(conversationID: conversationID)
    }

    func unbind(conversationID: Conversation.ID) {
        cancelConnection(conversationID)
        clearProjection(conversationID)
        reducers[conversationID] = nil
        phases[conversationID] = nil
        bindings[conversationID] = nil
        if activeConversationID == conversationID { activeConversationID = nil }
        persistBindings()
    }

    func unbindAll() {
        for conversationID in Array(eventTasks.keys) {
            cancelConnection(conversationID)
        }
        bindings.removeAll()
        reducers.removeAll()
        phases.removeAll()
        services.removeAll()
        renderTasks.values.forEach { $0.cancel() }
        renderTasks.removeAll()
        remoteMessageIndex.removeAll()
        projectedMessages.removeAll()
        migratedConversations.removeAll()
        activeConversationID = nil
        persistBindings()
    }

    func activate(conversationID: Conversation.ID?) {
        guard activeConversationID != conversationID || conversationID.flatMap({ eventTasks[$0] }) == nil else { return }
        activeConversationID = conversationID
        for connectedID in Array(eventTasks.keys) where connectedID != conversationID {
            cancelConnection(connectedID)
        }
        guard let conversationID, bindings[conversationID] != nil else { return }
        connect(conversationID: conversationID)
    }

    func reconnect(conversationID: Conversation.ID) {
        guard bindings[conversationID] != nil else { return }
        if activeConversationID != conversationID {
            activate(conversationID: conversationID)
            return
        }
        cancelConnection(conversationID)
        connect(conversationID: conversationID)
    }

    private func connect(conversationID: Conversation.ID) {
        guard activeConversationID == conversationID,
              let binding = bindings[conversationID],
              eventTasks[conversationID] == nil
        else { return }
        let generation = nextGeneration(for: conversationID)
        phases[conversationID] = .connecting
        notify(conversationID)

        eventTasks[conversationID] = Task { [weak self] in
            guard let self else { return }
            defer { finishConnection(conversationID, generation: generation) }
            var attempt = 0
            while isCurrent(conversationID, binding: binding, generation: generation) {
                var streamStartedAt: ContinuousClock.Instant?
                do {
                    guard let profile = try profileProvider() else { throw PiServiceError.invalidServerURL }
                    guard profile.baseURL == binding.baseURL else { throw PiCoordinatorError.profileMismatch }
                    let service = try serviceFactory(profile)
                    guard isCurrent(conversationID, binding: binding, generation: generation) else { return }
                    services[conversationID] = service
                    let clientID = binding.clientID

                    let snapshot = try await service.state(sessionID: binding.sessionID)
                    try Task.checkCancellation()
                    guard isCurrent(conversationID, binding: binding, generation: generation) else { return }
                    var reducer = PiSessionReducer()
                    reducer.replace(snapshot: snapshot, clientID: clientID)
                    reducers[conversationID] = reducer
                    phases[conversationID] = .connected
                    render(conversationID)

                    streamStartedAt = .now
                    for try await event in service.events(sessionID: binding.sessionID, clientID: clientID) {
                        try Task.checkCancellation()
                        guard isCurrent(conversationID, binding: binding, generation: generation) else { return }
                        var current = reducers[conversationID] ?? reducer
                        current.reduce(event)
                        if event.resetsReconnectBackoff { attempt = 0 }
                        reducers[conversationID] = current
                        phases[conversationID] = .connected
                        if current.state.isReleased {
                            flushScheduledRender(conversationID, generation: generation)
                            return
                        }
                        scheduleRender(conversationID, generation: generation)
                    }
                    throw PiServiceError.eventStreamEnded
                } catch is CancellationError {
                    return
                } catch {
                    guard isCurrent(conversationID, binding: binding, generation: generation) else { return }
                    if let streamStartedAt,
                       ContinuousClock.now - streamStartedAt >= .seconds(5)
                    {
                        attempt = 0
                    }
                    services[conversationID] = nil
                    phases[conversationID] = .offline(error.localizedDescription)
                    notify(conversationID)
                    attempt += 1
                    do {
                        try await reconnectDelay(attempt)
                        try Task.checkCancellation()
                    } catch {
                        return
                    }
                    guard isCurrent(conversationID, binding: binding, generation: generation) else { return }
                    phases[conversationID] = .connecting
                    notify(conversationID)
                }
            }
        }
    }

    func send(text: String, delivery: PiCommand.Delivery?, conversationID: Conversation.ID) async throws {
        let context = try commandContext(conversationID)
        guard context.state.role == .controller else { throw PiCoordinatorError.viewer }
        guard !context.state.isReleased else { throw PiCoordinatorError.released }
        guard context.state.isStreaming == (delivery != nil) else { throw PiCoordinatorError.sessionStateChanged }
        try await context.service.send(
            .prompt(clientID: context.clientID, text: text, delivery: delivery),
            sessionID: context.binding.sessionID
        )
    }

    func abort(conversationID: Conversation.ID) async throws {
        let context = try commandContext(conversationID)
        guard context.state.role == .controller else { throw PiCoordinatorError.viewer }
        guard !context.state.isReleased else { throw PiCoordinatorError.released }
        guard context.state.isStreaming else { throw PiCoordinatorError.notStreaming }
        try await context.service.send(.abort(clientID: context.clientID), sessionID: context.binding.sessionID)
    }

    func takeOver(conversationID: Conversation.ID) async throws {
        let context = try commandContext(conversationID)
        guard context.state.role == .viewer else { throw PiCoordinatorError.alreadyController }
        guard !context.state.isReleased else { throw PiCoordinatorError.released }
        guard !context.state.isStreaming else { throw PiCoordinatorError.streaming }
        try await context.service.takeOver(sessionID: context.binding.sessionID, clientID: context.clientID)
    }

    func release(conversationID: Conversation.ID) async throws {
        let context = try commandContext(conversationID)
        guard context.state.role == .controller else { throw PiCoordinatorError.viewer }
        guard !context.state.isReleased else { throw PiCoordinatorError.released }
        try await context.service.release(sessionID: context.binding.sessionID, clientID: context.clientID)
    }

    private func commandContext(_ conversationID: Conversation.ID) throws -> (
        binding: Binding,
        service: any PiServiceProtocol,
        clientID: String,
        state: PiConversationState
    ) {
        guard let binding = bindings[conversationID] else { throw PiCoordinatorError.notBound }
        guard activeConversationID == conversationID,
              phases[conversationID] == .connected
        else { throw PiCoordinatorError.notConnected }
        guard let service = services[conversationID],
              let state = reducers[conversationID]?.state
        else { throw PiCoordinatorError.notConnected }
        return (binding, service, binding.clientID, state)
    }

    private func render(_ conversationID: Conversation.ID) {
        guard let state = reducers[conversationID]?.state else { return }
        if let renderOverride {
            renderOverride(conversationID, state)
            notify(conversationID)
            return
        }
        guard ConversationManager.shared.conversation(identifier: conversationID) != nil else {
            unbind(conversationID: conversationID)
            return
        }
        let session = ConversationSessionManager.shared.session(for: conversationID)
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let remoteIDs = Set(state.messages.map(\.id))

        if migratedConversations.insert(conversationID).inserted {
            let persistedPiMessageIDs = session.messages.compactMap { message -> Message.ID? in
                guard !session.isTransientMessage(message.objectId),
                      let data = message.metadata,
                      (try? decoder.decode(PiMessageMetadata.self, from: data)) != nil
                else { return nil }
                return message.objectId
            }
            persistedPiMessageIDs.forEach { session.discard(messageIdentifier: $0) }
        }

        if remoteMessageIndex[conversationID] == nil {
            var initialIndex: [String: Message.ID] = [:]
            for message in session.messages {
                guard session.isTransientMessage(message.objectId),
                      let data = message.metadata,
                      let metadata = try? decoder.decode(PiMessageMetadata.self, from: data)
                else { continue }
                initialIndex[metadata.remoteID] = message.objectId
            }
            remoteMessageIndex[conversationID] = initialIndex
        }

        var index = remoteMessageIndex[conversationID] ?? [:]
        var changed = false
        for remoteID in index.keys where !remoteIDs.contains(remoteID) {
            if let messageID = index.removeValue(forKey: remoteID) {
                session.discardTransientMessage(messageIdentifier: messageID)
                changed = true
            }
        }

        let previous = projectedMessages[conversationID] ?? [:]
        for presentation in state.messages {
            guard previous[presentation.id] != presentation || index[presentation.id] == nil else { continue }
            let existing = index[presentation.id].flatMap(session.message(for:))
            let message = existing ?? session.appendTransientMessage(role: presentation.storageRole)
            index[presentation.id] = message.objectId
            message.update(\.role, to: presentation.storageRole)
            message.update(\.document, to: presentation.document)
            message.update(\.reasoningContent, to: presentation.reasoning)
            message.update(\.toolStatus, to: presentation.toolStatus(preserving: existing?.toolStatus))
            message.update(\.metadata, to: try? encoder.encode(PiMessageMetadata(remoteID: presentation.id)))
            changed = true
        }

        remoteMessageIndex[conversationID] = index
        projectedMessages[conversationID] = state.messages.reduce(into: [:]) { $0[$1.id] = $1 }
        if changed { session.notifyMessagesDidChange(scrolling: state.isStreaming) }
        if let title = state.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            if ConversationManager.shared.conversation(identifier: conversationID)?.title != title {
                ConversationManager.shared.editConversation(identifier: conversationID) {
                    $0.update(\.title, to: title)
                }
            }
        }
        notify(conversationID)
    }

    private func scheduleRender(_ conversationID: Conversation.ID, generation: UInt64) {
        guard renderTasks[conversationID] == nil else { return }
        renderTasks[conversationID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            self?.flushScheduledRender(conversationID, generation: generation)
        }
    }

    private func flushScheduledRender(_ conversationID: Conversation.ID, generation: UInt64) {
        renderTasks[conversationID]?.cancel()
        renderTasks[conversationID] = nil
        guard generations[conversationID] == generation else { return }
        render(conversationID)
    }

    private func clearProjection(_ conversationID: Conversation.ID) {
        renderTasks[conversationID]?.cancel()
        renderTasks[conversationID] = nil
        remoteMessageIndex[conversationID] = nil
        projectedMessages[conversationID] = nil
        migratedConversations.remove(conversationID)
    }

    private func notify(_ conversationID: Conversation.ID) {
        NotificationCenter.default.post(name: .piSessionDidChange, object: conversationID)
    }

    private func isCurrent(_ conversationID: Conversation.ID, binding: Binding, generation: UInt64) -> Bool {
        !Task.isCancelled
            && activeConversationID == conversationID
            && bindings[conversationID] == binding
            && generations[conversationID] == generation
    }

    private func nextGeneration(for conversationID: Conversation.ID) -> UInt64 {
        let generation = (generations[conversationID] ?? 0) &+ 1
        generations[conversationID] = generation
        return generation
    }

    private func cancelConnection(_ conversationID: Conversation.ID) {
        _ = nextGeneration(for: conversationID)
        eventTasks[conversationID]?.cancel()
        eventTasks[conversationID] = nil
        services[conversationID] = nil
        renderTasks[conversationID]?.cancel()
        renderTasks[conversationID] = nil
    }

    private func finishConnection(_ conversationID: Conversation.ID, generation: UInt64) {
        guard generations[conversationID] == generation else { return }
        eventTasks[conversationID] = nil
        services[conversationID] = nil
    }

    private func persistBindings() {
        defaults.set(try? JSONEncoder().encode(bindings), forKey: bindingsKey)
    }

    private static func decodeBindings(_ data: Data?) -> [Conversation.ID: Binding] {
        guard let data else { return [:] }
        return (try? JSONDecoder().decode([Conversation.ID: Binding].self, from: data)) ?? [:]
    }
}

private struct PiMessageMetadata: Codable {
    let remoteID: String
}

private extension PiServerEvent {
    var resetsReconnectBackoff: Bool {
        if case .initial = self { return false }
        return true
    }
}

private extension PiPresentationMessage {
    var storageRole: Message.Role {
        switch role {
        case .user: .user
        case .assistant: .assistant
        case .system: .hint
        case .tool: .toolHint
        }
    }

    var document: String {
        if let tool { return tool.detail }
        return text.isEmpty && reasoning.isEmpty ? String(localized: "Empty message.") : text
    }

    func toolStatus(preserving existing: Message.ToolStatus?) -> Message.ToolStatus {
        guard let tool else { return .init() }
        let state = switch tool.state {
        case .running: 0
        case .succeeded: 1
        case .failed: 2
        }
        var status = Message.ToolStatus(name: tool.name, state: state, message: tool.detail)
        if let existing { status.id = existing.id }
        return status
    }
}

enum PiCoordinatorError: LocalizedError, Equatable {
    case notBound
    case notConnected
    case viewer
    case streaming
    case released
    case notStreaming
    case alreadyController
    case sessionStateChanged
    case profileMismatch

    var errorDescription: String? {
        switch self {
        case .notBound: String(localized: "This conversation is not linked to a Pi session.")
        case .notConnected: String(localized: "Pi is reconnecting. Try again in a moment.")
        case .viewer: String(localized: "This session is view-only. Take control before sending a message.")
        case .streaming: String(localized: "Wait for the current response to finish before taking control.")
        case .released: String(localized: "This session has been released to the Pi CLI.")
        case .notStreaming: String(localized: "There is no active Pi response to stop.")
        case .alreadyController: String(localized: "This device already controls the Pi session.")
        case .sessionStateChanged: String(localized: "The Pi session state changed. Review it and send again.")
        case .profileMismatch: String(localized: "This conversation belongs to a different Pi server. Restore that server profile to reconnect.")
        }
    }
}
