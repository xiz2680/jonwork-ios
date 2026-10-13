import Foundation

enum PiAdapterError: Error, Equatable, LocalizedError {
    case unsupportedContract(String)
    case unknownEnvelopeField
    case unknownEventType(String)
    case invalidPayload(String)
    case invalidEventID
    case duplicateEvent
    case outOfOrderEvent
    case eventGap
    case sessionMismatch
    case revisionRegression
    case invalidEventLifecycle

    var errorDescription: String? {
        switch self {
        case .unsupportedContract: String(localized: "Jonwork needs an update before it can connect.")
        case .unknownEnvelopeField, .unknownEventType, .invalidPayload:
            String(localized: "The server sent an unsupported event.")
        case .invalidEventID, .duplicateEvent, .outOfOrderEvent, .eventGap,
             .sessionMismatch, .revisionRegression, .invalidEventLifecycle:
            String(localized: "Conversation history changed unexpectedly. Restoring the authoritative snapshot…")
        }
    }

    var requiresSnapshotRecovery: Bool {
        switch self {
        case .invalidPayload, .invalidEventID, .duplicateEvent, .outOfOrderEvent, .eventGap,
             .sessionMismatch, .revisionRegression, .invalidEventLifecycle:
            return true
        case .unsupportedContract, .unknownEnvelopeField, .unknownEventType:
            return false
        }
    }
}

struct PiEventAdapter: Sendable {
    private struct Operation: Sendable {
        var activeTurns: Set<String> = []
        let retryOfOperationID: String?
        let validatesRetrySource: Bool
        var abortRequested = false
    }

    private struct Assistant: Sendable {
        let operationID: String
        let turnID: String
        var activeTools: Set<String> = []
    }

    private struct Tool: Sendable {
        let operationID: String
        let turnID: String
        let messageID: String
        let parentCallID: String?
        var activeChildren: Set<String> = []
        var lastUpdateSequence = 0
    }

    private struct SettledOperation: Sendable {
        let retryOfOperationID: String?
        let terminalEventID: UInt64
    }

    private(set) var sessionID: String?
    private(set) var lastEventID: PiGatewayWire.EventID?
    private(set) var revision = 0
    private let replayRetentionEvents: UInt64
    private var operations: [String: Operation] = [:]
    private var assistants: [String: Assistant] = [:]
    private var tools: [String: Tool] = [:]
    private var settledOperations: [String: SettledOperation] = [:]
    private var completedAssistants: [String: UInt64] = [:]
    private var completedTools: [String: UInt64] = [:]
    private var completedTurns: [String: UInt64] = [:]
    private var controllerClientID: String?
    private var pendingReleaseClientID: String?

    init(replayRetentionEvents: Int = 2_048) {
        precondition(replayRetentionEvents > 0)
        self.replayRetentionEvents = UInt64(replayRetentionEvents)
    }

    var retainedTerminalStateCount: Int {
        settledOperations.count + completedAssistants.count + completedTools.count + completedTurns.count
    }

    mutating func replace(with snapshot: PiGatewayWire.Snapshot, clientID: String) throws -> PiConversationEvent {
        try snapshot.validate()
        sessionID = snapshot.sessionId
        lastEventID = try .init(snapshot.lastEventId)
        revision = snapshot.revision
        operations.removeAll(keepingCapacity: true)
        assistants.removeAll(keepingCapacity: true)
        tools.removeAll(keepingCapacity: true)
        settledOperations.removeAll(keepingCapacity: true)
        completedAssistants.removeAll(keepingCapacity: true)
        completedTools.removeAll(keepingCapacity: true)
        completedTurns.removeAll(keepingCapacity: true)
        controllerClientID = snapshot.controller.clientId
        pendingReleaseClientID = nil
        if let operationID = snapshot.run.operationId, snapshot.run.status != .idle {
            operations[operationID] = .init(
                retryOfOperationID: nil,
                validatesRetrySource: false
            )
        }
        return .snapshot(snapshot, clientID: clientID)
    }

    mutating func adapt(_ wire: PiGatewayWire.Event) throws -> PiConversationEvent {
        guard wire.contract == PiGatewayWire.contract else { throw PiAdapterError.unsupportedContract(wire.contract) }
        guard wire.sessionId == sessionID else { throw PiAdapterError.sessionMismatch }
        let eventID = try PiGatewayWire.EventID(wire.id)
        if let lastEventID {
            if eventID == lastEventID { throw PiAdapterError.duplicateEvent }
            if eventID < lastEventID { throw PiAdapterError.outOfOrderEvent }
            guard eventID.rawValue == lastEventID.rawValue + 1 else { throw PiAdapterError.eventGap }
        }
        guard wire.sessionRevision >= revision else { throw PiAdapterError.revisionRegression }

        compactTerminalState(currentEventID: eventID.rawValue)
        let event = try map(wire, eventID: eventID.rawValue)
        lastEventID = eventID
        revision = wire.sessionRevision
        return event
    }

    private mutating func map(_ wire: PiGatewayWire.Event, eventID: UInt64) throws -> PiConversationEvent {
        let data = wire.data
        if pendingReleaseClientID != nil, wire.type != "session.released" {
            throw PiAdapterError.invalidEventLifecycle
        }
        switch wire.type {
        case "operation.accepted":
            try validate(data, keys: ["operationId", "command", "retryOfOperationId"])
            let operationID = try string(data, "operationId")
            guard operations[operationID] == nil, settledOperations[operationID] == nil else {
                throw PiAdapterError.invalidEventLifecycle
            }
            let command = try string(data, "command")
            let retryOf = try optionalString(data, "retryOfOperationId")
            guard (command == "retry") == (retryOf != nil) else {
                throw PiAdapterError.invalidEventLifecycle
            }
            guard retryOf != operationID else { throw PiAdapterError.invalidEventLifecycle }
            if let retryOf, operations[retryOf] != nil {
                throw PiAdapterError.invalidEventLifecycle
            }
            operations[operationID] = .init(
                retryOfOperationID: retryOf,
                validatesRetrySource: true
            )
            return .operationAccepted(id: operationID, command: command, retryOf: retryOf)

        case "user.message":
            try validate(data, keys: ["operationId", "messageId", "text", "attachmentIds"])
            let operationID = try activeOperation(data)
            return .userMessage(
                id: try string(data, "messageId"),
                text: try string(data, "text"),
                attachmentIDs: try strings(data, "attachmentIds")
            ).requiring(operationID: operationID)

        case "turn.started":
            try validate(data, keys: ["operationId", "turnId"])
            let operationID = try activeOperation(data)
            let turnID = try string(data, "turnId")
            let turnKey = terminalTurnKey(operationID: operationID, turnID: turnID)
            guard completedTurns[turnKey] == nil,
                  operations[operationID]?.activeTurns.insert(turnID).inserted == true
            else {
                throw PiAdapterError.invalidEventLifecycle
            }
            return .turnStarted(operationID: operationID, turnID: turnID)

        case "assistant.message.started":
            try validate(data, keys: ["operationId", "turnId", "messageId"])
            let (operationID, turnID, messageID) = try activeAssistantIdentity(data)
            guard assistants[messageID] == nil, completedAssistants[messageID] == nil else {
                throw PiAdapterError.invalidEventLifecycle
            }
            assistants[messageID] = .init(operationID: operationID, turnID: turnID)
            return .assistantStarted(operationID: operationID, turnID: turnID, messageID: messageID)

        case "assistant.text.delta", "assistant.reasoning.delta":
            try validate(data, keys: ["operationId", "turnId", "messageId", "delta"])
            let (_, _, messageID) = try activeAssistantIdentity(data, requireExisting: true)
            let delta = try string(data, "delta")
            return wire.type == "assistant.text.delta"
                ? .assistantTextDelta(messageID: messageID, delta: delta)
                : .assistantReasoningDelta(messageID: messageID, delta: delta)

        case "tool.started":
            try validate(data, keys: ["operationId", "turnId", "messageId", "toolCallId", "parentCallId", "toolName", "arguments"])
            let (operationID, turnID, messageID) = try activeAssistantIdentity(data, requireExisting: true)
            let callID = try string(data, "toolCallId")
            let parentID = try optionalString(data, "parentCallId")
            guard tools[callID] == nil, completedTools[callID] == nil else {
                throw PiAdapterError.invalidEventLifecycle
            }
            if let parentID {
                guard tools[parentID] != nil else { throw PiAdapterError.invalidEventLifecycle }
                tools[parentID]?.activeChildren.insert(callID)
            }
            tools[callID] = .init(
                operationID: operationID,
                turnID: turnID,
                messageID: messageID,
                parentCallID: parentID
            )
            assistants[messageID]?.activeTools.insert(callID)
            return .toolStarted(try tool(data, name: string(data, "toolName"), detail: render(data["arguments"])))

        case "tool.updated":
            try validate(data, keys: ["operationId", "turnId", "messageId", "toolCallId", "parentCallId", "updateSequence", "partialResult"])
            let callID = try string(data, "toolCallId")
            guard var current = tools[callID],
                  try toolIdentity(data, matches: current)
            else { throw PiAdapterError.invalidEventLifecycle }
            let sequence = try integer(data, "updateSequence")
            guard sequence == current.lastUpdateSequence + 1 else { throw PiAdapterError.invalidEventLifecycle }
            current.lastUpdateSequence = sequence
            tools[callID] = current
            return .toolUpdated(try tool(data, detail: render(data["partialResult"]), updateSequence: sequence))

        case "tool.completed":
            try validate(data, keys: ["operationId", "turnId", "messageId", "toolCallId", "parentCallId", "status", "result", "error"])
            let callID = try string(data, "toolCallId")
            guard let current = tools[callID],
                  current.activeChildren.isEmpty,
                  try toolIdentity(data, matches: current)
            else {
                throw PiAdapterError.invalidEventLifecycle
            }
            tools.removeValue(forKey: callID)
            completedTools[callID] = eventID
            assistants[current.messageID]?.activeTools.remove(callID)
            if let parent = current.parentCallID { tools[parent]?.activeChildren.remove(callID) }
            let succeeded = try string(data, "status") == "success"
            let detail = succeeded ? render(data["result"]) : try failure(data["error"])?.message
            return .toolCompleted(try tool(data, detail: detail, succeeded: succeeded))

        case "assistant.message.completed":
            try validate(data, keys: ["operationId", "turnId", "messageId", "status", "error"])
            let (_, _, messageID) = try activeAssistantIdentity(data, requireExisting: true)
            guard let assistant = assistants[messageID], assistant.activeTools.isEmpty else {
                throw PiAdapterError.invalidEventLifecycle
            }
            assistants.removeValue(forKey: messageID)
            completedAssistants[messageID] = eventID
            return .assistantCompleted(
                messageID: messageID,
                status: try string(data, "status"),
                error: try failure(data["error"])
            )

        case "turn.completed":
            try validate(data, keys: ["operationId", "turnId", "status"])
            let operationID = try activeOperation(data)
            let turnID = try string(data, "turnId")
            guard operations[operationID]?.activeTurns.contains(turnID) == true,
                  !assistants.values.contains(where: { $0.operationID == operationID && $0.turnID == turnID })
            else { throw PiAdapterError.invalidEventLifecycle }
            operations[operationID]?.activeTurns.remove(turnID)
            completedTurns[terminalTurnKey(operationID: operationID, turnID: turnID)] = eventID
            return .turnCompleted(operationID: operationID, turnID: turnID, status: try string(data, "status"))

        case "abort.requested":
            try validate(data, keys: ["operationId", "requestedByClientId"])
            let operationID = try activeOperation(data)
            guard operations[operationID]?.abortRequested == false else {
                throw PiAdapterError.invalidEventLifecycle
            }
            operations[operationID]?.abortRequested = true
            return .abortRequested(operationID: operationID, clientID: try string(data, "requestedByClientId"))

        case "operation.settled":
            try validate(data, keys: ["operationId", "status", "retryOfOperationId", "error"])
            let operationID = try activeOperation(data)
            let retryOf = try optionalString(data, "retryOfOperationId")
            guard let operation = operations[operationID],
                  operation.activeTurns.isEmpty,
                  (!operation.validatesRetrySource || operation.retryOfOperationID == retryOf)
            else {
                throw PiAdapterError.invalidEventLifecycle
            }
            operations.removeValue(forKey: operationID)
            settledOperations[operationID] = .init(retryOfOperationID: retryOf, terminalEventID: eventID)
            return .operationSettled(
                id: operationID,
                status: try string(data, "status"),
                retryOf: retryOf,
                error: try failure(data["error"])
            )

        case "gateway.error":
            try validate(data, keys: ["operationId", "error"])
            guard let failure = try failure(data["error"]) else { throw PiAdapterError.invalidPayload("error") }
            return .error(operationID: try optionalString(data, "operationId"), failure: failure)

        case "controller.changed":
            try validate(data, keys: ["previousControllerClientId", "controllerClientId", "reason"])
            let previous = try optionalString(data, "previousControllerClientId")
            let current = try optionalString(data, "controllerClientId")
            let reason = try string(data, "reason")
            guard previous == controllerClientID, previous != current else {
                throw PiAdapterError.invalidEventLifecycle
            }
            switch reason {
            case "takeover":
                guard current != nil else { throw PiAdapterError.invalidEventLifecycle }
            case "release":
                guard let previous, current == nil else { throw PiAdapterError.invalidEventLifecycle }
                pendingReleaseClientID = previous
            case "disconnect", "expired":
                guard previous != nil, current == nil else { throw PiAdapterError.invalidEventLifecycle }
            default:
                throw PiAdapterError.invalidPayload("reason")
            }
            controllerClientID = current
            return .controllerChanged(
                previous: previous,
                current: current,
                reason: reason
            )

        case "session.released":
            try validate(data, keys: ["byClientId"])
            let clientID = try string(data, "byClientId")
            guard pendingReleaseClientID == clientID, controllerClientID == nil else {
                throw PiAdapterError.invalidEventLifecycle
            }
            pendingReleaseClientID = nil
            return .released(byClientID: clientID)

        default:
            throw PiAdapterError.unknownEventType(wire.type)
        }
    }

    private func activeOperation(_ data: [String: PiJSONValue]) throws -> String {
        let operationID = try string(data, "operationId")
        guard operations[operationID] != nil else { throw PiAdapterError.invalidEventLifecycle }
        return operationID
    }

    private func activeAssistantIdentity(
        _ data: [String: PiJSONValue],
        requireExisting: Bool = false
    ) throws -> (String, String, String) {
        let operationID = try activeOperation(data)
        let turnID = try string(data, "turnId")
        let messageID = try string(data, "messageId")
        guard operations[operationID]?.activeTurns.contains(turnID) == true else {
            throw PiAdapterError.invalidEventLifecycle
        }
        if requireExisting {
            guard let assistant = assistants[messageID],
                  assistant.operationID == operationID,
                  assistant.turnID == turnID
            else { throw PiAdapterError.invalidEventLifecycle }
        }
        return (operationID, turnID, messageID)
    }

    private func tool(
        _ data: [String: PiJSONValue],
        name: String? = nil,
        detail: String? = nil,
        updateSequence: Int? = nil,
        succeeded: Bool? = nil
    ) throws -> PiConversationEvent.Tool {
        .init(
            operationID: try string(data, "operationId"),
            turnID: try string(data, "turnId"),
            messageID: try string(data, "messageId"),
            callID: try string(data, "toolCallId"),
            parentCallID: try optionalString(data, "parentCallId"),
            name: name,
            detail: detail,
            updateSequence: updateSequence,
            succeeded: succeeded
        )
    }

    private func validate(_ data: [String: PiJSONValue], keys: Set<String>) throws {
        guard Set(data.keys) == keys else { throw PiAdapterError.invalidPayload("fields") }
    }

    private func string(_ data: [String: PiJSONValue], _ key: String) throws -> String {
        guard let value = data[key]?.stringValue else { throw PiAdapterError.invalidPayload(key) }
        return value
    }

    private func optionalString(_ data: [String: PiJSONValue], _ key: String) throws -> String? {
        guard let value = data[key] else { throw PiAdapterError.invalidPayload(key) }
        if value == .null { return nil }
        guard let string = value.stringValue else { throw PiAdapterError.invalidPayload(key) }
        return string
    }

    private func strings(_ data: [String: PiJSONValue], _ key: String) throws -> [String] {
        guard let values = data[key]?.arrayValue else { throw PiAdapterError.invalidPayload(key) }
        return try values.map {
            guard let value = $0.stringValue else { throw PiAdapterError.invalidPayload(key) }
            return value
        }
    }

    private func integer(_ data: [String: PiJSONValue], _ key: String) throws -> Int {
        guard case let .number(value) = data[key],
              value.isFinite,
              value >= 0,
              value.rounded(.towardZero) == value,
              let integer = Int(exactly: value)
        else {
            throw PiAdapterError.invalidPayload(key)
        }
        return integer
    }

    private func toolIdentity(_ data: [String: PiJSONValue], matches tool: Tool) throws -> Bool {
        let operationID = try string(data, "operationId")
        let turnID = try string(data, "turnId")
        let messageID = try string(data, "messageId")
        let parentCallID = try optionalString(data, "parentCallId")
        return operationID == tool.operationID
            && turnID == tool.turnID
            && messageID == tool.messageID
            && parentCallID == tool.parentCallID
    }

    private func terminalTurnKey(operationID: String, turnID: String) -> String {
        "\(operationID)\u{0}\(turnID)"
    }

    private mutating func compactTerminalState(currentEventID: UInt64) {
        let cutoff = currentEventID >= replayRetentionEvents
            ? currentEventID - replayRetentionEvents + 1
            : 0
        settledOperations = settledOperations.filter { $0.value.terminalEventID >= cutoff }
        completedAssistants = completedAssistants.filter { $0.value >= cutoff }
        completedTools = completedTools.filter { $0.value >= cutoff }
        completedTurns = completedTurns.filter { $0.value >= cutoff }
    }

    private func failure(_ value: PiJSONValue?) throws -> PiConversationFailure? {
        guard let value else { throw PiAdapterError.invalidPayload("error") }
        if value == .null { return nil }
        guard let object = value.objectValue,
              Set(object.keys) == ["code", "message", "retryable"],
              let code = object["code"]?.stringValue,
              let message = object["message"]?.stringValue,
              case let .bool(retryable) = object["retryable"]
        else { throw PiAdapterError.invalidPayload("error") }
        return .init(code: code, message: message, retryable: retryable)
    }

    private func render(_ value: PiJSONValue?) -> String {
        guard let value else { return "" }
        if let string = value.stringValue { return string }
        return (try? JSONEncoder.piGatewayPretty.encode(value))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

private extension PiConversationEvent {
    func requiring(operationID _: String) -> Self { self }
}

private extension JSONEncoder {
    static var piGatewayPretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
