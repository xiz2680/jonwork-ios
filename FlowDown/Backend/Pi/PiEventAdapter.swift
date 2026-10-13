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
        case .unsupportedContract: String(localized: "The server uses an unsupported Pi Gateway version.")
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
        var settled = false
    }

    private struct Assistant: Sendable {
        let operationID: String
        let turnID: String
        var activeTools: Set<String> = []
        var completed = false
    }

    private struct Tool: Sendable {
        let operationID: String
        let turnID: String
        let messageID: String
        let parentCallID: String?
        var activeChildren: Set<String> = []
        var lastUpdateSequence = 0
        var completed = false
    }

    private(set) var sessionID: String?
    private(set) var lastEventID: PiGatewayWire.EventID?
    private(set) var revision = 0
    private var operations: [String: Operation] = [:]
    private var assistants: [String: Assistant] = [:]
    private var tools: [String: Tool] = [:]

    mutating func replace(with snapshot: PiGatewayWire.Snapshot, clientID: String) throws -> PiConversationEvent {
        try snapshot.validate()
        sessionID = snapshot.sessionId
        lastEventID = try .init(snapshot.lastEventId)
        revision = snapshot.revision
        operations.removeAll(keepingCapacity: true)
        assistants.removeAll(keepingCapacity: true)
        tools.removeAll(keepingCapacity: true)
        if let operationID = snapshot.run.operationId, snapshot.run.status != .idle {
            operations[operationID] = .init()
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

        let event = try map(wire)
        lastEventID = eventID
        revision = wire.sessionRevision
        return event
    }

    private mutating func map(_ wire: PiGatewayWire.Event) throws -> PiConversationEvent {
        let data = wire.data
        switch wire.type {
        case "operation.accepted":
            try validate(data, keys: ["operationId", "command", "retryOfOperationId"])
            let operationID = try string(data, "operationId")
            guard operations[operationID] == nil else { throw PiAdapterError.invalidEventLifecycle }
            let retryOf = try optionalString(data, "retryOfOperationId")
            if let retryOf, let source = operations[retryOf], !source.settled {
                throw PiAdapterError.invalidEventLifecycle
            }
            operations[operationID] = .init()
            return .operationAccepted(id: operationID, command: try string(data, "command"), retryOf: retryOf)

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
            guard operations[operationID]?.activeTurns.insert(turnID).inserted == true else {
                throw PiAdapterError.invalidEventLifecycle
            }
            return .turnStarted(operationID: operationID, turnID: turnID)

        case "assistant.message.started":
            try validate(data, keys: ["operationId", "turnId", "messageId"])
            let (operationID, turnID, messageID) = try activeAssistantIdentity(data)
            guard assistants[messageID] == nil else { throw PiAdapterError.invalidEventLifecycle }
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
            guard tools[callID] == nil else { throw PiAdapterError.invalidEventLifecycle }
            if let parentID {
                guard tools[parentID]?.completed == false else { throw PiAdapterError.invalidEventLifecycle }
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
                  !current.completed,
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
            guard var current = tools[callID],
                  !current.completed,
                  current.activeChildren.isEmpty,
                  try toolIdentity(data, matches: current)
            else {
                throw PiAdapterError.invalidEventLifecycle
            }
            current.completed = true
            tools[callID] = current
            assistants[current.messageID]?.activeTools.remove(callID)
            if let parent = current.parentCallID { tools[parent]?.activeChildren.remove(callID) }
            let succeeded = try string(data, "status") == "success"
            let detail = succeeded ? render(data["result"]) : try failure(data["error"])?.message
            return .toolCompleted(try tool(data, detail: detail, succeeded: succeeded))

        case "assistant.message.completed":
            try validate(data, keys: ["operationId", "turnId", "messageId", "status", "error"])
            let (_, _, messageID) = try activeAssistantIdentity(data, requireExisting: true)
            guard var assistant = assistants[messageID], assistant.activeTools.isEmpty, !assistant.completed else {
                throw PiAdapterError.invalidEventLifecycle
            }
            assistant.completed = true
            assistants[messageID] = assistant
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
                  !assistants.values.contains(where: { $0.operationID == operationID && $0.turnID == turnID && !$0.completed })
            else { throw PiAdapterError.invalidEventLifecycle }
            operations[operationID]?.activeTurns.remove(turnID)
            return .turnCompleted(operationID: operationID, turnID: turnID, status: try string(data, "status"))

        case "abort.requested":
            try validate(data, keys: ["operationId", "requestedByClientId"])
            return .abortRequested(operationID: try activeOperation(data), clientID: try string(data, "requestedByClientId"))

        case "operation.settled":
            try validate(data, keys: ["operationId", "status", "retryOfOperationId", "error"])
            let operationID = try activeOperation(data)
            guard var operation = operations[operationID], operation.activeTurns.isEmpty, !operation.settled else {
                throw PiAdapterError.invalidEventLifecycle
            }
            operation.settled = true
            operations[operationID] = operation
            return .operationSettled(
                id: operationID,
                status: try string(data, "status"),
                retryOf: try optionalString(data, "retryOfOperationId"),
                error: try failure(data["error"])
            )

        case "gateway.error":
            try validate(data, keys: ["operationId", "error"])
            guard let failure = try failure(data["error"]) else { throw PiAdapterError.invalidPayload("error") }
            return .error(operationID: try optionalString(data, "operationId"), failure: failure)

        case "controller.changed":
            try validate(data, keys: ["previousControllerClientId", "controllerClientId", "reason"])
            return .controllerChanged(
                previous: try optionalString(data, "previousControllerClientId"),
                current: try optionalString(data, "controllerClientId"),
                reason: try string(data, "reason")
            )

        case "session.released":
            try validate(data, keys: ["byClientId"])
            return .released(byClientID: try string(data, "byClientId"))

        default:
            throw PiAdapterError.unknownEventType(wire.type)
        }
    }

    private func activeOperation(_ data: [String: PiJSONValue]) throws -> String {
        let operationID = try string(data, "operationId")
        guard operations[operationID]?.settled == false else { throw PiAdapterError.invalidEventLifecycle }
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
                  assistant.turnID == turnID,
                  !assistant.completed
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
