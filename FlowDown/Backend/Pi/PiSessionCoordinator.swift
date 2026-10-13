import CryptoKit
import Foundation
import Storage

extension Notification.Name {
    static let piSessionDidChange = Notification.Name("PiSessionDidChange")
}

enum JonworkSurfacePolicy {
    static let productionAllowsLegacyConversations = false
    static let productionIncludesLegacyMenuCommands = false
    static let productionAllowsLegacyProviderNetworking = false

    static var allowsLegacyConversations: Bool {
        #if DEBUG
            return true
        #else
            return productionAllowsLegacyConversations
        #endif
    }

    static var allowsLegacyProviderNetworking: Bool {
        #if DEBUG
            return true
        #else
            return productionAllowsLegacyProviderNetworking
        #endif
    }

    static func permitsConversation(
        hasJonworkBinding: Bool,
        allowsLegacyConversations: Bool = allowsLegacyConversations
    ) -> Bool {
        return hasJonworkBinding || allowsLegacyConversations
    }

    static func shouldCreateInitialConversation(
        isConversationListEmpty: Bool,
        allowsLegacyConversations: Bool = allowsLegacyConversations
    ) -> Bool {
        return isConversationListEmpty && allowsLegacyConversations
    }

    static func permitsLegacyConversationActions(
        hasJonworkBinding: Bool,
        allowsLegacyConversations: Bool = allowsLegacyConversations
    ) -> Bool {
        return allowsLegacyConversations && !hasJonworkBinding
    }

    static func permitsLegacyProviderAccess(hasJonworkBinding: Bool) -> Bool {
        return !hasJonworkBinding
    }
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
        case restoring
        case connected
        case offline(String)
    }

    struct ViewState: Equatable, Sendable {
        enum PendingAction: Equatable, Sendable {
            case takeover
            case other
        }

        let conversation: PiConversationState
        let connection: ConnectionPhase
        let pendingAction: PendingAction?

        init(
            conversation: PiConversationState,
            connection: ConnectionPhase,
            pendingAction: PendingAction? = nil
        ) {
            self.conversation = conversation
            self.connection = connection
            self.pendingAction = pendingAction
        }
    }

    struct AttachmentPolicy: Equatable, Sendable {
        let allowsImages: Bool
        let allowsFiles: Bool
        let allowsCamera: Bool
        let allowsPhotoLibrary: Bool
        let allowsFilePicker: Bool
        let mediaTypes: Set<String>
        let maximumBytes: Int
        let maximumCount: Int

        var allowsAny: Bool { allowsImages || allowsFiles }
    }

    private let bindingsKey = "Pi.Session.Bindings"
    private let defaults: UserDefaults
    private let profileProvider: () throws -> PiServerProfile?
    private let serviceFactory: (PiServerProfile) throws -> any PiServiceProtocol
    private let reconnectDelay: (Int) async throws -> Void
    private let renderOverride: ((Conversation.ID, PiConversationState) -> Void)?
    private var bindings: [Conversation.ID: Binding]
    private var reducers: [Conversation.ID: PiSessionReducer] = [:]
    private var adapters: [Conversation.ID: PiEventAdapter] = [:]
    private var discoveries: [Conversation.ID: PiGatewayWire.Discovery] = [:]
    private var availableModels: [Conversation.ID: [PiGatewayWire.Model]] = [:]
    private var mutationsInFlight: Set<Conversation.ID> = []
    private var pendingActions: [Conversation.ID: ViewState.PendingAction] = [:]
    private let pendingMutationStore: any PiPendingMutationStoring
    private var pendingMutationStoreLoadFailed = false
    private var pendingMutations: [Conversation.ID: PiPendingMutationRecord] = [:]
    private var pendingAttachmentBatches: [Conversation.ID: PiPendingAttachmentBatch] = [:]
    private var lastMutationReceipts: [Conversation.ID: PiGatewayWire.MutationReceipt] = [:]
    private struct OperationSettlement: Sendable {
        let status: String
        let failure: PiConversationFailure?
    }
    private var operationSettlements: [Conversation.ID: [String: OperationSettlement]] = [:]
    private var phases: [Conversation.ID: ConnectionPhase] = [:]
    private var services: [Conversation.ID: any PiServiceProtocol] = [:]
    private var eventTasks: [Conversation.ID: Task<Void, Never>] = [:]
    private var renderTasks: [Conversation.ID: Task<Void, Never>] = [:]
    private var generations: [Conversation.ID: UInt64] = [:]
    private var remoteMessageIndex: [Conversation.ID: [String: Message.ID]] = [:]
    private var projectedMessages: [Conversation.ID: [String: PiPresentationMessage]] = [:]
    private var migratedConversations: Set<Conversation.ID> = []
    private var activeConversationID: Conversation.ID?
    private var authenticatedServiceBaseURL: URL?
    private var authenticatedServiceFactory: (() throws -> any PiServiceProtocol)?

    init(
        defaults: UserDefaults = .standard,
        profileProvider: (() throws -> PiServerProfile?)? = nil,
        serviceFactory: ((PiServerProfile) throws -> any PiServiceProtocol)? = nil,
        pendingMutationStore: any PiPendingMutationStoring = PiPendingMutationStore(),
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
        self.pendingMutationStore = pendingMutationStore
        bindings = Self.decodeBindings(defaults.data(forKey: bindingsKey))
        do {
            pendingMutations = try pendingMutationStore.load()
            pendingAttachmentBatches = try pendingMutationStore.loadAttachmentUploads()
        } catch {
            pendingMutationStoreLoadFailed = true
            pendingMutations = [:]
            pendingAttachmentBatches = [:]
        }
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
            connection: phases[conversationID] ?? .connecting,
            pendingAction: pendingActions[conversationID]
        )
    }

    func conversationID(sessionID: String, repository: String, baseURL: URL) -> Conversation.ID? {
        bindings.first(where: {
            $0.value.sessionID == sessionID
                && $0.value.repository == repository
                && $0.value.baseURL == baseURL
        })?.key
    }

    func bind(
        conversationID: Conversation.ID,
        sessionID: String,
        repository: String,
        clientID: String,
        baseURL: URL
    ) {
        for (existingConversationID, binding) in bindings where existingConversationID != conversationID
            && binding.sessionID == sessionID
            && binding.repository == repository
            && binding.baseURL == baseURL
        {
            unbind(conversationID: existingConversationID)
        }
        cancelConnection(conversationID)
        bindings[conversationID] = .init(
            sessionID: sessionID,
            repository: repository,
            clientID: clientID,
            baseURL: baseURL
        )
        reducers[conversationID] = nil
        adapters[conversationID] = nil
        discoveries[conversationID] = nil
        availableModels[conversationID] = nil
        lastMutationReceipts[conversationID] = nil
        operationSettlements[conversationID] = nil
        phases[conversationID] = nil
        clearProjection(conversationID)
        persistBindings()
        activate(conversationID: conversationID)
    }

    func unbind(conversationID: Conversation.ID) {
        cancelConnection(conversationID)
        clearProjection(conversationID)
        reducers[conversationID] = nil
        adapters[conversationID] = nil
        discoveries[conversationID] = nil
        availableModels[conversationID] = nil
        mutationsInFlight.remove(conversationID)
        pendingActions[conversationID] = nil
        var retained = pendingMutations
        retained[conversationID] = nil
        do {
            try pendingMutationStore.save(retained)
            pendingMutations = retained
        } catch {}
        lastMutationReceipts[conversationID] = nil
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
        adapters.removeAll()
        discoveries.removeAll()
        availableModels.removeAll()
        mutationsInFlight.removeAll()
        pendingActions.removeAll()
        pendingMutations.removeAll()
        try? persistPendingMutations()
        lastMutationReceipts.removeAll()
        operationSettlements.removeAll()
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

    func revokeAllCredentialsAndState() async {
        let activeServices = Array(services.values)
        authenticatedServiceBaseURL = nil
        authenticatedServiceFactory = nil
        unbindAll()
        pendingAttachmentBatches.removeAll()
        try? pendingMutationStore.saveAttachmentUploads([:])
        for service in activeServices {
            await service.cancelAllRequests()
        }
    }

    func installAuthenticatedServiceFactory(
        baseURL: URL,
        factory: @escaping () throws -> any PiServiceProtocol
    ) {
        authenticatedServiceBaseURL = baseURL
        authenticatedServiceFactory = factory
    }

    func clearAuthenticatedServiceFactory() {
        authenticatedServiceBaseURL = nil
        authenticatedServiceFactory = nil
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

    func suspendActiveSession() {
        guard let activeConversationID else { return }
        cancelConnection(activeConversationID)
        phases[activeConversationID] = .connecting
        notify(activeConversationID)
    }

    func refreshActiveSession() {
        guard let activeConversationID, bindings[activeConversationID] != nil else { return }
        cancelConnection(activeConversationID)
        connect(conversationID: activeConversationID)
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
        phases[conversationID] = reducers[conversationID] == nil ? .restoring : .connecting
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
                    let service: any PiServiceProtocol
                    if authenticatedServiceBaseURL == profile.baseURL,
                       let authenticatedServiceFactory
                    {
                        service = try authenticatedServiceFactory()
                    } else {
                        service = try serviceFactory(profile)
                    }
                    guard isCurrent(conversationID, binding: binding, generation: generation) else { return }
                    services[conversationID] = service
                    let clientID = binding.clientID
                    let discovery = try await service.discover()
                    let models = try await service.listModels()
                    let snapshot = try await service.snapshot(sessionID: binding.sessionID)
                    try Task.checkCancellation()
                    guard isCurrent(conversationID, binding: binding, generation: generation) else { return }
                    var adapter = PiEventAdapter(
                        replayRetentionEvents: discovery.limits.replayRetentionEvents
                    )
                    let replacement = try adapter.replace(with: snapshot, clientID: clientID)
                    var reducer = PiSessionReducer()
                    reducer.reduce(replacement)
                    adapters[conversationID] = adapter
                    reducers[conversationID] = reducer
                    discoveries[conversationID] = discovery
                    availableModels[conversationID] = models
                    phases[conversationID] = .connected
                    render(conversationID)

                    streamStartedAt = .now
                    let replayCursor = pendingConfigurationReceipt(for: conversationID)?.afterEventId
                        ?? snapshot.lastEventId
                    for try await wireEvent in service.events(
                        sessionID: binding.sessionID,
                        clientID: clientID,
                        afterEventID: replayCursor
                    ) {
                        try Task.checkCancellation()
                        guard isCurrent(conversationID, binding: binding, generation: generation) else { return }
                        guard var currentAdapter = adapters[conversationID] else { return }
                        try recordSettlement(from: wireEvent, conversationID: conversationID)
                        if let lastEventID = currentAdapter.lastEventID,
                           try PiGatewayWire.EventID(wireEvent.id) <= lastEventID
                        {
                            continue
                        }
                        let event = try currentAdapter.adapt(wireEvent)
                        var current = reducers[conversationID] ?? reducer
                        current.reduce(event)
                        current.observe(revision: currentAdapter.revision, lastEventID: currentAdapter.lastEventID?.string ?? snapshot.lastEventId)
                        attempt = 0
                        adapters[conversationID] = currentAdapter
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
                    if let error = error as? PiServiceError, !error.isRecoverableTransportFailure { return }
                    if let error = error as? PiAdapterError, !error.requiresSnapshotRecovery { return }
                    attempt += 1
                    do {
                        try await reconnectDelay(attempt)
                        try Task.checkCancellation()
                    } catch {
                        return
                    }
                    guard isCurrent(conversationID, binding: binding, generation: generation) else { return }
                    phases[conversationID] = .restoring
                    notify(conversationID)
                }
            }
        }
    }

    func send(
        text: String,
        attachments: [PiAttachmentUpload] = [],
        delivery: PiConversationAction.Delivery,
        conversationID: Conversation.ID
    ) async throws {
        let context = try commandContext(conversationID)
        guard context.state.role == .controller else { throw PiCoordinatorError.viewer }
        guard !context.state.isReleased else { throw PiCoordinatorError.released }
        guard context.state.isStreaming == (delivery != .prompt) else { throw PiCoordinatorError.sessionStateChanged }
        let attachmentIDs = try await upload(
            attachments,
            text: text,
            delivery: delivery,
            conversationID: conversationID,
            context: context
        )
        try await performMutation(
            .send(text: text, attachmentIDs: attachmentIDs, delivery: delivery),
            conversationID: conversationID
        )
        if pendingAttachmentBatches.removeValue(forKey: conversationID) != nil {
            try pendingMutationStore.saveAttachmentUploads(pendingAttachmentBatches)
        }
    }

    func send(text: String, delivery: PiCommand.Delivery?, conversationID: Conversation.ID) async throws {
        let domainDelivery: PiConversationAction.Delivery = switch delivery {
        case .steer: .steer
        case .followUp: .followUp
        case nil: .prompt
        }
        try await send(text: text, delivery: domainDelivery, conversationID: conversationID)
    }

    func abort(conversationID: Conversation.ID) async throws {
        let context = try commandContext(conversationID)
        guard context.state.role == .controller else { throw PiCoordinatorError.viewer }
        guard !context.state.isReleased else { throw PiCoordinatorError.released }
        guard context.state.isStreaming else { throw PiCoordinatorError.notStreaming }
        try await performMutation(.abort, conversationID: conversationID)
    }

    func retry(conversationID: Conversation.ID) async throws {
        let context = try commandContext(conversationID)
        guard context.state.role == .controller else { throw PiCoordinatorError.viewer }
        guard !context.state.isStreaming,
              let operationID = context.state.lastFailedOperationID
        else { throw PiCoordinatorError.sessionStateChanged }
        try await performMutation(.retry(operationID: operationID), conversationID: conversationID)
    }

    func rename(_ name: String, conversationID: Conversation.ID) async throws {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 200 else { throw PiCoordinatorError.sessionStateChanged }
        try await performMutation(.rename(value), conversationID: conversationID)
    }

    func setModel(provider: String, modelID: String, conversationID: Conversation.ID) async throws {
        guard availableModels[conversationID]?.contains(where: {
            $0.provider == provider && $0.id == modelID
        }) == true else { throw PiCoordinatorError.capabilityUnavailable }
        try await performMutation(.setModel(provider: provider, modelID: modelID), conversationID: conversationID)
    }

    func setThinkingLevel(_ level: PiGatewayWire.ThinkingLevel, conversationID: Conversation.ID) async throws {
        guard let state = reducers[conversationID]?.state,
              let selected = state.model,
              availableModels[conversationID]?.first(where: {
                  $0.provider == selected.provider && $0.id == selected.id
              })?.thinkingLevels.contains(level) == true
        else { throw PiCoordinatorError.capabilityUnavailable }
        try await performMutation(.setThinkingLevel(level), conversationID: conversationID)
    }

    func compact(instructions: String?, conversationID: Conversation.ID) async throws {
        try await performMutation(.compact(instructions: instructions), conversationID: conversationID)
    }

    func takeOver(conversationID: Conversation.ID) async throws {
        let context = try commandContext(conversationID)
        guard context.state.role == .viewer else { throw PiCoordinatorError.alreadyController }
        guard !context.state.isReleased else { throw PiCoordinatorError.released }
        guard !context.state.isStreaming else { throw PiCoordinatorError.streaming }
        try await performMutation(.takeOver, conversationID: conversationID)
    }

    func release(conversationID: Conversation.ID) async throws {
        let context = try commandContext(conversationID)
        guard context.state.role == .controller else { throw PiCoordinatorError.viewer }
        guard !context.state.isReleased else { throw PiCoordinatorError.released }
        try await performMutation(.release, conversationID: conversationID)
    }

    func models(conversationID: Conversation.ID) -> [PiGatewayWire.Model] {
        availableModels[conversationID] ?? []
    }

    func supportsAttachments(conversationID: Conversation.ID, kind: PiAttachmentUpload.Kind) -> Bool {
        guard let policy = attachmentPolicy(conversationID: conversationID) else { return false }
        switch kind {
        case .image: return policy.allowsImages
        case .file: return policy.allowsFiles
        }
    }

    func canAttach(conversationID: Conversation.ID) -> Bool {
        attachmentPolicy(conversationID: conversationID)?.allowsAny == true
    }

    func attachmentPolicy(conversationID: Conversation.ID) -> AttachmentPolicy? {
        guard let discovery = discoveries[conversationID],
              let state = reducers[conversationID]?.state,
              let selected = state.model,
              let model = availableModels[conversationID]?.first(where: {
                  $0.provider == selected.provider && $0.id == selected.id
              })
        else { return nil }
        let sources = Set(discovery.capabilities.attachments.sources)
        let gatewayMediaTypes = Set(
            discovery.capabilities.attachments.mediaTypes
                .map { $0.lowercased() }
        )
        let modelAttachment = model.attachments
        let modelAllowsImages = model.input.contains(.image)
            && modelAttachment.supported
            && modelAttachment.kinds.contains(.image)
        let modelMediaTypes = Set(modelAttachment.mediaTypes.map { $0.lowercased() })
        let allowsImages = discovery.capabilities.attachments.images && modelAllowsImages
        let allowsFiles = discovery.capabilities.attachments.files && model.input.contains(.file)
        return .init(
            allowsImages: allowsImages,
            allowsFiles: allowsFiles,
            allowsCamera: allowsImages && sources.contains(.camera),
            allowsPhotoLibrary: allowsImages && sources.contains(.photoLibrary),
            allowsFilePicker: (allowsImages || allowsFiles) && sources.contains(.filePicker),
            mediaTypes: gatewayMediaTypes.intersection(modelMediaTypes),
            maximumBytes: min(discovery.limits.attachmentMaxBytes, modelAttachment.maxBytes),
            maximumCount: min(discovery.limits.attachmentsPerPrompt, modelAttachment.maxCount)
        )
    }

    func supportsAttachmentMediaType(_ mediaType: String, conversationID: Conversation.ID) -> Bool {
        guard let policy = attachmentPolicy(conversationID: conversationID) else { return false }
        let normalized = mediaType.lowercased()
        let kindAllowed = normalized.hasPrefix("image/") ? policy.allowsImages : policy.allowsFiles
        return kindAllowed && policy.mediaTypes.contains(normalized)
    }

    func selectedModel(conversationID: Conversation.ID) -> PiGatewayWire.Model? {
        guard let state = reducers[conversationID]?.state,
              let selected = state.model,
              let model = availableModels[conversationID]?.first(where: {
                  $0.provider == selected.provider && $0.id == selected.id
              })
        else { return nil }
        return model
    }

    func attachmentMaximumBytes(conversationID: Conversation.ID) -> Int? {
        guard canAttach(conversationID: conversationID) else { return nil }
        return discoveries[conversationID]?.limits.attachmentMaxBytes
    }

    private func performMutation(_ action: PiConversationAction, conversationID: Conversation.ID) async throws {
        guard !pendingMutationStoreLoadFailed else { throw PiServiceError.invalidResponse }
        guard mutationsInFlight.insert(conversationID).inserted else { throw PiCoordinatorError.mutationInFlight }
        pendingActions[conversationID] = action == .takeOver ? .takeover : .other
        notify(conversationID)
        defer {
            mutationsInFlight.remove(conversationID)
            pendingActions[conversationID] = nil
            notify(conversationID)
        }
        let context = try commandContext(conversationID)
        switch action {
        case .takeOver:
            guard context.state.role == .viewer,
                  !context.state.isReleased,
                  !context.state.isStreaming
            else { throw PiCoordinatorError.sessionStateChanged }
        default:
            guard context.state.role == .controller else { throw PiCoordinatorError.viewer }
            guard !context.state.isReleased else { throw PiCoordinatorError.released }
        }
        let pending: PiPendingMutationRecord
        if let existing = pendingMutations[conversationID] {
            guard existing.sessionID == context.binding.sessionID,
                  existing.clientID == context.clientID,
                  existing.action == action,
                  existing.expiresAt > Date(),
                  existing.requestDigest == Self.mutationDigest(
                      sessionID: existing.sessionID,
                      clientID: existing.clientID,
                      action: existing.action,
                      context: existing.context
                  )
            else { throw PiCoordinatorError.mutationInFlight }
            pending = existing
            if let receipt = existing.receipt {
                try await accept(
                    receipt,
                    pending: existing,
                    conversationID: conversationID,
                    service: context.service
                )
                return
            }
            try await resolveAmbiguous(
                pending,
                conversationID: conversationID,
                service: context.service
            )
            return
        } else {
            guard let retention = discoveries[conversationID]?.limits.idempotencyRetentionSeconds else {
                throw PiCoordinatorError.notConnected
            }
            let mutationContext = PiMutationContext(
                idempotencyKey: UUID().uuidString,
                revision: context.state.revision
            )
            let newPending = PiPendingMutationRecord(
                sessionID: context.binding.sessionID,
                clientID: context.clientID,
                action: action,
                context: mutationContext,
                requestDigest: Self.mutationDigest(
                    sessionID: context.binding.sessionID,
                    clientID: context.clientID,
                    action: action,
                    context: mutationContext
                ),
                createdAt: Date(),
                expiresAt: Date().addingTimeInterval(TimeInterval(retention))
            )
            pending = newPending
            pendingMutations[conversationID] = newPending
            try persistPendingMutations()
        }
        do {
            let receipt = try await submit(pending, service: context.service)
            let recorded = try recordReceipt(receipt, pending: pending, conversationID: conversationID)
            try await accept(receipt, pending: recorded, conversationID: conversationID, service: context.service)
        } catch {
            let retained = pendingMutations[conversationID] ?? pending
            if retained.receipt != nil {
                throw error
            }
            if error as? PiServiceError == .conflict {
                try clearPendingMutation(conversationID)
                reconnect(conversationID: conversationID)
                throw error
            }
            if Self.isAmbiguousMutationFailure(error) {
                try await resolveAmbiguous(
                    retained,
                    conversationID: conversationID,
                    service: context.service
                )
            } else {
                try clearPendingMutation(conversationID)
                throw error
            }
        }
    }

    private func submit(
        _ pending: PiPendingMutationRecord,
        service: any PiServiceProtocol
    ) async throws -> PiGatewayWire.MutationReceipt {
        try await service.mutate(
            pending.action,
            sessionID: pending.sessionID,
            clientID: pending.clientID,
            context: pending.context
        )
    }

    private func resolveAmbiguous(
        _ pending: PiPendingMutationRecord,
        conversationID: Conversation.ID,
        service: any PiServiceProtocol
    ) async throws {
        do {
            switch try await service.mutationReceipt(
                sessionID: pending.sessionID,
                idempotencyKey: pending.context.idempotencyKey,
                clientID: pending.clientID
            ) {
            case let .pending(sessionID):
                guard sessionID == pending.sessionID else { throw PiServiceError.invalidResponse }
                throw PiCoordinatorError.mutationPending
            case let .applied(receipt):
                let recorded = try recordReceipt(receipt, pending: pending, conversationID: conversationID)
                try await accept(receipt, pending: recorded, conversationID: conversationID, service: service)
            }
        } catch PiServiceError.mutationNotFound {
            let receipt = try await submit(pending, service: service)
            let recorded = try recordReceipt(receipt, pending: pending, conversationID: conversationID)
            try await accept(receipt, pending: recorded, conversationID: conversationID, service: service)
        } catch {
            throw error
        }
    }

    private func recordReceipt(
        _ receipt: PiGatewayWire.MutationReceipt,
        pending: PiPendingMutationRecord,
        conversationID: Conversation.ID
    ) throws -> PiPendingMutationRecord {
        let recorded = PiPendingMutationRecord(
            sessionID: pending.sessionID,
            clientID: pending.clientID,
            action: pending.action,
            context: pending.context,
            requestDigest: pending.requestDigest,
            receipt: receipt,
            createdAt: pending.createdAt,
            expiresAt: pending.expiresAt
        )
        pendingMutations[conversationID] = recorded
        try persistPendingMutations()
        return recorded
    }

    private func accept(
        _ receipt: PiGatewayWire.MutationReceipt,
        pending: PiPendingMutationRecord,
        conversationID: Conversation.ID,
        service: any PiServiceProtocol
    ) async throws {
        guard receipt.status == .applied,
              receipt.sessionId == pending.sessionID,
              (200 ..< 300).contains(receipt.responseStatus)
        else { throw PiServiceError.invalidResponse }
        if pending.action.requiresSettledConfiguration {
            guard receipt.responseStatus == 202, let operationID = receipt.operationId else {
                throw PiServiceError.invalidResponse
            }
            try await waitForConfigurationSettlement(
                operationID: operationID,
                conversationID: conversationID
            )
        }
        let snapshot = try await service.snapshot(sessionID: pending.sessionID)
        guard snapshot.sessionId == pending.sessionID,
              snapshot.revision >= receipt.revision,
              pending.action.matchesAuthoritativeConfiguration(snapshot.configuration)
        else { throw PiServiceError.invalidResponse }
        guard let discovery = discoveries[conversationID] else {
            throw PiServiceError.capabilityUnavailable(["discovery"])
        }
        var adapter = PiEventAdapter(
            replayRetentionEvents: discovery.limits.replayRetentionEvents
        )
        let replacement = try adapter.replace(with: snapshot, clientID: pending.clientID)
        var reducer = PiSessionReducer()
        reducer.reduce(replacement)
        adapters[conversationID] = adapter
        reducers[conversationID] = reducer
        lastMutationReceipts[conversationID] = receipt
        try clearPendingMutation(conversationID)
        if let operationID = receipt.operationId {
            operationSettlements[conversationID]?[operationID] = nil
        }
        render(conversationID)
    }

    private func pendingConfigurationReceipt(
        for conversationID: Conversation.ID
    ) -> PiGatewayWire.MutationReceipt? {
        guard let pending = pendingMutations[conversationID],
              pending.action.requiresSettledConfiguration
        else { return nil }
        return pending.receipt
    }

    private func waitForConfigurationSettlement(
        operationID: String,
        conversationID: Conversation.ID
    ) async throws {
        guard let timeout = discoveries[conversationID]?.limits.mutationTimeoutMs else {
            throw PiCoordinatorError.notConnected
        }
        let deadline = ContinuousClock.now + .milliseconds(timeout)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            if let settlement = operationSettlements[conversationID]?[operationID] {
                guard settlement.status == "completed" else {
                    try clearPendingMutation(conversationID)
                    operationSettlements[conversationID]?[operationID] = nil
                    if let failure = settlement.failure {
                        throw PiServiceError.gateway(code: failure.code, retryable: failure.retryable)
                    }
                    throw PiServiceError.gateway(code: "operation_\(settlement.status)", retryable: false)
                }
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw PiServiceError.timedOut
    }

    private func recordSettlement(
        from event: PiGatewayWire.Event,
        conversationID: Conversation.ID
    ) throws {
        guard event.type == "operation.settled" else { return }
        let data = event.data
        guard Set(data.keys) == ["operationId", "status", "retryOfOperationId", "error"],
              let operationID = data["operationId"]?.stringValue,
              let status = data["status"]?.stringValue,
              ["completed", "aborted", "failed"].contains(status),
              data["retryOfOperationId"] == .null || data["retryOfOperationId"]?.stringValue != nil
        else { throw PiAdapterError.invalidPayload("operation.settled") }
        let failure: PiConversationFailure?
        if status == "failed" {
            guard let object = data["error"]?.objectValue,
                  Set(object.keys) == ["code", "message", "retryable"],
                  let code = object["code"]?.stringValue,
                  let message = object["message"]?.stringValue,
                  case let .bool(retryable) = object["retryable"]
            else { throw PiAdapterError.invalidPayload("error") }
            failure = .init(code: code, message: message, retryable: retryable)
        } else {
            guard data["error"] == .null else { throw PiAdapterError.invalidPayload("error") }
            failure = nil
        }
        operationSettlements[conversationID, default: [:]][operationID] = .init(
            status: status,
            failure: failure
        )
        if operationSettlements[conversationID, default: [:]].count > 64,
           let staleOperationID = operationSettlements[conversationID]?.keys.first(where: { $0 != operationID })
        {
            operationSettlements[conversationID]?[staleOperationID] = nil
        }
    }

    private static func mutationDigest(
        sessionID: String,
        clientID: String,
        action: PiConversationAction,
        context: PiMutationContext
    ) -> String {
        struct Canonical: Encodable {
            let sessionID: String
            let clientID: String
            let action: PiConversationAction
            let context: PiMutationContext
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(Canonical(
            sessionID: sessionID,
            clientID: clientID,
            action: action,
            context: context
        ))) ?? Data()
        return Data(SHA256.hash(data: data)).base64EncodedString()
    }

    private func persistPendingMutations() throws {
        try pendingMutationStore.save(pendingMutations)
    }

    private func clearPendingMutation(_ conversationID: Conversation.ID) throws {
        var updated = pendingMutations
        updated[conversationID] = nil
        try pendingMutationStore.save(updated)
        pendingMutations = updated
    }

    private static func isAmbiguousMutationFailure(_ error: Error) -> Bool {
        guard let error = error as? PiServiceError else { return false }
        switch error {
        case .timedOut, .connectionLost, .networkUnavailable, .transportFailure:
            return true
        default:
            return false
        }
    }

    private func upload(
        _ attachments: [PiAttachmentUpload],
        text: String,
        delivery: PiConversationAction.Delivery,
        conversationID: Conversation.ID,
        context: (binding: Binding, service: any PiServiceProtocol, clientID: String, state: PiConversationState)
    ) async throws -> [String] {
        guard !pendingMutationStoreLoadFailed else { throw PiServiceError.invalidResponse }
        if attachments.isEmpty {
            guard pendingAttachmentBatches[conversationID] == nil else {
                throw PiCoordinatorError.mutationInFlight
            }
            return []
        }
        guard let discovery = discoveries[conversationID] else { throw PiCoordinatorError.capabilityUnavailable }
        let sizes = try attachments.map { try $0.byteCount() }
        guard attachments.count <= discovery.limits.attachmentsPerPrompt,
              sizes.reduce(0, +) <= discovery.limits.attachmentTotalBytes
        else { throw PiCoordinatorError.attachmentLimitExceeded }
        var prepared: [(data: Data, record: PiPendingAttachmentUploadRecord)] = []
        for (attachment, size) in zip(attachments, sizes) {
            guard size <= discovery.limits.attachmentMaxBytes,
                  supportsAttachments(conversationID: conversationID, kind: attachment.kind),
                  modelSupports(attachment.kind, state: context.state, conversationID: conversationID),
                  discovery.limits.attachmentMediaTypes.contains(attachment.mediaType)
            else { throw PiCoordinatorError.capabilityUnavailable }
            let data = try await attachment.load(maximumBytes: discovery.limits.attachmentMaxBytes)
            let normalizedFileName = attachment.fileName.precomposedStringWithCanonicalMapping
            guard !normalizedFileName.isEmpty,
                  normalizedFileName != ".",
                  normalizedFileName != "..",
                  !normalizedFileName.contains("\0"),
                  !normalizedFileName.contains("/"),
                  !normalizedFileName.contains("\\"),
                  normalizedFileName.lengthOfBytes(using: .utf8) <= 255
            else { throw PiServiceError.invalidResponse }
            let digestBytes = Data(SHA256.hash(data: data))
            prepared.append((
                data,
                .init(
                    repositoryID: context.binding.repository,
                    digest: digestBytes.base64EncodedString(),
                    fileName: normalizedFileName,
                    mediaType: attachment.mediaType,
                    byteCount: data.count,
                    idempotencyKey: UUID().uuidString,
                    attachmentID: nil,
                    serverSHA256: nil
                )
            ))
        }
        let requestDigest = Self.attachmentRequestDigest(
            sessionID: context.binding.sessionID,
            text: text,
            delivery: delivery,
            uploads: prepared.map(\.record)
        )
        var batch: PiPendingAttachmentBatch
        if let existing = pendingAttachmentBatches[conversationID] {
            guard existing.sessionID == context.binding.sessionID,
                  existing.repositoryID == context.binding.repository,
                  existing.requestDigest == requestDigest,
                  existing.expiresAt > Date(),
                  Self.sameAttachmentInputs(existing.uploads, prepared.map(\.record))
            else { throw PiCoordinatorError.mutationInFlight }
            batch = existing
        } else {
            batch = .init(
                sessionID: context.binding.sessionID,
                repositoryID: context.binding.repository,
                requestDigest: requestDigest,
                uploads: prepared.map(\.record),
                createdAt: Date(),
                expiresAt: Date().addingTimeInterval(
                    TimeInterval(discovery.limits.idempotencyRetentionSeconds)
                )
            )
            pendingAttachmentBatches[conversationID] = batch
            try pendingMutationStore.saveAttachmentUploads(pendingAttachmentBatches)
        }

        for index in batch.uploads.indices where batch.uploads[index].attachmentID == nil {
            let pending = batch.uploads[index]
            let uploaded = try await context.service.uploadAttachment(
                data: prepared[index].data,
                fileName: pending.fileName,
                mediaType: pending.mediaType,
                repositoryID: pending.repositoryID,
                idempotencyKey: pending.idempotencyKey
            )
            let expectedHexDigest = SHA256.hash(data: prepared[index].data)
                .map { String(format: "%02x", $0) }
                .joined()
            guard uploaded.status == .ready,
                  uploaded.fileName == pending.fileName,
                  uploaded.mediaType == pending.mediaType,
                  uploaded.byteLength == pending.byteCount,
                  uploaded.sha256 == expectedHexDigest
            else { throw PiServiceError.invalidResponse }
            var uploads = batch.uploads
            uploads[index] = .init(
                repositoryID: pending.repositoryID,
                digest: pending.digest,
                fileName: pending.fileName,
                mediaType: pending.mediaType,
                byteCount: pending.byteCount,
                idempotencyKey: pending.idempotencyKey,
                attachmentID: uploaded.attachmentId,
                serverSHA256: uploaded.sha256
            )
            batch = .init(
                sessionID: batch.sessionID,
                repositoryID: batch.repositoryID,
                requestDigest: batch.requestDigest,
                uploads: uploads,
                createdAt: batch.createdAt,
                expiresAt: batch.expiresAt
            )
            pendingAttachmentBatches[conversationID] = batch
            try pendingMutationStore.saveAttachmentUploads(pendingAttachmentBatches)
        }
        return try batch.uploads.map {
            guard let attachmentID = $0.attachmentID else { throw PiCoordinatorError.mutationPending }
            return attachmentID
        }
    }

    private static func sameAttachmentInputs(
        _ stored: [PiPendingAttachmentUploadRecord],
        _ current: [PiPendingAttachmentUploadRecord]
    ) -> Bool {
        guard stored.count == current.count else { return false }
        return zip(stored, current).allSatisfy {
            $0.repositoryID == $1.repositoryID
                && $0.digest == $1.digest
                && $0.fileName == $1.fileName
                && $0.mediaType == $1.mediaType
                && $0.byteCount == $1.byteCount
        }
    }

    private static func attachmentRequestDigest(
        sessionID: String,
        text: String,
        delivery: PiConversationAction.Delivery,
        uploads: [PiPendingAttachmentUploadRecord]
    ) -> String {
        struct CanonicalUpload: Encodable {
            let repositoryID: String
            let digest: String
            let fileName: String
            let mediaType: String
            let byteCount: Int
        }
        struct Canonical: Encodable {
            let sessionID: String
            let text: String
            let delivery: PiConversationAction.Delivery
            let uploads: [CanonicalUpload]
        }
        let canonical = Canonical(
            sessionID: sessionID,
            text: text,
            delivery: delivery,
            uploads: uploads.map {
                .init(
                    repositoryID: $0.repositoryID,
                    digest: $0.digest,
                    fileName: $0.fileName,
                    mediaType: $0.mediaType,
                    byteCount: $0.byteCount
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(canonical)) ?? Data()
        return Data(SHA256.hash(data: data)).base64EncodedString()
    }

    private func modelSupports(
        _ kind: PiAttachmentUpload.Kind,
        state: PiConversationState,
        conversationID: Conversation.ID
    ) -> Bool {
        guard let selected = state.model,
              let model = availableModels[conversationID]?.first(where: {
                  $0.provider == selected.provider && $0.id == selected.id
              })
        else { return false }
        switch kind {
        case .image: return model.input.contains(.image)
        case .file: return model.input.contains(.file)
        }
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
        return !Task.isCancelled
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
        adapters[conversationID] = nil
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

private extension PiConversationAction {
    var requiresSettledConfiguration: Bool {
        switch self {
        case .setModel, .setThinkingLevel: true
        default: false
        }
    }

    func matchesAuthoritativeConfiguration(
        _ configuration: PiGatewayWire.Snapshot.Configuration
    ) -> Bool {
        switch self {
        case let .setModel(provider, modelID):
            configuration.model?.provider == provider && configuration.model?.id == modelID
        case let .setThinkingLevel(level):
            configuration.thinkingLevel == level
        default:
            true
        }
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
    case mutationInFlight
    case mutationPending
    case capabilityUnavailable
    case attachmentLimitExceeded

    var errorDescription: String? {
        switch self {
        case .notBound: String(localized: "This conversation is not available in Jonwork.")
        case .notConnected: String(localized: "Jonwork is reconnecting. Try again in a moment.")
        case .viewer: String(localized: "This conversation is read-only on this device. Choose Edit on This Device before sending a message.")
        case .streaming: String(localized: "Wait for the current response to finish before editing on this device.")
        case .released: String(localized: "This conversation is now available on your desktop.")
        case .notStreaming: String(localized: "There is no active response to stop.")
        case .alreadyController: String(localized: "This conversation is already editable on this device.")
        case .sessionStateChanged: String(localized: "The conversation changed. Review it and send again.")
        case .profileMismatch: String(localized: "This conversation belongs to another Jonwork connection. Sign in to the correct workspace to reconnect.")
        case .mutationInFlight: String(localized: "Another conversation change is still being sent. Try again in a moment.")
        case .mutationPending: String(localized: "The previous conversation change is still being confirmed. Try again in a moment.")
        case .capabilityUnavailable: String(localized: "This server or model does not support the requested attachment.")
        case .attachmentLimitExceeded: String(localized: "The selected attachments exceed the server limit.")
        }
    }
}
