import Foundation

struct PiConversationState: Equatable, Sendable {
    var sessionID: String = ""
    var repository: String = ""
    var title: String?
    var isStreaming = false
    var model: PiSelectedModel?
    var thinkingLevel = "off"
    var steeringMode: PiQueueMode = .all
    var followUpMode: PiQueueMode = .all
    var stats: PiSessionStats?
    var contextUsage: PiContextUsage?
    var clientID: String = ""
    var controllerClientID: String?
    var role: PiClientRole = .viewer
    var isReleased = false
    var revision = 0
    var lastEventID = "0"
    var activeOperationID: String?
    var lastFailedOperationID: String?
    var failure: PiConversationFailure?
    var attachmentIDs: [String] = []
    var messages: [PiPresentationMessage] = []
}

struct PiPresentationMessage: Equatable, Sendable, Identifiable {
    enum Role: Equatable, Sendable { case user, assistant, system, tool }

    let id: String
    var role: Role
    var text: String
    var reasoning: String
    var tool: PiToolPresentation?
}

struct PiToolPresentation: Equatable, Sendable {
    enum State: Equatable, Sendable { case running, succeeded, failed }

    let callID: String
    var parentCallID: String?
    var name: String
    var detail: String
    var state: State
}

struct PiSessionReducer: Sendable {
    static let maximumToolDetailCharacters = 8_192
    static let maximumPresentationMessages = 2_000
    static let toolDetailTruncationMarker = "\n… [truncated by Jonwork]"

    private(set) var state = PiConversationState()
    private var activeMessageID: String?
    private var activeAnonymousToolIDs: [String: String] = [:]
    private var nextMessageSequence = 0
    private var nextToolSequence = 0

    mutating func accept(_ receipt: PiGatewayWire.MutationReceipt) {
        state.revision = receipt.revision
    }

    mutating func observe(revision: Int, lastEventID: String) {
        state.revision = revision
        state.lastEventID = lastEventID
    }

    mutating func reduce(_ event: PiConversationEvent) {
        switch event {
        case let .snapshot(snapshot, clientID):
            state = Self.project(snapshot, clientID: clientID)
            resetTransientIdentity()
        case let .operationAccepted(id, _, _):
            state.activeOperationID = id
            state.isStreaming = true
            state.failure = nil
        case let .userMessage(id, text, _):
            upsert(.init(id: id, role: .user, text: text, reasoning: "", tool: nil))
        case .turnStarted:
            state.isStreaming = true
        case let .assistantStarted(_, _, messageID):
            upsert(.init(id: messageID, role: .assistant, text: "", reasoning: "", tool: nil))
        case let .assistantTextDelta(messageID, delta):
            append(delta, to: messageID, reasoning: false)
        case let .assistantReasoningDelta(messageID, delta):
            append(delta, to: messageID, reasoning: true)
        case let .toolStarted(tool):
            upsert(.init(
                id: "tool-\(tool.callID)",
                role: .tool,
                text: "",
                reasoning: "",
                tool: .init(
                    callID: tool.callID,
                    parentCallID: tool.parentCallID,
                    name: tool.name ?? String(localized: "Tool"),
                    detail: Self.truncateToolDetail(tool.detail ?? ""),
                    state: .running
                )
            ))
        case let .toolUpdated(tool):
            updateDomainTool(tool, state: .running)
        case let .toolCompleted(tool):
            updateDomainTool(tool, state: tool.succeeded == true ? .succeeded : .failed)
        case let .assistantCompleted(_, status, error):
            if status == "error", let error { state.failure = error }
        case .turnCompleted, .abortRequested:
            break
        case let .operationSettled(id, status, _, error):
            state.isStreaming = false
            state.activeOperationID = nil
            state.failure = error
            state.lastFailedOperationID = status == "failed" ? id : nil
        case let .error(_, failure):
            state.failure = failure
        case let .controllerChanged(_, current, _):
            state.controllerClientID = current
            state.role = current == state.clientID ? .controller : .viewer
        case .released:
            state.isReleased = true
            state.isStreaming = false
            state.controllerClientID = nil
            state.role = .viewer
        }
    }

    private mutating func append(_ delta: String, to messageID: String, reasoning: Bool) {
        let index: Int
        if let existing = state.messages.firstIndex(where: { $0.id == messageID }) {
            index = existing
        } else {
            state.messages.append(.init(id: messageID, role: .assistant, text: "", reasoning: "", tool: nil))
            index = state.messages.index(before: state.messages.endIndex)
        }
        if reasoning { state.messages[index].reasoning += delta } else { state.messages[index].text += delta }
    }

    private mutating func updateDomainTool(_ event: PiConversationEvent.Tool, state toolState: PiToolPresentation.State) {
        let id = "tool-\(event.callID)"
        guard let index = self.state.messages.firstIndex(where: { $0.id == id }),
              var tool = self.state.messages[index].tool
        else { return }
        if let detail = event.detail { tool.detail = Self.truncateToolDetail(detail) }
        tool.state = toolState
        self.state.messages[index].tool = tool
    }

    private static func project(_ snapshot: PiGatewayWire.Snapshot, clientID: String) -> PiConversationState {
        var messages: [PiPresentationMessage] = []
        for message in snapshot.messages {
            var text = ""
            var reasoning = ""
            var tools: [String: PiToolPresentation] = [:]
            var toolOrder: [String] = []
            var attachmentIDs: [String] = []
            for content in message.content {
                switch content.type {
                case .text: text += content.text ?? ""
                case .thinking: reasoning += content.text ?? ""
                case .toolCall:
                    let callID = content.toolCallId ?? "\(message.id)-tool"
                    if tools[callID] == nil { toolOrder.append(callID) }
                    tools[callID] = .init(
                        callID: callID,
                        parentCallID: nil,
                        name: String(localized: "Tool"),
                        detail: content.text ?? "",
                        state: .running
                    )
                case .toolResult:
                    let callID = content.toolCallId ?? "\(message.id)-tool"
                    if tools[callID] == nil { toolOrder.append(callID) }
                    tools[callID] = .init(
                        callID: callID,
                        parentCallID: nil,
                        name: String(localized: "Tool"),
                        detail: content.text ?? "",
                        state: message.status == .error ? .failed : .succeeded
                    )
                case .attachment:
                    if let attachmentID = content.attachmentId { attachmentIDs.append(attachmentID) }
                }
            }
            let role: PiPresentationMessage.Role = switch message.role {
            case .user: .user
            case .assistant: .assistant
            case .tool: .tool
            }
            if !text.isEmpty || !reasoning.isEmpty || (tools.isEmpty && attachmentIDs.isEmpty) {
                messages.append(.init(id: message.id, role: role, text: text, reasoning: reasoning, tool: nil))
            }
            for callID in toolOrder {
                guard let tool = tools[callID] else { continue }
                messages.append(.init(
                    id: "tool-\(callID)",
                    role: .tool,
                    text: "",
                    reasoning: "",
                    tool: tool
                ))
            }
            for attachmentID in attachmentIDs {
                let attachment = snapshot.attachments.first { $0.attachmentId == attachmentID }
                messages.append(.init(
                    id: "attachment-\(attachmentID)",
                    role: role,
                    text: attachment?.fileName ?? attachmentID,
                    reasoning: "",
                    tool: nil
                ))
            }
        }
        return .init(
            sessionID: snapshot.sessionId,
            repository: snapshot.repositoryId,
            isStreaming: snapshot.run.status == .running,
            model: snapshot.configuration.model.map { .init(provider: $0.provider, id: $0.id, name: nil) },
            thinkingLevel: snapshot.configuration.thinkingLevel.rawValue,
            clientID: clientID,
            controllerClientID: snapshot.controller.clientId,
            role: snapshot.controller.clientId == clientID ? .controller : .viewer,
            isReleased: snapshot.lifecycle == .released,
            revision: snapshot.revision,
            lastEventID: snapshot.lastEventId,
            activeOperationID: snapshot.run.operationId,
            attachmentIDs: snapshot.attachments.map(\.attachmentId),
            messages: Array(messages.suffix(maximumPresentationMessages))
        )
    }

    mutating func reduce(_ event: PiServerEvent) {
        switch event {
        case let .initial(snapshot, clientID, controllerClientID, role):
            state = Self.project(snapshot)
            state.clientID = clientID
            state.controllerClientID = controllerClientID
            state.role = role
            resetTransientIdentity()
        case let .agent(event):
            reduceAgent(event)
        case let .statePatch(patch):
            apply(patch)
        case let .controllerChanged(controllerClientID):
            state.controllerClientID = controllerClientID
            state.role = controllerClientID == state.clientID ? .controller : .viewer
        case .released:
            state.isReleased = true
            state.isStreaming = false
        }
    }

    mutating func replace(snapshot: PiSessionState, clientID: String) {
        state = Self.project(snapshot)
        state.clientID = clientID
        state.role = .viewer
        resetTransientIdentity()
    }

    private mutating func reduceAgent(_ event: PiAgentEvent) {
        switch event.type {
        case "agent_start", "turn_start":
            state.isStreaming = true
        case "agent_end", "agent_settled":
            state.isStreaming = false
        case "message_start", "message_update", "message_end", "turn_end":
            guard let message = event.payload["message"] else { return }
            let explicitID = Self.messageID(message)
            let isEnding = event.type == "message_end" || event.type == "turn_end"
            let messageID = explicitID
                ?? activeMessageID
                ?? (isEnding ? matchingMessageID(for: message) : nil)
                ?? allocateMessageID()
            if event.type != "message_end", event.type != "turn_end" {
                activeMessageID = messageID
            }
            let projected = Self.project(message, fallbackID: messageID)
            if !projected.text.isEmpty || !projected.reasoning.isEmpty || projected.role != .assistant {
                upsert(projected)
            }
            if isEnding {
                activeMessageID = nil
            }
        case "tool_execution_start":
            let name = event.payload["toolName"]?.stringValue ?? String(localized: "Tool")
            let callID = event.payload["toolCallId"]?.stringValue ?? activeAnonymousToolIDs[name] ?? allocateToolID()
            if event.payload["toolCallId"] == nil { activeAnonymousToolIDs[name] = callID }
            upsert(.init(
                id: "tool-\(callID)",
                role: .tool,
                text: "",
                reasoning: "",
                tool: .init(callID: callID, parentCallID: nil, name: name, detail: Self.renderToolDetail(event.payload["args"]), state: .running),
            ))
        case "tool_execution_update":
            updateTool(event, state: .running, detailKey: "partialResult")
        case "tool_execution_end":
            let failed = event.payload["isError"] == .bool(true)
            updateTool(event, state: failed ? .failed : .succeeded, detailKey: "result")
        default:
            break
        }
    }

    private mutating func upsert(_ message: PiPresentationMessage) {
        if let index = state.messages.firstIndex(where: { $0.id == message.id }) {
            state.messages[index] = message
        } else {
            state.messages.append(message)
            if state.messages.count > Self.maximumPresentationMessages {
                state.messages.removeFirst(state.messages.count - Self.maximumPresentationMessages)
            }
        }
    }

    private mutating func updateTool(_ event: PiAgentEvent, state toolState: PiToolPresentation.State, detailKey: String) {
        let name = event.payload["toolName"]?.stringValue ?? String(localized: "Tool")
        guard let callID = event.payload["toolCallId"]?.stringValue ?? activeAnonymousToolIDs[name] else { return }
        let messageID = "tool-\(callID)"
        let message = PiPresentationMessage(
            id: messageID,
            role: .tool,
            text: "",
            reasoning: "",
            tool: .init(
                callID: callID,
                parentCallID: nil,
                name: name,
                detail: Self.renderToolDetail(event.payload[detailKey]),
                state: toolState,
            ),
        )
        upsert(message)
        if toolState != .running { activeAnonymousToolIDs[name] = nil }
    }

    private mutating func apply(_ patch: PiSessionPatch) {
        if let model = patch.model { state.model = model }
        if let thinkingLevel = patch.thinkingLevel { state.thinkingLevel = thinkingLevel }
        if let sessionName = patch.sessionName { state.title = sessionName }
        if let steeringMode = patch.steeringMode { state.steeringMode = steeringMode }
        if let followUpMode = patch.followUpMode { state.followUpMode = followUpMode }
        if let stats = patch.stats { state.stats = stats }
        if let contextUsage = patch.contextUsage { state.contextUsage = contextUsage }
    }

    private static func project(_ snapshot: PiSessionState) -> PiConversationState {
        .init(
            sessionID: snapshot.sessionId,
            repository: snapshot.cwd,
            title: snapshot.sessionName,
            isStreaming: snapshot.isStreaming,
            model: snapshot.model,
            thinkingLevel: snapshot.thinkingLevel,
            steeringMode: snapshot.steeringMode,
            followUpMode: snapshot.followUpMode,
            stats: snapshot.stats,
            contextUsage: snapshot.contextUsage,
            messages: projectSnapshotMessages(snapshot.messages),
        )
    }

    private static func projectSnapshotMessages(_ messages: [PiJSONValue]) -> [PiPresentationMessage] {
        var result: [PiPresentationMessage] = []
        for (messageIndex, value) in messages.enumerated() {
            let fallbackID = "snapshot-\(messageIndex)"
            let projected = project(value, fallbackID: fallbackID)
            if !projected.text.isEmpty || !projected.reasoning.isEmpty || projected.role != .assistant {
                replaceOrAppend(projected, to: &result)
            }
            guard let blocks = value.objectValue?["content"]?.arrayValue else { continue }
            for (blockIndex, block) in blocks.compactMap(\.objectValue).enumerated()
                where block["type"]?.stringValue == "toolCall"
            {
                let callID = block["id"]?.stringValue
                    ?? block["toolCallId"]?.stringValue
                    ?? "snapshot-\(messageIndex)-tool-\(blockIndex)"
                replaceOrAppend(.init(
                    id: "tool-\(callID)",
                    role: .tool,
                    text: "",
                    reasoning: "",
                    tool: .init(
                        callID: callID,
                        parentCallID: nil,
                        name: block["name"]?.stringValue ?? String(localized: "Tool"),
                        detail: renderToolDetail(block["arguments"]),
                        state: .running
                    )
                ), to: &result)
            }
        }
        return Array(result.suffix(maximumPresentationMessages))
    }

    private static func replaceOrAppend(_ message: PiPresentationMessage, to messages: inout [PiPresentationMessage]) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
    }

    private static func project(_ value: PiJSONValue, fallbackID: String) -> PiPresentationMessage {
        guard let object = value.objectValue else {
            return .init(id: fallbackID, role: .system, text: render(value), reasoning: "", tool: nil)
        }
        let roleValue = object["role"]?.stringValue ?? "system"
        let role: PiPresentationMessage.Role = switch roleValue {
        case "user": .user
        case "assistant": .assistant
        case "tool", "toolResult": .tool
        default: .system
        }
        let id = if role == .tool, let callID = object["toolCallId"]?.stringValue {
            "tool-\(callID)"
        } else {
            object["id"]?.stringValue
                ?? object["messageId"]?.stringValue
                ?? fallbackID
        }
        var text = ""
        var reasoning = ""

        if let raw = object["content"]?.stringValue {
            text = raw
        } else if let blocks = object["content"]?.arrayValue {
            for block in blocks.compactMap(\.objectValue) {
                switch block["type"]?.stringValue {
                case "text": text += block["text"]?.stringValue ?? ""
                case "thinking", "reasoning": reasoning += block["thinking"]?.stringValue ?? block["text"]?.stringValue ?? ""
                default: break
                }
            }
        }
        var tool: PiToolPresentation?
        if role == .tool {
            let callID = object["toolCallId"]?.stringValue ?? id
            tool = .init(
                callID: callID,
                parentCallID: nil,
                name: object["toolName"]?.stringValue ?? String(localized: "Tool"),
                detail: truncateToolDetail(text.isEmpty ? render(object["content"]) : text),
                state: object["isError"] == .bool(true) ? .failed : .succeeded,
            )
            text = ""
        }
        return .init(id: id, role: role, text: text, reasoning: reasoning, tool: tool)
    }

    private static func messageID(_ value: PiJSONValue) -> String? {
        guard let object = value.objectValue else { return nil }
        return object["id"]?.stringValue ?? object["messageId"]?.stringValue
    }

    private func matchingMessageID(for value: PiJSONValue) -> String? {
        let candidate = Self.project(value, fallbackID: "")
        return state.messages.last(where: {
            $0.role == candidate.role
                && $0.text == candidate.text
                && $0.reasoning == candidate.reasoning
                && $0.tool == candidate.tool
        })?.id
    }

    private mutating func allocateMessageID() -> String {
        defer { nextMessageSequence += 1 }
        return "live-message-\(nextMessageSequence)"
    }

    private mutating func allocateToolID() -> String {
        defer { nextToolSequence += 1 }
        return "anonymous-tool-\(nextToolSequence)"
    }

    private mutating func resetTransientIdentity() {
        activeMessageID = nil
        activeAnonymousToolIDs.removeAll(keepingCapacity: true)
        nextMessageSequence = state.messages.count
        nextToolSequence = state.messages.lazy.filter { $0.tool != nil }.count
    }

    private static func render(_ value: PiJSONValue?) -> String {
        guard let value else { return "" }
        switch value {
        case let .string(value): return value
        case let .number(value): return String(value)
        case let .bool(value): return String(value)
        case .null: return ""
        case .object, .array:
            return (try? JSONEncoder.pretty.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        }
    }

    static func renderToolDetail(_ value: PiJSONValue?) -> String {
        truncateToolDetail(render(value))
    }

    static func truncateToolDetail(_ detail: String) -> String {
        guard detail.count > maximumToolDetailCharacters else { return detail }
        let contentLimit = maximumToolDetailCharacters - toolDetailTruncationMarker.count
        return String(detail.prefix(contentLimit)) + toolDetailTruncationMarker
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
