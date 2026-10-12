import Foundation

enum PiJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: PiJSONValue])
    case array([PiJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: PiJSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([PiJSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var objectValue: [String: PiJSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var arrayValue: [PiJSONValue]? {
        guard case let .array(value) = self else { return nil }
        return value
    }
}

struct PiModel: Codable, Equatable, Sendable, Identifiable {
    let provider: String
    let id: String
    let name: String?
    let reasoning: Bool?
    let input: [String]?
    let contextWindow: Int?
    let maxTokens: Int?
}

struct PiSessionSummary: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let path: String?
    let cwd: String
    let name: String?
    let firstMessage: String
    let created: String
    let modified: String
    let messageCount: Int
    let isRunning: Bool
}

struct PiContextUsage: Codable, Equatable, Sendable {
    let tokens: Int?
    let contextWindow: Int
    let percent: Double?
}

struct PiTokenStats: Codable, Equatable, Sendable {
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int
    let total: Int
}

struct PiSessionStats: Codable, Equatable, Sendable {
    let tokens: PiTokenStats
    let cost: Double
}

struct PiSelectedModel: Codable, Equatable, Sendable {
    let provider: String
    let id: String
    let name: String?
}

struct PiSessionState: Codable, Equatable, Sendable {
    let sessionId: String
    let cwd: String
    let sessionFile: String?
    let sessionName: String?
    let isStreaming: Bool
    let model: PiSelectedModel?
    let thinkingLevel: String
    let steeringMode: PiQueueMode
    let followUpMode: PiQueueMode
    let stats: PiSessionStats?
    let contextUsage: PiContextUsage?
    let messages: [PiJSONValue]
}

enum PiQueueMode: String, Codable, Equatable, Sendable {
    case all
    case oneAtATime = "one-at-a-time"
}

enum PiClientRole: String, Codable, Equatable, Sendable {
    case controller
    case viewer
}

struct PiSessionPatch: Codable, Equatable, Sendable {
    let model: PiSelectedModel??
    let thinkingLevel: String?
    let sessionName: String?
    let steeringMode: PiQueueMode?
    let followUpMode: PiQueueMode?
    let stats: PiSessionStats??
    let contextUsage: PiContextUsage??

    private enum CodingKeys: String, CodingKey {
        case model
        case thinkingLevel
        case sessionName
        case steeringMode
        case followUpMode
        case stats
        case contextUsage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        model = try Self.decodePresent(PiSelectedModel.self, forKey: .model, from: container)
        thinkingLevel = try container.decodeIfPresent(String.self, forKey: .thinkingLevel)
        sessionName = try container.decodeIfPresent(String.self, forKey: .sessionName)
        steeringMode = try container.decodeIfPresent(PiQueueMode.self, forKey: .steeringMode)
        followUpMode = try container.decodeIfPresent(PiQueueMode.self, forKey: .followUpMode)
        stats = try Self.decodePresent(PiSessionStats.self, forKey: .stats, from: container)
        contextUsage = try Self.decodePresent(PiContextUsage.self, forKey: .contextUsage, from: container)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try Self.encodePresent(model, forKey: .model, to: &container)
        try container.encodeIfPresent(thinkingLevel, forKey: .thinkingLevel)
        try container.encodeIfPresent(sessionName, forKey: .sessionName)
        try container.encodeIfPresent(steeringMode, forKey: .steeringMode)
        try container.encodeIfPresent(followUpMode, forKey: .followUpMode)
        try Self.encodePresent(stats, forKey: .stats, to: &container)
        try Self.encodePresent(contextUsage, forKey: .contextUsage, to: &container)
    }

    private static func decodePresent<Value: Decodable>(
        _ type: Value.Type,
        forKey key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Value?? {
        guard container.contains(key) else { return nil }
        return .some(try container.decodeIfPresent(type, forKey: key))
    }

    private static func encodePresent<Value: Encodable>(
        _ value: Value??,
        forKey key: CodingKeys,
        to container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        guard let value else { return }
        try container.encodeIfPresent(value, forKey: key)
    }
}

struct PiAgentEvent: Codable, Equatable, Sendable {
    let type: String
    let payload: [String: PiJSONValue]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: PiJSONValue].self)
        guard let type = object["type"]?.stringValue else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Pi agent event is missing type")
        }
        self.type = type
        payload = object
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(payload)
    }
}

enum PiServerEvent: Equatable, Sendable {
    case initial(state: PiSessionState, clientID: String, controllerClientID: String?, role: PiClientRole)
    case agent(PiAgentEvent)
    case statePatch(PiSessionPatch)
    case controllerChanged(String?)
    case released(byClientID: String)
}

extension PiServerEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case state
        case yourClientId
        case controllerClientId
        case role
        case event
        case patch
        case byClientId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "init":
            self = try .initial(
                state: container.decode(PiSessionState.self, forKey: .state),
                clientID: container.decode(String.self, forKey: .yourClientId),
                controllerClientID: container.decodeIfPresent(String.self, forKey: .controllerClientId),
                role: container.decode(PiClientRole.self, forKey: .role),
            )
        case "agent_event":
            self = try .agent(container.decode(PiAgentEvent.self, forKey: .event))
        case "state_patch":
            self = try .statePatch(container.decode(PiSessionPatch.self, forKey: .patch))
        case "controller_changed":
            self = try .controllerChanged(container.decodeIfPresent(String.self, forKey: .controllerClientId))
        case "released":
            self = try .released(byClientID: container.decode(String.self, forKey: .byClientId))
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown Pi event: \(type)")
        }
    }
}

enum PiCommand: Encodable, Equatable, Sendable {
    case prompt(clientID: String, text: String, delivery: Delivery?)
    case abort(clientID: String)
    case setModel(clientID: String, provider: String, modelID: String)
    case setThinkingLevel(clientID: String, level: String)
    case setSteeringMode(clientID: String, mode: PiQueueMode)
    case setFollowUpMode(clientID: String, mode: PiQueueMode)
    case setSessionName(clientID: String, name: String)

    enum Delivery: String, Codable, Equatable, Sendable {
        case followUp
        case steer
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case clientId
        case text
        case deliverAs
        case provider
        case modelId
        case level
        case mode
        case name
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .prompt(clientID, text, delivery):
            try container.encode("prompt", forKey: .type)
            try container.encode(clientID, forKey: .clientId)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(delivery, forKey: .deliverAs)
        case let .abort(clientID):
            try container.encode("abort", forKey: .type)
            try container.encode(clientID, forKey: .clientId)
        case let .setModel(clientID, provider, modelID):
            try container.encode("set_model", forKey: .type)
            try container.encode(clientID, forKey: .clientId)
            try container.encode(provider, forKey: .provider)
            try container.encode(modelID, forKey: .modelId)
        case let .setThinkingLevel(clientID, level):
            try container.encode("set_thinking_level", forKey: .type)
            try container.encode(clientID, forKey: .clientId)
            try container.encode(level, forKey: .level)
        case let .setSteeringMode(clientID, mode):
            try container.encode("set_steering_mode", forKey: .type)
            try container.encode(clientID, forKey: .clientId)
            try container.encode(mode, forKey: .mode)
        case let .setFollowUpMode(clientID, mode):
            try container.encode("set_follow_up_mode", forKey: .type)
            try container.encode(clientID, forKey: .clientId)
            try container.encode(mode, forKey: .mode)
        case let .setSessionName(clientID, name):
            try container.encode("set_session_name", forKey: .type)
            try container.encode(clientID, forKey: .clientId)
            try container.encode(name, forKey: .name)
        }
    }
}
