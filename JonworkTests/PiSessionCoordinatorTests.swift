@testable import Jonwork
import CryptoKit
import Foundation
import Testing
import UIKit

@Suite(.serialized)
struct PiSessionCoordinatorTests {
    @Test @MainActor
    func retainedExportAndActionsRejectIdenticalBindingInNewAuthenticationEpoch() async throws {
        let service = PiServiceSpy(snapshots: [
            snapshot(title: "Account A", message: "ACCOUNT_A_PRIVATE"),
            snapshot(title: "Account B", message: "ACCOUNT_B_PRIVATE"),
        ], streams: [pendingStream(), pendingStream()])
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer { coordinator.unbindAll(); defaults.removePersistentDomain(forName: defaultsSuite) }
        bind(coordinator, conversationID: "conversation", sessionID: "shared-session")
        try await waitUntil { coordinator.viewState(for: "conversation")?.connection == .connected }
        let oldBinding = coordinator.binding(for: "conversation")
        let old = PiConversationExportController(conversationID: "conversation", coordinator: coordinator)
        old.loadViewIfNeeded()
        #expect(String(data: try #require(old.exportData(pdf: false)), encoding: .utf8)?.contains("ACCOUNT_A_PRIVATE") == true)
        let context = PiPresentationAuthorization(conversationID: "conversation", coordinator: coordinator)
        let menu = coordinator.nativeFlagsMenu(conversationID: "conversation")
        #expect(menu.options.contains(.displayInline))
        #expect(menu.children.count == 2)
        #expect(menu.children.allSatisfy { ($0 as? UIAction)?.title.isEmpty == false })
        _ = coordinator.beginAuthenticationEpoch()
        coordinator.unbindAll()
        bind(coordinator, conversationID: "conversation", sessionID: "shared-session")
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.messages.first?.text == "ACCOUNT_B_PRIVATE" }
        #expect(coordinator.binding(for: "conversation") == oldBinding)
        #expect(!context.isCurrent)
        #expect(old.exportData(pdf: false) == nil)
        #expect(old.exportData(pdf: true) == nil)
        #expect(old.tableView(old.tableView, numberOfRowsInSection: 0) == 0)
        for action in menu.children.compactMap({ $0 as? UIAction }) {
            let button = UIButton(primaryAction: action)
            button.sendActions(for: .primaryActionTriggered)
        }
        #expect(coordinator.nativeFlags(for: "conversation") == .init())
        let freshMenu = coordinator.nativeFlagsMenu(conversationID: "conversation")
        let freshAction = try #require(freshMenu.children.first as? UIAction)
        UIButton(primaryAction: freshAction).sendActions(for: .primaryActionTriggered)
        #expect(coordinator.nativeFlags(for: "conversation").favorite)
        let fresh = PiConversationExportController(conversationID: "conversation", coordinator: coordinator)
        #expect(String(data: try #require(fresh.exportData(pdf: false)), encoding: .utf8)?.contains("ACCOUNT_B_PRIVATE") == true)
    }

    @Test @MainActor
    func delayedMutationSnapshotCannotRestoreLoggedOutOrReboundHistory() async throws {
        let stream = ControlledEventStream()
        let service = PiServiceSpy(snapshots: [
            snapshot(title: "Old", message: "old private history", controllerClientID: "controller"),
            snapshot(title: "Delayed old result", message: "old private result", revision: 2, controllerClientID: "controller"),
            snapshot(title: "New account", message: "new account history", controllerClientID: "new-client"),
        ], streams: [stream.stream, pendingStream()])
        var renderedTexts: [String] = []
        let (coordinator, defaults) = makeCoordinator(service: service) { _, state in renderedTexts.append(state.messages.first?.text ?? "") }
        defer { coordinator.unbindAll(); defaults.removePersistentDomain(forName: defaultsSuite) }
        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { coordinator.viewState(for: "conversation")?.connection == .connected }
        let suspension = SuspendedAttachmentUpload()
        service.suspendSnapshots { await suspension.wait() }
        let mutation = Task { try await coordinator.rename("renamed", conversationID: "conversation") }
        try await waitUntil { service.stateCallCount >= 2 }
        await coordinator.revokeAllCredentialsAndState()
        #expect(coordinator.viewState(for: "conversation") == nil)
        service.clearSnapshotSuspension()
        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "new-client")
        await suspension.release()
        await #expect(throws: CancellationError.self) { try await mutation.value }
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.messages.first?.text == "new account history" }
        #expect(!renderedTexts.contains("old private result"))
        #expect(coordinator.viewState(for: "conversation")?.conversation.messages.first?.text == "new account history")
    }
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
            service.stateCallCount == 2 && coordinator.viewState(for: "conversation")?.conversation.messages.first?.text == "new"
        }

        #expect(rendered.compactMap { $0.messages.first?.text } == ["old", "new"])
        #expect(rendered.last?.messages.first?.text == "new")
    }

    @Test
    @MainActor
    func `reconnect backoff resets only after receiving a stream event`() async throws {
        let connectedStream = ControlledEventStream()
        let initialState = snapshot(title: "One", message: "one")
        let service = PiServiceSpy(
            snapshots: [initialState, snapshot(title: "Two", message: "two"), snapshot(title: "Three", message: "three")],
            streams: [finiteStream([controllerEvent(id: "1", clientID: nil)]), finishedStream(), connectedStream.stream]
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
            service.stateCallCount == 2 && coordinator.viewState(for: "conversation")?.conversation.messages.first?.text == "new"
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
        #expect(coordinator.viewState(for: "a")?.conversation.messages.isEmpty == true)

        service.resume(sessionID: "session-b", with: snapshot(title: "Current", message: "current", sessionID: "session-b"))
        try await waitUntil { renderedConversationIDs.contains("b") }
        #expect(coordinator.viewState(for: "b")?.conversation.messages.first?.text == "current")
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
    func `remote session identity is unique across local conversations`() {
        let service = PiServiceSpy(snapshots: [], streams: [])
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer {
            coordinator.unbindAll()
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        let baseURL = URL(string: "https://pi.example.test")!
        coordinator.bind(
            conversationID: "old-local",
            sessionID: "remote-session",
            repository: "/repo",
            clientID: "client-a",
            baseURL: baseURL
        )
        coordinator.bind(
            conversationID: "current-local",
            sessionID: "remote-session",
            repository: "/repo",
            clientID: "client-b",
            baseURL: baseURL
        )

        #expect(coordinator.binding(for: "old-local") == nil)
        #expect(coordinator.conversationID(
            sessionID: "remote-session",
            repository: "/repo",
            baseURL: baseURL
        ) == "current-local")
    }

    @Test
    @MainActor
    func `attachment policy intersects gateway model and media type capabilities`() async throws {
        let stream = ControlledEventStream()
        let model = attachmentModel()
        let service = PiServiceSpy(
            snapshots: [snapshot(
                title: "Attachments",
                message: "history",
                model: .init(provider: model.provider, id: model.id)
            )],
            streams: [stream.stream],
            models: [model]
        )
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        bind(coordinator, conversationID: "conversation", sessionID: "session")
        #expect(coordinator.viewState(for: "conversation")?.connection == .restoring)
        try await waitUntil { coordinator.viewState(for: "conversation")?.connection == .connected }

        let policy = try #require(coordinator.attachmentPolicy(conversationID: "conversation"))
        #expect(policy.allowsImages)
        #expect(!policy.allowsFiles)
        #expect(coordinator.supportsAttachmentMediaType("image/png", conversationID: "conversation"))
        #expect(!coordinator.supportsAttachmentMediaType("application/octet-stream", conversationID: "conversation"))
    }

    @Test
    @MainActor
    func `set model remains pending until matching operation settles and snapshot confirms`() async throws {
        let stream = ControlledEventStream()
        let model = attachmentModel()
        let service = PiServiceSpy(
            snapshots: [
                snapshot(title: "Before", message: "before"),
                snapshot(
                    title: "After", message: "after", revision: 2, lastEventID: "3",
                    model: .init(provider: model.provider, id: model.id)
                ),
            ],
            streams: [stream.stream],
            models: [model]
        )
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { service.eventClientIDs == ["controller"] }
        stream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.role == .controller }

        var completed = false
        let mutation = Task {
            try await coordinator.setModel(provider: model.provider, modelID: model.id, conversationID: "conversation")
            completed = true
        }
        try await waitUntil { service.commands.count == 1 }
        #expect(coordinator.viewState(for: "conversation")?.pendingAction == .other)
        #expect(!completed)
        #expect(service.stateCallCount == 1)

        stream.yield(operationAcceptedEvent(id: "2", operationID: "operation", command: "set_model"))
        stream.yield(operationSettledEvent(id: "3", operationID: "operation", status: "completed"))
        try await mutation.value

        #expect(completed)
        #expect(service.stateCallCount == 2)
        #expect(coordinator.viewState(for: "conversation")?.conversation.model?.id == model.id)
        #expect(coordinator.viewState(for: "conversation")?.pendingAction == nil)
    }

    @Test
    @MainActor
    func `set thinking remains pending and failed settlement does not fetch optimistic snapshot`() async throws {
        let stream = ControlledEventStream()
        let model = reasoningModel()
        let service = PiServiceSpy(
            snapshots: [snapshot(
                title: "Thinking", message: "before",
                model: .init(provider: model.provider, id: model.id)
            )],
            streams: [stream.stream],
            models: [model]
        )
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { service.eventClientIDs == ["controller"] }
        stream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.role == .controller }

        let mutation = Task {
            try await coordinator.setThinkingLevel(.high, conversationID: "conversation")
        }
        try await waitUntil { service.commands.count == 1 }
        #expect(coordinator.viewState(for: "conversation")?.pendingAction == .other)
        stream.yield(operationAcceptedEvent(id: "2", operationID: "operation", command: "set_thinking_level"))
        stream.yield(operationSettledEvent(id: "3", operationID: "operation", status: "failed"))

        await #expect(throws: PiServiceError.gateway(code: "operation_failed", retryable: true)) {
            try await mutation.value
        }
        #expect(service.stateCallCount == 1)
        #expect(coordinator.viewState(for: "conversation")?.conversation.thinkingLevel == "off")
    }

    @Test(arguments: ["failed", "aborted"])
    @MainActor
    func `known terminal configuration failure clears pending and permits subsequent mutations`(
        terminalStatus: String
    ) async throws {
        let stream = ControlledEventStream()
        let store = InMemoryPendingMutationStore()
        let reasoning = reasoningModel()
        let replacement = attachmentModel()
        let confirmedThinking = snapshot(
            title: "Thinking", message: "thinking", revision: 3, lastEventID: "5",
            model: .init(provider: reasoning.provider, id: reasoning.id), thinkingLevel: .high,
            controllerClientID: "controller"
        )
        let confirmedModel = snapshot(
            title: "Model", message: "model", revision: 4, lastEventID: "7",
            model: .init(provider: replacement.provider, id: replacement.id), thinkingLevel: .high,
            controllerClientID: "controller"
        )
        let renamed = snapshot(
            title: "Renamed", message: "renamed", revision: 5, lastEventID: "7",
            model: .init(provider: replacement.provider, id: replacement.id), thinkingLevel: .high,
            controllerClientID: "controller"
        )
        let service = PiServiceSpy(
            snapshots: [
                snapshot(
                    title: "Initial", message: "initial",
                    model: .init(provider: reasoning.provider, id: reasoning.id)
                ),
                confirmedThinking,
                confirmedModel,
                renamed,
            ],
            streams: [stream.stream], models: [reasoning, replacement]
        )
        service.enqueueOperationIDs(["terminal", "same-action", "different-action", "rename"])
        let (coordinator, defaults) = makeCoordinator(service: service, pendingStore: store) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { service.eventClientIDs == ["controller"] }
        stream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.role == .controller }

        let terminal = Task { try await coordinator.setThinkingLevel(.high, conversationID: "conversation") }
        try await waitUntil { service.commands.count == 1 }
        stream.yield(operationAcceptedEvent(id: "2", operationID: "terminal", command: "set_thinking_level"))
        stream.yield(operationSettledEvent(id: "3", operationID: "terminal", status: terminalStatus))
        do {
            try await terminal.value
            Issue.record("Expected the terminal operation to fail")
        } catch let error as PiServiceError {
            let expected = terminalStatus == "failed"
                ? PiServiceError.gateway(code: "operation_failed", retryable: true)
                : PiServiceError.gateway(code: "operation_aborted", retryable: false)
            #expect(error == expected)
        }
        #expect(store.mutations.isEmpty)

        let sameAction = Task { try await coordinator.setThinkingLevel(.high, conversationID: "conversation") }
        try await waitUntil { service.commands.count == 2 }
        stream.yield(operationAcceptedEvent(
            id: "4", operationID: "same-action", command: "set_thinking_level", revision: 3
        ))
        stream.yield(operationSettledEvent(
            id: "5", operationID: "same-action", status: "completed", revision: 3
        ))
        try await sameAction.value

        let differentAction = Task {
            try await coordinator.setModel(
                provider: replacement.provider,
                modelID: replacement.id,
                conversationID: "conversation"
            )
        }
        try await waitUntil { service.commands.count == 3 }
        stream.yield(operationAcceptedEvent(
            id: "6", operationID: "different-action", command: "set_model", revision: 4
        ))
        stream.yield(operationSettledEvent(
            id: "7", operationID: "different-action", status: "completed", revision: 4
        ))
        try await differentAction.value

        try await coordinator.rename("Renamed", conversationID: "conversation")
        #expect(service.commands == [
            .setThinkingLevel(.high),
            .setThinkingLevel(.high),
            .setModel(provider: replacement.provider, modelID: replacement.id),
            .rename("Renamed"),
        ])
        #expect(store.mutations.isEmpty)
    }

    @Test
    @MainActor
    func `configuration timeout keeps durable receipt and does not apply an optimistic snapshot`() async throws {
        let stream = ControlledEventStream()
        let store = InMemoryPendingMutationStore()
        let model = reasoningModel()
        let service = PiServiceSpy(
            snapshots: [snapshot(
                title: "Thinking", message: "before",
                model: .init(provider: model.provider, id: model.id)
            )],
            streams: [stream.stream], models: [model],
            discovery: testDiscovery(mutationTimeoutMs: 40)
        )
        let (coordinator, defaults) = makeCoordinator(service: service, pendingStore: store) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { service.eventClientIDs == ["controller"] }
        stream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.role == .controller }

        await #expect(throws: PiServiceError.timedOut) {
            try await coordinator.setThinkingLevel(.high, conversationID: "conversation")
        }

        #expect(service.stateCallCount == 1)
        #expect(store.mutations["conversation"]?.receipt?.operationId == "operation")
        #expect(coordinator.viewState(for: "conversation")?.conversation.thinkingLevel == "off")
    }

    @Test
    @MainActor
    func `configuration settlement replay survives reconnect before authoritative confirmation`() async throws {
        let firstStream = ControlledEventStream()
        let replayStream = ControlledEventStream()
        let model = attachmentModel()
        let confirmed = snapshot(
            title: "Confirmed", message: "after", revision: 2, lastEventID: "3",
            model: .init(provider: model.provider, id: model.id)
        )
        let service = PiServiceSpy(
            snapshots: [snapshot(title: "Before", message: "before"), confirmed, confirmed],
            streams: [firstStream.stream, replayStream.stream], models: [model]
        )
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { service.eventClientIDs == ["controller"] }
        firstStream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.role == .controller }

        let mutation = Task {
            try await coordinator.setModel(provider: model.provider, modelID: model.id, conversationID: "conversation")
        }
        try await waitUntil { service.commands.count == 1 }
        firstStream.finish(throwing: PiServiceError.connectionLost)
        try await waitUntil { service.eventClientIDs.count == 2 }
        replayStream.yield(operationAcceptedEvent(id: "2", operationID: "operation", command: "set_model"))
        replayStream.yield(operationSettledEvent(id: "3", operationID: "operation", status: "completed"))
        try await mutation.value

        #expect(service.stateCallCount == 3)
        #expect(coordinator.viewState(for: "conversation")?.conversation.model?.id == model.id)
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
        let appliedState = snapshot(title: "Identity", message: "history", revision: 2)
        let service = PiServiceSpy(snapshots: [state, appliedState], streams: [stream.stream])
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "create-client")
        try await waitUntil { service.eventClientIDs == ["create-client"] }
        stream.yield(controllerEvent(id: "1", clientID: "create-client"))
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.role == .controller }
        try await coordinator.send(text: "hello", delivery: nil, conversationID: "conversation")

        #expect(coordinator.binding(for: "conversation")?.clientID == "create-client")
        #expect(coordinator.binding(for: "conversation")?.baseURL == URL(string: "https://pi.example.test"))
        #expect(service.commands == [.send(text: "hello", attachmentIDs: [], delivery: .prompt)])
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

    @Test
    @MainActor
    func `credential revocation cancels service and removes send authority`() async throws {
        let service = PiServiceSpy(
            snapshots: [snapshot(title: "Bound", message: "history")],
            streams: [pendingStream()]
        )
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        bind(coordinator, conversationID: "conversation", sessionID: "session")
        try await waitUntil { coordinator.viewState(for: "conversation")?.connection == .connected }

        coordinator.saveTextDraft("private unsent draft", conversationID: "conversation")
        #expect(coordinator.textDraft(for: "conversation") == "private unsent draft")
        await coordinator.revokeAllCredentialsAndState()

        #expect(coordinator.textDraft(for: "conversation").isEmpty)
        #expect(service.cancelCount == 1)
        #expect(coordinator.binding(for: "conversation") == nil)
        await #expect(throws: PiCoordinatorError.notBound) {
            try await coordinator.send(text: "blocked", delivery: nil, conversationID: "conversation")
        }
    }

    @Test(arguments: [false, true])
    @MainActor
    func `authorization change during suspended upload never sends prompt or clears accepted batch`(changeModel: Bool) async throws {
        let stream = ControlledEventStream()
        let nextStream = ControlledEventStream()
        let pendingStore = InMemoryPendingMutationStore()
        let model = PiGatewayWire.Snapshot.Configuration.Model(provider: "test", id: "vision")
        let newModel = PiGatewayWire.Snapshot.Configuration.Model(provider: "test", id: "reasoning")
        let service = PiServiceSpy(
            snapshots: [
                snapshot(title: "Before", message: "history", model: model, controllerClientID: "controller"),
                snapshot(title: "After", message: "history", model: newModel, controllerClientID: "controller"),
            ], streams: [stream.stream, nextStream.stream], models: [attachmentModel(), reasoningModel()]
        )
        let barrier = SuspendedAttachmentUpload()
        service.suspendUploads { await barrier.wait() }
        let data = Data("private image".utf8)
        service.enqueueUpload(.success(uploadedAttachment(id: "accepted-attachment", name: "image.png", data: data)))
        let (coordinator, defaults) = makeCoordinator(service: service, pendingStore: pendingStore) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { coordinator.viewState(for: "conversation")?.connection == .connected }
        let consent = PiSharingConsent(defaults: defaults)
        let scope = PiSharingConsent.Scope(
            workspaceURL: URL(string: "https://pi.example.test")!, repository: "/repo",
            connectionID: "controller", provider: "test", modelID: "vision"
        )
        #expect(await consent.authorize(scope, currentScope: { scope }, requestPermission: { true }))
        let fence = try #require(consent.fence(for: scope))
        // Even a prior permission for the new model must not validate the original fence.
        if changeModel {
            let otherScope = PiSharingConsent.Scope(
                workspaceURL: scope.workspaceURL, repository: scope.repository,
                connectionID: scope.connectionID, provider: "test", modelID: "reasoning"
            )
            #expect(await consent.authorize(otherScope, currentScope: { otherScope }, requestPermission: { true }))
        }
        let sending = Task { @MainActor in
            try await coordinator.send(
                text: "inspect private history", attachments: [.init(data: data, fileName: "image.png", mediaType: "image/png", kind: .image)],
                delivery: .prompt, conversationID: "conversation", sharingAuthorization: fence
            )
        }
        try await waitUntil { service.uploadKeys.count == 1 }
        if changeModel {
            coordinator.reconnect(conversationID: "conversation")
            try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.model?.id == "reasoning" }
        } else {
            consent.revokeAll()
        }
        await barrier.release()
        await #expect(throws: PiCoordinatorError.sessionStateChanged) { try await sending.value }
        #expect(service.commands.isEmpty)
        #expect(service.uploadKeys.count == 1)
        #expect(pendingStore.attachmentUploads["conversation"]?.uploads.first?.attachmentID == "accepted-attachment")
    }

    @Test
    @MainActor
    func `later attachment failure preserves accepted upload and replays only the pending key`() async throws {
        let stream = ControlledEventStream()
        let store = InMemoryPendingMutationStore()
        let model = PiGatewayWire.Snapshot.Configuration.Model(provider: "test", id: "vision")
        let service = PiServiceSpy(
            snapshots: [
                snapshot(title: "Controller", message: "history", model: model),
                snapshot(title: "Applied", message: "accepted", revision: 2, model: model),
            ],
            streams: [stream.stream],
            models: [attachmentModel()]
        )
        let first = Data("first".utf8)
        let second = Data("second".utf8)
        service.enqueueUpload(.success(uploadedAttachment(id: "attachment-1", name: "first.png", data: first)))
        service.enqueueUpload(.failure(PiServiceError.timedOut))
        service.enqueueUpload(.success(uploadedAttachment(id: "attachment-2", name: "second.png", data: second)))
        let (coordinator, defaults) = makeCoordinator(service: service, pendingStore: store) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { service.eventClientIDs == ["controller"] }
        stream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.role == .controller }
        let attachments = [
            PiAttachmentUpload(data: first, fileName: "first.png", mediaType: "image/png", kind: .image),
            PiAttachmentUpload(data: second, fileName: "second.png", mediaType: "image/png", kind: .image),
        ]

        await #expect(throws: PiServiceError.timedOut) {
            try await coordinator.send(
                text: "inspect", attachments: attachments, delivery: .prompt,
                conversationID: "conversation"
            )
        }
        let pending = try #require(store.attachmentUploads["conversation"])
        #expect(pending.uploads[0].attachmentID == "attachment-1")
        #expect(pending.uploads[1].attachmentID == nil)

        try await coordinator.send(
            text: "inspect", attachments: attachments, delivery: .prompt,
            conversationID: "conversation"
        )

        #expect(service.uploadKeys.count == 3)
        #expect(service.uploadKeys[0] != service.uploadKeys[1])
        #expect(service.uploadKeys[1] == service.uploadKeys[2])
        #expect(try store.loadAttachmentUploads().isEmpty)
    }

    @Test
    @MainActor
    func `pending attachment survives restart blocks a different send and replays the exact key`() async throws {
        let store = InMemoryPendingMutationStore()
        let model = PiGatewayWire.Snapshot.Configuration.Model(provider: "test", id: "vision")
        let data = Data("restart".utf8)
        let attachment = PiAttachmentUpload(
            data: data, fileName: "restart.png", mediaType: "image/png", kind: .image
        )
        let firstStream = ControlledEventStream()
        let firstService = PiServiceSpy(
            snapshots: [snapshot(title: "Controller", message: "history", model: model)],
            streams: [firstStream.stream], models: [attachmentModel()]
        )
        firstService.enqueueUpload(.failure(PiServiceError.connectionLost))
        let (first, firstDefaults) = makeCoordinator(service: firstService, pendingStore: store) { _, _ in }
        bind(first, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { firstService.eventClientIDs == ["controller"] }
        firstStream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { first.viewState(for: "conversation")?.conversation.role == .controller }
        await #expect(throws: PiServiceError.connectionLost) {
            try await first.send(
                text: "inspect", attachments: [attachment], delivery: .prompt,
                conversationID: "conversation"
            )
        }
        let originalKey = try #require(firstService.uploadKeys.first)
        first.unbind(conversationID: "conversation")
        firstDefaults.removePersistentDomain(forName: defaultsSuite)

        let secondStream = ControlledEventStream()
        let secondService = PiServiceSpy(
            snapshots: [
                snapshot(title: "Controller", message: "history", model: model),
                snapshot(title: "Applied", message: "accepted", revision: 2, model: model),
            ],
            streams: [secondStream.stream], models: [attachmentModel()]
        )
        secondService.enqueueUpload(.success(uploadedAttachment(
            id: "attachment-restart", name: "restart.png", data: data
        )))
        let (second, secondDefaults) = makeCoordinator(service: secondService, pendingStore: store) { _, _ in }
        defer {
            second.unbind(conversationID: "conversation")
            secondDefaults.removePersistentDomain(forName: defaultsSuite)
        }
        bind(second, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { secondService.eventClientIDs == ["controller"] }
        secondStream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { second.viewState(for: "conversation")?.conversation.role == .controller }

        await #expect(throws: PiCoordinatorError.mutationInFlight) {
            try await second.send(
                text: "different", attachments: [attachment], delivery: .prompt,
                conversationID: "conversation"
            )
        }
        #expect(secondService.uploadKeys.isEmpty)

        try await second.send(
            text: "inspect", attachments: [attachment], delivery: .prompt,
            conversationID: "conversation"
        )
        #expect(secondService.uploadKeys == [originalKey])
        #expect(try store.loadAttachmentUploads().isEmpty)
    }

    @Test
    @MainActor
    func `response lost after applied uses receipt without resubmitting`() async throws {
        let stream = ControlledEventStream()
        let service = PiServiceSpy(
            snapshots: [
                snapshot(title: "Controller", message: "history"),
                snapshot(title: "Applied", message: "accepted", revision: 2),
            ],
            streams: [stream.stream]
        )
        service.failNextMutation(with: PiServiceError.timedOut)
        service.enqueueReceipt(.success(.applied(.init(
            sessionId: "session", revision: 2, operationId: "operation", afterEventId: "1"
        ))))
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { service.eventClientIDs == ["controller"] }
        stream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.role == .controller }

        try await coordinator.send(text: "same", delivery: nil, conversationID: "conversation")

        #expect(service.mutationContexts.count == 1)
        #expect(coordinator.viewState(for: "conversation")?.conversation.messages.first?.text == "accepted")
    }

    @Test
    @MainActor
    func `pending receipt preserves durable mutation and blocks resubmission`() async throws {
        let stream = ControlledEventStream()
        let store = InMemoryPendingMutationStore()
        let service = PiServiceSpy(
            snapshots: [snapshot(title: "Controller", message: "history")],
            streams: [stream.stream]
        )
        service.failNextMutation(with: PiServiceError.connectionLost)
        service.enqueueReceipt(.success(.pending(sessionId: "session")))
        let (coordinator, defaults) = makeCoordinator(service: service, pendingStore: store) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { service.eventClientIDs == ["controller"] }
        stream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.role == .controller }

        await #expect(throws: PiCoordinatorError.mutationPending) {
            try await coordinator.send(text: "same", delivery: nil, conversationID: "conversation")
        }

        #expect(service.mutationContexts.count == 1)
        let storedAction = try store.load()["conversation"]?.action
        #expect(storedAction == .send(text: "same", attachmentIDs: [], delivery: .prompt))
    }

    @Test
    @MainActor
    func `receipt not found replays exact canonical mutation`() async throws {
        let stream = ControlledEventStream()
        let service = PiServiceSpy(
            snapshots: [snapshot(title: "Controller", message: "history"), snapshot(title: "Applied", message: "accepted", revision: 2)],
            streams: [stream.stream]
        )
        service.failNextMutation(with: PiServiceError.timedOut)
        service.enqueueReceipt(.failure(PiServiceError.mutationNotFound))
        let (coordinator, defaults) = makeCoordinator(service: service) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { service.eventClientIDs == ["controller"] }
        stream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.role == .controller }

        try await coordinator.send(text: "same", delivery: nil, conversationID: "conversation")

        #expect(service.mutationContexts.count == 2)
        #expect(service.mutationContexts[0] == service.mutationContexts[1])
    }

    @Test
    @MainActor
    func `app restart recovers durable mutation before exact replay`() async throws {
        let store = InMemoryPendingMutationStore()
        let firstStream = ControlledEventStream()
        let firstService = PiServiceSpy(
            snapshots: [snapshot(title: "Controller", message: "history")],
            streams: [firstStream.stream]
        )
        firstService.failNextMutation(with: PiServiceError.timedOut)
        firstService.enqueueReceipt(.success(.pending(sessionId: "session")))
        let (first, defaults) = makeCoordinator(service: firstService, pendingStore: store) { _, _ in }
        bind(first, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { firstService.eventClientIDs == ["controller"] }
        firstStream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { first.viewState(for: "conversation")?.conversation.role == .controller }
        await #expect(throws: PiCoordinatorError.mutationPending) {
            try await first.send(text: "same", delivery: nil, conversationID: "conversation")
        }
        first.activate(conversationID: nil)

        let secondStream = ControlledEventStream()
        let secondService = PiServiceSpy(
            snapshots: [snapshot(title: "Controller", message: "history"), snapshot(title: "Applied", message: "accepted", revision: 2)],
            streams: [secondStream.stream]
        )
        secondService.enqueueReceipt(.failure(PiServiceError.mutationNotFound))
        let second = PiSessionCoordinator(
            defaults: defaults,
            profileProvider: { PiServerProfile(baseURL: URL(string: "https://pi.example.test")!, token: nil) },
            serviceFactory: { _ in secondService },
            pendingMutationStore: store,
            reconnectDelay: { _ in },
            renderOverride: { _, _ in }
        )
        defer {
            second.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        second.activate(conversationID: "conversation")
        try await waitUntil { secondService.eventClientIDs == ["controller"] }
        secondStream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { second.viewState(for: "conversation")?.conversation.role == .controller }

        try await second.send(text: "same", delivery: nil, conversationID: "conversation")

        #expect(secondService.mutationContexts.count == 1)
        #expect(firstService.mutationContexts.first == secondService.mutationContexts.first)
        let storedMutations = try store.load()
        #expect(storedMutations.isEmpty)
    }

    @Test(arguments: [
        PiAppliedSnapshotFailure.malformed,
        PiAppliedSnapshotFailure.stale,
        PiAppliedSnapshotFailure.unauthorized,
    ])
    @MainActor
    fileprivate func `applied receipt survives snapshot recovery failure without a second mutation key`(
        _ failure: PiAppliedSnapshotFailure
    ) async throws {
        let stream = ControlledEventStream()
        let store = InMemoryPendingMutationStore()
        let service = PiServiceSpy(
            snapshotResults: [
                .success(snapshot(title: "Controller", message: "history")),
                failure.result,
                failure.result,
            ],
            streams: [stream.stream]
        )
        let (coordinator, defaults) = makeCoordinator(service: service, pendingStore: store) { _, _ in }
        defer {
            coordinator.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        bind(coordinator, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { service.eventClientIDs == ["controller"] }
        stream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { coordinator.viewState(for: "conversation")?.conversation.role == .controller }

        await expectPiServiceError(failure.expectedError) {
            try await coordinator.send(text: "same", delivery: nil, conversationID: "conversation")
        }
        await expectPiServiceError(failure.expectedError) {
            try await coordinator.send(text: "same", delivery: nil, conversationID: "conversation")
        }

        let retained = try store.load()["conversation"]
        #expect(retained?.receipt != nil)
        #expect(service.mutationContexts.count == 1)
        #expect(Set(service.mutationContexts.map(\.idempotencyKey)).count == 1)
    }

    @Test
    @MainActor
    func `expired unresolved mutation remains fail closed across restart`() async throws {
        let store = InMemoryPendingMutationStore()
        let firstStream = ControlledEventStream()
        let firstService = PiServiceSpy(
            snapshots: [snapshot(title: "Controller", message: "history")],
            streams: [firstStream.stream]
        )
        firstService.failNextMutation(with: PiServiceError.timedOut)
        firstService.enqueueReceipt(.success(.pending(sessionId: "session")))
        let (first, defaults) = makeCoordinator(service: firstService, pendingStore: store) { _, _ in }
        bind(first, conversationID: "conversation", sessionID: "session", clientID: "controller")
        try await waitUntil { firstService.eventClientIDs == ["controller"] }
        firstStream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { first.viewState(for: "conversation")?.conversation.role == .controller }
        await #expect(throws: PiCoordinatorError.mutationPending) {
            try await first.send(text: "same", delivery: nil, conversationID: "conversation")
        }
        try store.expireMutation(for: "conversation")
        first.activate(conversationID: nil)

        let secondStream = ControlledEventStream()
        let secondService = PiServiceSpy(
            snapshots: [snapshot(title: "Controller", message: "history")],
            streams: [secondStream.stream]
        )
        let second = PiSessionCoordinator(
            defaults: defaults,
            profileProvider: { PiServerProfile(baseURL: URL(string: "https://pi.example.test")!, token: nil) },
            serviceFactory: { _ in secondService },
            pendingMutationStore: store,
            reconnectDelay: { _ in },
            renderOverride: { _, _ in }
        )
        defer {
            second.unbind(conversationID: "conversation")
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        second.activate(conversationID: "conversation")
        try await waitUntil { secondService.eventClientIDs == ["controller"] }
        secondStream.yield(controllerEvent(id: "1", clientID: "controller"))
        try await waitUntil { second.viewState(for: "conversation")?.conversation.role == .controller }

        await #expect(throws: PiCoordinatorError.mutationInFlight) {
            try await second.send(text: "same", delivery: nil, conversationID: "conversation")
        }

        #expect(secondService.mutationContexts.isEmpty)
        let retained = try store.load()["conversation"]
        #expect(retained != nil)
        #expect(retained?.expiresAt ?? .distantFuture < Date())
    }

    @MainActor
    private func expectPiServiceError(
        _ expected: PiServiceError,
        operation: @MainActor () async throws -> Void
    ) async {
        do {
            try await operation()
            Issue.record("Expected \(expected)")
        } catch let error as PiServiceError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @MainActor
    private func makeCoordinator(
        service: any PiServiceProtocol,
        pendingStore: any PiPendingMutationStoring = InMemoryPendingMutationStore(),
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
            pendingMutationStore: pendingStore,
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
    title _: String,
    message: String,
    sessionID: String = "session",
    revision: Int = 1,
    lastEventID: String? = nil,
    streaming: Bool = false,
    model: PiGatewayWire.Snapshot.Configuration.Model? = nil,
    thinkingLevel: PiGatewayWire.ThinkingLevel = .off,
    controllerClientID: String? = nil
) -> PiGatewayWire.Snapshot {
    PiGatewayWire.Snapshot(
        contract: PiGatewayWire.contract,
        sessionId: sessionID,
        repositoryId: "/repo",
        revision: revision,
        lastEventId: lastEventID ?? String(max(0, revision - 1)),
        lifecycle: .idle,
        runtime: .running,
        run: .init(status: streaming ? .running : .idle, operationId: streaming ? "operation-active" : nil),
        controller: .init(clientId: controllerClientID, leaseExpiresAt: controllerClientID == nil ? nil : Date().addingTimeInterval(60)),
        configuration: .init(model: model, thinkingLevel: thinkingLevel),
        messages: [.init(
            id: "message",
            role: .assistant,
            status: streaming ? .streaming : .completed,
            content: [.init(type: .text, text: message, toolCallId: nil, attachmentId: nil)]
        )],
        attachments: []
    )
}

private func attachmentModel() -> PiGatewayWire.Model {
    .init(
        provider: "test", id: "vision", name: "Vision", reasoning: false,
        input: [.text, .image], thinkingLevels: [.off], contextWindow: nil,
        maxOutputTokens: nil,
        attachments: .init(
            supported: true, kinds: [.image], mediaTypes: ["image/png"],
            maxBytes: 1_000_000, maxCount: 4
        )
    )
}

private func reasoningModel() -> PiGatewayWire.Model {
    .init(
        provider: "test", id: "reasoning", name: "Reasoning", reasoning: true,
        input: [.text], thinkingLevels: [.off, .high], contextWindow: nil,
        maxOutputTokens: nil,
        attachments: .init(supported: false, kinds: [], mediaTypes: [], maxBytes: 0, maxCount: 0)
    )
}

private func uploadedAttachment(id: String, name: String, data: Data) -> PiGatewayWire.Attachment {
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return .init(
        attachmentId: id,
        fileName: name,
        mediaType: "image/png",
        byteLength: data.count,
        sha256: digest,
        status: .ready,
        expiresAt: Date().addingTimeInterval(3_600)
    )
}

private func testDiscovery(mutationTimeoutMs: Int = 1_000) -> PiGatewayWire.Discovery {
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
            readTimeoutMs: 1_000, mutationTimeoutMs: mutationTimeoutMs, sseConnectTimeoutMs: 1_000,
            replayRetentionEvents: 100, replayRetentionSeconds: 100,
            idempotencyRetentionSeconds: 86_400, attachmentMaxBytes: 1_000_000,
            attachmentTotalBytes: 2_000_000, attachmentsPerPrompt: 4, attachmentUploadTimeoutMs: 1_000,
            attachmentDownloadTimeoutMs: 1_000, attachmentMediaTypes: ["image/png"],
            attachmentDigestAlgorithm: "sha-256"
        )
    )
}

private func controllerEvent(id: String, clientID: String?) -> PiGatewayWire.Event {
    let controller = clientID.map { #""\#($0)""# } ?? "null"
    let json = #"{"contract":"pi-gateway/1.0","id":"\#(id)","sessionId":"session","sessionRevision":1,"occurredAt":"2026-10-13T08:00:00.000Z","type":"controller.changed","data":{"previousControllerClientId":null,"controllerClientId":\#(controller),"reason":"takeover"}}"#
    return try! JSONDecoder.piGateway.decode(PiGatewayWire.Event.self, from: Data(json.utf8))
}

private func operationAcceptedEvent(
    id: String,
    operationID: String,
    command: String,
    revision: Int = 2
) -> PiGatewayWire.Event {
    let json = #"{"contract":"pi-gateway/1.0","id":"\#(id)","sessionId":"session","sessionRevision":\#(revision),"occurredAt":"2026-10-13T08:00:00.000Z","type":"operation.accepted","data":{"operationId":"\#(operationID)","command":"\#(command)","retryOfOperationId":null}}"#
    return try! JSONDecoder.piGateway.decode(PiGatewayWire.Event.self, from: Data(json.utf8))
}

private func operationSettledEvent(
    id: String,
    operationID: String,
    status: String,
    revision: Int = 2
) -> PiGatewayWire.Event {
    let error = status == "failed"
        ? #"{"code":"operation_failed","message":"Operation failed","retryable":true}"#
        : "null"
    let json = #"{"contract":"pi-gateway/1.0","id":"\#(id)","sessionId":"session","sessionRevision":\#(revision),"occurredAt":"2026-10-13T08:00:00.100Z","type":"operation.settled","data":{"operationId":"\#(operationID)","status":"\#(status)","retryOfOperationId":null,"error":\#(error)}}"#
    return try! JSONDecoder.piGateway.decode(PiGatewayWire.Event.self, from: Data(json.utf8))
}

private func finishedStream() -> AsyncThrowingStream<PiGatewayWire.Event, Error> {
    AsyncThrowingStream { $0.finish() }
}

private func failedStream() -> AsyncThrowingStream<PiGatewayWire.Event, Error> {
    AsyncThrowingStream { $0.finish(throwing: PiServiceError.connectionLost) }
}

private func finiteStream(_ events: [PiGatewayWire.Event]) -> AsyncThrowingStream<PiGatewayWire.Event, Error> {
    AsyncThrowingStream { continuation in
        events.forEach { continuation.yield($0) }
        continuation.finish()
    }
}

private func pendingStream() -> AsyncThrowingStream<PiGatewayWire.Event, Error> {
    AsyncThrowingStream { _ in }
}

private final class ControlledEventStream: @unchecked Sendable {
    let stream: AsyncThrowingStream<PiGatewayWire.Event, Error>
    private let continuation: AsyncThrowingStream<PiGatewayWire.Event, Error>.Continuation

    init() {
        var continuation: AsyncThrowingStream<PiGatewayWire.Event, Error>.Continuation!
        stream = AsyncThrowingStream { continuation = $0 }
        self.continuation = continuation
    }

    func yield(_ event: PiGatewayWire.Event) {
        continuation.yield(event)
    }

    func finish(throwing error: Error? = nil) {
        if let error { continuation.finish(throwing: error) } else { continuation.finish() }
    }
}

private final class PiServiceSpy: PiServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshotResults: [Result<PiGatewayWire.Snapshot, Error>]
    private var streams: [AsyncThrowingStream<PiGatewayWire.Event, Error>]
    private var stateCalls = 0
    private var sentCommands: [PiConversationAction] = []
    private var connectedClientIDs: [String] = []
    private var cancellations = 0
    private var mutationFailures: [Error] = []
    private var queuedOperationIDs: [String] = []
    private var contexts: [PiMutationContext] = []
    private var receiptResults: [Result<PiGatewayWire.MutationReceiptLookup, Error>] = []
    private var availableModelValues: [PiGatewayWire.Model]
    private let discoveryValue: PiGatewayWire.Discovery
    private var uploadResults: [Result<PiGatewayWire.Attachment, Error>] = []
    private var recordedUploadKeys: [String] = []
    private var uploadSuspension: (@Sendable () async -> Void)?
    private var snapshotSuspension: (@Sendable () async -> Void)?

    init(
        snapshots: [PiGatewayWire.Snapshot],
        streams: [AsyncThrowingStream<PiGatewayWire.Event, Error>],
        models: [PiGatewayWire.Model] = [],
        discovery: PiGatewayWire.Discovery = testDiscovery()
    ) {
        snapshotResults = snapshots.map(Result.success)
        self.streams = streams
        availableModelValues = models
        discoveryValue = discovery
    }

    init(
        snapshotResults: [Result<PiGatewayWire.Snapshot, Error>],
        streams: [AsyncThrowingStream<PiGatewayWire.Event, Error>],
        models: [PiGatewayWire.Model] = [],
        discovery: PiGatewayWire.Discovery = testDiscovery()
    ) {
        self.snapshotResults = snapshotResults
        self.streams = streams
        availableModelValues = models
        discoveryValue = discovery
    }

    var stateCallCount: Int { lock.withLock { stateCalls } }
    var commands: [PiConversationAction] { lock.withLock { sentCommands } }
    var eventClientIDs: [String] { lock.withLock { connectedClientIDs } }
    var cancelCount: Int { lock.withLock { cancellations } }
    var mutationContexts: [PiMutationContext] { lock.withLock { contexts } }
    var uploadKeys: [String] { lock.withLock { recordedUploadKeys } }

    func failNextMutation(with error: Error) { lock.withLock { mutationFailures.append(error) } }
    func enqueueOperationIDs(_ values: [String]) { lock.withLock { queuedOperationIDs.append(contentsOf: values) } }
    func enqueueReceipt(_ result: Result<PiGatewayWire.MutationReceiptLookup, Error>) {
        lock.withLock { receiptResults.append(result) }
    }
    func suspendUploads(_ operation: @escaping @Sendable () async -> Void) {
        lock.withLock { uploadSuspension = operation }
    }
    func clearSnapshotSuspension() { lock.withLock { snapshotSuspension = nil } }

    func suspendSnapshots(_ operation: @escaping @Sendable () async -> Void) {
        lock.withLock { snapshotSuspension = operation }
    }

    func enqueueUpload(_ result: Result<PiGatewayWire.Attachment, Error>) {
        lock.withLock { uploadResults.append(result) }
    }

    func cancelAllRequests() async { lock.withLock { cancellations += 1 } }

    func discover() async throws -> PiGatewayWire.Discovery { discoveryValue }
    func listModels() async throws -> [PiGatewayWire.Model] { lock.withLock { availableModelValues } }

    func snapshot(sessionID _: String) async throws -> PiGatewayWire.Snapshot {
        let value = try lock.withLock {
            let index = min(stateCalls, snapshotResults.count - 1)
            stateCalls += 1
            return try snapshotResults[index].get()
        }
        if let suspension = lock.withLock({ snapshotSuspension }) { await suspension() }
        return value
    }

    func events(sessionID _: String, clientID: String, afterEventID _: String) -> AsyncThrowingStream<PiGatewayWire.Event, Error> {
        lock.withLock {
            connectedClientIDs.append(clientID)
            return streams.isEmpty ? pendingStream() : streams.removeFirst()
        }
    }

    func mutate(
        _ action: PiConversationAction,
        sessionID: String,
        clientID _: String,
        context: PiMutationContext
    ) async throws -> PiGatewayWire.MutationReceipt {
        let result = lock.withLock { () -> (Error?, String) in
            sentCommands.append(action)
            contexts.append(context)
            let failure = mutationFailures.isEmpty ? nil : mutationFailures.removeFirst()
            let operationID = queuedOperationIDs.isEmpty ? "operation" : queuedOperationIDs.removeFirst()
            return (failure, operationID)
        }
        if let failure = result.0 { throw failure }
        return .init(
            sessionId: sessionID,
            revision: context.revision + 1,
            operationId: result.1,
            afterEventId: "0"
        )
    }

    func mutationReceipt(
        sessionID _: String,
        idempotencyKey _: String,
        clientID _: String
    ) async throws -> PiGatewayWire.MutationReceiptLookup {
        try lock.withLock {
            guard !receiptResults.isEmpty else { throw PiServiceError.invalidResponse }
            return try receiptResults.removeFirst().get()
        }
    }

    func uploadAttachment(
        data _: Data,
        fileName _: String,
        mediaType _: String,
        repositoryID _: String,
        idempotencyKey: String
    ) async throws -> PiGatewayWire.Attachment {
        let (result, suspension) = try lock.withLock {
            recordedUploadKeys.append(idempotencyKey)
            guard !uploadResults.isEmpty else { throw PiServiceError.invalidResponse }
            return (uploadResults.removeFirst(), uploadSuspension)
        }
        await suspension?()
        return try result.get()
    }
}

private final class InMemoryPendingMutationStore: PiPendingMutationStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: PiPendingMutationRecord] = [:]
    private var creation: PiPendingCreationRecord?
    private var uploads: [String: PiPendingAttachmentBatch] = [:]

    var attachmentUploads: [String: PiPendingAttachmentBatch] { lock.withLock { uploads } }
    var mutations: [String: PiPendingMutationRecord] { lock.withLock { records } }

    func load() throws -> [String: PiPendingMutationRecord] { lock.withLock { records } }
    func save(_ records: [String: PiPendingMutationRecord]) throws { lock.withLock { self.records = records } }
    func loadCreation() throws -> PiPendingCreationRecord? { lock.withLock { creation } }
    func saveCreation(_ record: PiPendingCreationRecord?) throws { lock.withLock { creation = record } }
    func loadAttachmentUploads() throws -> [String: PiPendingAttachmentBatch] { lock.withLock { uploads } }
    func saveAttachmentUploads(_ records: [String: PiPendingAttachmentBatch]) throws {
        lock.withLock { uploads = records }
    }

    func expireMutation(for conversationID: String) throws {
        lock.withLock {
            guard let record = records[conversationID] else { return }
            records[conversationID] = .init(
                sessionID: record.sessionID,
                clientID: record.clientID,
                action: record.action,
                context: record.context,
                requestDigest: record.requestDigest,
                receipt: record.receipt,
                createdAt: record.createdAt,
                expiresAt: .distantPast
            )
        }
    }
}

private enum PiAppliedSnapshotFailure: CaseIterable, Sendable {
    case malformed
    case stale
    case unauthorized

    var result: Result<PiGatewayWire.Snapshot, Error> {
        switch self {
        case .malformed: .failure(PiServiceError.invalidResponse)
        case .stale: .success(snapshot(title: "Stale", message: "history", revision: 1))
        case .unauthorized: .failure(PiServiceError.authenticationRequired)
        }
    }

    var expectedError: PiServiceError {
        switch self {
        case .malformed, .stale: .invalidResponse
        case .unauthorized: .authenticationRequired
        }
    }
}

private final class SuspendedPiService: PiServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let eventStream = ControlledEventStream()
    private var continuations: [String: CheckedContinuation<PiGatewayWire.Snapshot, Error>] = [:]

    var pendingSessionIDs: Set<String> { lock.withLock { Set(continuations.keys) } }

    func resume(sessionID: String, with state: PiGatewayWire.Snapshot) {
        lock.withLock { continuations.removeValue(forKey: sessionID) }?.resume(returning: state)
    }

    func discover() async throws -> PiGatewayWire.Discovery { testDiscovery() }
    func listModels() async throws -> [PiGatewayWire.Model] { [] }

    func snapshot(sessionID: String) async throws -> PiGatewayWire.Snapshot {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { continuations[sessionID] = continuation }
        }
    }

    func events(sessionID _: String, clientID _: String, afterEventID _: String) -> AsyncThrowingStream<PiGatewayWire.Event, Error> {
        eventStream.stream
    }
}

private actor SuspendedAttachmentUpload {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}
