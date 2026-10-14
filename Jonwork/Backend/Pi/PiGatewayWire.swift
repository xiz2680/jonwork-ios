import Foundation

enum PiGatewayWire {
    static let contract = "pi-gateway/1.0"
    static let supportedMajorVersion = 1

    struct Discovery: Decodable, Equatable, Sendable {
        let contract: String
        let apiVersion: String
        let compatibility: Compatibility
        let authentication: Authentication
        let capabilities: Capabilities
        let limits: Limits

        var majorVersion: Int? { Int(apiVersion.split(separator: ".").first ?? "") }

        func validate() throws {
            guard contract == PiGatewayWire.contract,
                  apiVersion == "1.0",
                  compatibility.minimumApiVersion == "1.0",
                  compatibility.maximumApiVersion == "1.0"
            else { throw PiServiceError.unsupportedGatewayVersion(apiVersion) }
            guard authentication.type == "oauth2_authorization_code",
                  !authentication.clientId.isEmpty,
                  authentication.scopes == ["pi.gateway"],
                  authentication.pkceMethods == ["S256"],
                  (60 ... 3_600).contains(authentication.accessTokenLifetimeSeconds),
                  authentication.refreshTokenRotation == "required"
            else { throw PiServiceError.unsupportedAuthentication }
            let missing = capabilities.missingRequired
            guard missing.isEmpty else { throw PiServiceError.capabilityUnavailable(missing) }
            guard limits.readTimeoutMs > 0,
                  limits.mutationTimeoutMs > 0,
                  limits.sseConnectTimeoutMs > 0,
                  limits.replayRetentionEvents > 0,
                  limits.replayRetentionSeconds > 0,
                  limits.idempotencyRetentionSeconds >= 86_400,
                  (1 ... 10_485_760).contains(limits.attachmentMaxBytes),
                  (1 ... 20_971_520).contains(limits.attachmentTotalBytes),
                  (0 ... 4).contains(limits.attachmentsPerPrompt),
                  (1 ... 30_000).contains(limits.attachmentUploadTimeoutMs),
                  (1 ... 30_000).contains(limits.attachmentDownloadTimeoutMs),
                  !limits.attachmentMediaTypes.isEmpty,
                  Set(limits.attachmentMediaTypes).count == limits.attachmentMediaTypes.count,
                  limits.attachmentMediaTypes.allSatisfy({ !$0.isEmpty }),
                  limits.attachmentDigestAlgorithm == "sha-256",
                  !capabilities.attachments.sources.isEmpty,
                  Set(capabilities.attachments.sources).count == capabilities.attachments.sources.count,
                  !capabilities.attachments.mediaTypes.isEmpty,
                  Set(capabilities.attachments.mediaTypes).count == capabilities.attachments.mediaTypes.count,
                  Set(capabilities.attachments.mediaTypes).isSubset(of: Set(limits.attachmentMediaTypes)),
                  capabilities.attachments.modelCompatibilityField == "attachments.supported"
            else { throw PiServiceError.invalidResponse }
        }

        func validate(baseURL: URL) throws {
            try validate()
            let loopbackHosts = Set(["localhost", "127.0.0.1", "::1", "[::1]"])
            let baseIsLoopback = baseURL.host.map { loopbackHosts.contains($0.lowercased()) } == true
            for endpoint in [
                authentication.authorizationEndpoint,
                authentication.credentialEndpoint,
                authentication.tokenEndpoint,
                authentication.revocationEndpoint,
            ].compactMap({ $0 }) {
                let scheme = endpoint.scheme?.lowercased()
                let endpointIsLoopback = endpoint.host.map { loopbackHosts.contains($0.lowercased()) } == true
                guard scheme == "https" || (scheme == "http" && baseIsLoopback && endpointIsLoopback),
                      endpoint.host != nil,
                      endpoint.user == nil,
                      endpoint.password == nil,
                      endpoint.fragment == nil,
                      endpoint.query == nil,
                      scheme == baseURL.scheme?.lowercased(),
                      endpoint.host?.lowercased() == baseURL.host?.lowercased(),
                      (endpoint.port ?? (scheme == "https" ? 443 : 80))
                        == (baseURL.port ?? (baseURL.scheme?.lowercased() == "https" ? 443 : 80))
                else { throw PiServiceError.unsupportedAuthentication }
            }
        }
    }

    struct Compatibility: Decodable, Equatable, Sendable {
        let minimumApiVersion: String
        let maximumApiVersion: String
    }

    struct Authentication: Decodable, Equatable, Sendable {
        let type: String
        let clientId: String
        let authorizationEndpoint: URL
        var credentialEndpoint: URL? = nil
        let tokenEndpoint: URL
        let revocationEndpoint: URL
        let scopes: [String]
        let pkceMethods: [String]
        let accessTokenLifetimeSeconds: Int
        let refreshTokenRotation: String
    }

    struct Capabilities: Decodable, Equatable, Sendable {
        enum AttachmentSource: String, Decodable, Equatable, Sendable {
            case photoLibrary = "photo_library"
            case camera
            case filePicker = "file_picker"
        }

        struct Attachments: Decodable, Equatable, Sendable {
            let images: Bool
            let files: Bool
            let sources: [AttachmentSource]
            let mediaTypes: [String]
            let modelCompatibilityField: String

            init(
                images: Bool,
                files: Bool,
                sources: [AttachmentSource],
                mediaTypes: [String],
                modelCompatibilityField: String
            ) {
                self.images = images
                self.files = files
                self.sources = sources
                self.mediaTypes = mediaTypes
                self.modelCompatibilityField = modelCompatibilityField
            }
        }

        let repositories: Bool
        let models: Bool
        let thinking: Bool
        let sessions: Bool
        let sessionSearch: Bool
        let sessionDelete: Bool
        let commands: Bool
        let sse: Bool
        let authoritativeSnapshot: Bool
        let eventIds: Bool
        let replay: Bool
        let idempotency: Bool
        let singleWriter: Bool
        let takeover: Bool
        let release: Bool
        let abort: Bool
        let retry: Bool
        let attachments: Attachments

        var missingRequired: [String] {
            [
                (repositories, "repositories"), (models, "models"), (thinking, "thinking"),
                (sessions, "sessions"), (sessionSearch, "sessionSearch"),
                (sessionDelete, "sessionDelete"), (commands, "commands"), (sse, "sse"),
                (authoritativeSnapshot, "authoritativeSnapshot"), (eventIds, "eventIds"),
                (replay, "replay"), (idempotency, "idempotency"),
                (singleWriter, "singleWriter"), (takeover, "takeover"),
                (release, "release"), (abort, "abort"), (retry, "retry"),
                (attachments.images || attachments.files, "attachments"),
            ].compactMap { $0.0 ? nil : $0.1 }
        }
    }

    struct Limits: Decodable, Equatable, Sendable {
        let readTimeoutMs: Int
        let mutationTimeoutMs: Int
        let sseConnectTimeoutMs: Int
        let replayRetentionEvents: Int
        let replayRetentionSeconds: Int
        let idempotencyRetentionSeconds: Int
        let attachmentMaxBytes: Int
        let attachmentTotalBytes: Int
        let attachmentsPerPrompt: Int
        let attachmentUploadTimeoutMs: Int
        let attachmentDownloadTimeoutMs: Int
        let attachmentMediaTypes: [String]
        let attachmentDigestAlgorithm: String
    }

    struct Repository: Decodable, Equatable, Sendable, Identifiable {
        let id: String
        let displayName: String
    }

    enum ModelInput: String, Decodable, Equatable, Sendable { case text, image, file }
    enum ThinkingLevel: String, Codable, CaseIterable, Equatable, Sendable {
        case off, minimal, low, medium, high, xhigh, max
    }

    struct Model: Decodable, Equatable, Sendable, Identifiable {
        struct Attachments: Decodable, Equatable, Sendable {
            enum Kind: String, Decodable, Equatable, Sendable { case image }
            let supported: Bool
            let kinds: [Kind]
            let mediaTypes: [String]
            let maxBytes: Int
            let maxCount: Int
        }

        let provider: String
        let id: String
        let name: String
        let reasoning: Bool
        let input: [ModelInput]
        let thinkingLevels: [ThinkingLevel]
        let contextWindow: Int?
        let maxOutputTokens: Int?
        let attachments: Attachments

        init(
            provider: String,
            id: String,
            name: String,
            reasoning: Bool,
            input: [ModelInput],
            thinkingLevels: [ThinkingLevel],
            contextWindow: Int?,
            maxOutputTokens: Int?,
            attachments: Attachments
        ) {
            self.provider = provider
            self.id = id
            self.name = name
            self.reasoning = reasoning
            self.input = input
            self.thinkingLevels = thinkingLevels
            self.contextWindow = contextWindow
            self.maxOutputTokens = maxOutputTokens
            self.attachments = attachments
        }
    }

    enum Runtime: String, Decodable, Equatable, Sendable { case stopped, starting, running, stopping }
    enum RunStatus: String, Decodable, Equatable, Sendable { case idle, running, failed }
    enum SessionLifecycle: String, Codable, Equatable, Sendable {
        case idle, running, restoring, released, failed, stopped
    }

    struct SessionSummary: Decodable, Equatable, Sendable, Identifiable {
        struct Run: Decodable, Equatable, Sendable { let status: RunStatus }
        struct Controller: Decodable, Equatable, Sendable {
            let clientId: String?
            let leaseExpiresAt: Date?
        }
        let sessionId: String
        let repositoryId: String
        let name: String?
        let revision: Int
        let lastEventId: String
        let createdAt: Date
        let modifiedAt: Date
        let messageCount: Int
        let lifecycle: SessionLifecycle
        let runtime: Runtime
        let run: Run
        let controller: Controller
        var id: String { sessionId }
        var isActive: Bool { lifecycle == .running || lifecycle == .restoring }
    }

    struct SessionList: Decodable, Equatable, Sendable {
        let items: [SessionSummary]
        let total: Int
        let authoritative: Bool

        func validate() throws {
            guard authoritative,
                  total >= 0,
                  total >= items.count,
                  items.allSatisfy({ item in
                      item.revision >= 1
                          && item.messageCount >= 0
                          && (try? EventID(item.lastEventId)) != nil
                  })
            else {
                throw PiServiceError.invalidResponse
            }
        }
    }

    struct Snapshot: Decodable, Equatable, Sendable {
        struct Run: Decodable, Equatable, Sendable { let status: RunStatus; let operationId: String? }
        struct Controller: Decodable, Equatable, Sendable { let clientId: String?; let leaseExpiresAt: Date? }
        struct Configuration: Decodable, Equatable, Sendable {
            struct Model: Decodable, Equatable, Sendable { let provider: String; let id: String }
            let model: Model?
            let thinkingLevel: ThinkingLevel
        }

        let contract: String
        let sessionId: String
        let repositoryId: String
        let revision: Int
        let lastEventId: String
        let lifecycle: SessionLifecycle
        let runtime: Runtime
        let run: Run
        let controller: Controller
        let configuration: Configuration
        let messages: [Message]
        let attachments: [Attachment]

        func validate() throws {
            guard contract == PiGatewayWire.contract else {
                throw PiServiceError.unsupportedGatewayVersion(contract)
            }
            _ = try EventID(lastEventId)
        }
    }

    struct Message: Decodable, Equatable, Sendable {
        enum Role: String, Decodable, Equatable, Sendable { case user, assistant, tool }
        enum Status: String, Decodable, Equatable, Sendable { case streaming, completed, aborted, error }
        struct Content: Decodable, Equatable, Sendable {
            enum Kind: String, Decodable, Equatable, Sendable {
                case text, thinking, toolCall = "tool_call", toolResult = "tool_result", attachment
            }
            let type: Kind
            let text: String?
            let toolCallId: String?
            let attachmentId: String?
        }
        let id: String
        let role: Role
        let status: Status
        let content: [Content]
    }

    struct Attachment: Decodable, Equatable, Sendable {
        enum Status: String, Decodable, Equatable, Sendable { case ready, consumed, rejected, expired }
        let attachmentId: String
        let fileName: String
        let mediaType: String
        let byteLength: Int
        let sha256: String
        let status: Status
        let expiresAt: Date
    }

    struct Event: Decodable, Equatable, Sendable {
        let contract: String
        let id: String
        let sessionId: String
        let sessionRevision: Int
        let occurredAt: Date
        let type: String
        let data: [String: PiJSONValue]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            let allowed = Set(["contract", "id", "sessionId", "sessionRevision", "occurredAt", "type", "data"])
            guard Set(container.allKeys.map(\.stringValue)) == allowed else {
                throw PiAdapterError.unknownEnvelopeField
            }
            contract = try container.decode(String.self, forKey: .init("contract"))
            id = try container.decode(String.self, forKey: .init("id"))
            sessionId = try container.decode(String.self, forKey: .init("sessionId"))
            sessionRevision = try container.decode(Int.self, forKey: .init("sessionRevision"))
            occurredAt = try container.decode(Date.self, forKey: .init("occurredAt"))
            type = try container.decode(String.self, forKey: .init("type"))
            data = try container.decode([String: PiJSONValue].self, forKey: .init("data"))
        }
    }

    struct EventID: Comparable, Equatable, Sendable {
        let rawValue: UInt64
        init(_ value: String) throws {
            guard !value.isEmpty,
                  value == "0" || value.first != "0",
                  value.allSatisfy(\.isNumber),
                  let rawValue = UInt64(value)
            else { throw PiAdapterError.invalidEventID }
            self.rawValue = rawValue
        }
        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
        var string: String { String(rawValue) }
    }

    struct MutationReceipt: Codable, Equatable, Sendable {
        enum Status: String, Codable, Equatable, Sendable { case applied }
        let status: Status
        let sessionId: String
        let revision: Int
        let operationId: String?
        let afterEventId: String
        let responseStatus: Int

        init(
            sessionId: String,
            revision: Int,
            operationId: String?,
            afterEventId: String,
            responseStatus: Int = 202
        ) {
            status = .applied
            self.sessionId = sessionId
            self.revision = revision
            self.operationId = operationId
            self.afterEventId = afterEventId
            self.responseStatus = responseStatus
        }
    }

    struct DeleteMutationReceipt: Decodable, Equatable, Sendable {
        let status: MutationReceipt.Status
        let sessionId: String
        let revision: Int
        let operationId: String?
        let afterEventId: String
        let responseStatus: Int
        let deleted: Bool

        func validate(sessionID: String) throws {
            guard status == .applied,
                  sessionId == sessionID,
                  revision >= 1,
                  operationId == nil,
                  responseStatus == 200,
                  deleted,
                  (try? EventID(afterEventId)) != nil
            else { throw PiServiceError.invalidResponse }
        }
    }

    enum MutationReceiptLookup: Decodable, Equatable, Sendable {
        case pending(sessionId: String)
        case applied(MutationReceipt)

        private enum CodingKeys: String, CodingKey { case status, sessionId }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(String.self, forKey: .status) {
            case "pending":
                self = .pending(sessionId: try container.decode(String.self, forKey: .sessionId))
            case "applied":
                self = .applied(try MutationReceipt(from: decoder))
            default:
                throw PiServiceError.invalidResponse
            }
        }
    }

    struct ErrorResponse: Decodable, Equatable, Sendable {
        struct Detail: Decodable, Equatable, Sendable {
            let code: String
            let message: String
            let requestId: String
            let retryable: Bool
        }
        let error: Detail
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { return nil }
}

extension JSONDecoder {
    static var piGateway: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) { return date }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            guard let date = standard.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Invalid ISO-8601 date"
                )
            }
            return date
        }
        return decoder
    }
}
