import CryptoKit
import Foundation

struct PiServerConfiguration: Equatable, Sendable {
    let baseURL: URL
    let token: String?

    init(baseURL: URL, token: String? = nil) throws {
        guard let scheme = baseURL.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              baseURL.host != nil,
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.query == nil,
              baseURL.fragment == nil
        else { throw PiServiceError.invalidServerURL }
        if scheme == "http", !Self.isLoopback(baseURL.host) { throw PiServiceError.insecureTransport }
        self.baseURL = baseURL
        self.token = token?.trimmingCharacters(in: .whitespacesAndNewlines).piNilIfEmpty
    }

    private static func isLoopback(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }
}

enum PiServiceError: Error, Equatable, LocalizedError {
    case invalidServerURL
    case insecureTransport
    case authenticationRequired
    case accessDenied
    case sessionUnavailable
    case conflict
    case timedOut
    case networkUnavailable
    case connectionLost
    case invalidResponse
    case unsupportedGatewayVersion(String)
    case unsupportedAuthentication
    case capabilityUnavailable([String])
    case gateway(code: String, retryable: Bool)
    case replayCursorExpired
    case mutationNotFound
    case httpFailure(statusCode: Int)
    case transportFailure(code: Int)
    case malformedEvent
    case eventTooLarge
    case eventBufferOverflow
    case eventQueueOverflow
    case eventStreamEnded

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: String(localized: "The Jonwork connection is not configured correctly.")
        case .insecureTransport: String(localized: "Jonwork could not establish a secure connection.")
        case .authenticationRequired: String(localized: "Your Jonwork sign-in expired. Sign in again to continue.")
        case .accessDenied: String(localized: "You do not have permission to make this change.")
        case .sessionUnavailable: String(localized: "This conversation is no longer available.")
        case .conflict: String(localized: "The conversation changed on another device. Restoring the latest version…")
        case .timedOut: String(localized: "Jonwork took too long to respond. Check your connection and try again.")
        case .networkUnavailable: String(localized: "Jonwork is unreachable. Check your network and try again.")
        case .connectionLost: String(localized: "The Jonwork connection was interrupted. Reconnecting…")
        case .invalidResponse: String(localized: "Jonwork returned an unexpected response.")
        case .unsupportedGatewayVersion: String(localized: "This server uses an unsupported Pi Gateway version.")
        case .unsupportedAuthentication: String(localized: "This server does not support secure native sign-in.")
        case let .capabilityUnavailable(capabilities):
            "This server is missing required Pi capabilities: \(capabilities.joined(separator: ", "))."
        case .gateway: String(localized: "Jonwork could not complete the request.")
        case .replayCursorExpired: String(localized: "Conversation history must be restored from the server.")
        case .mutationNotFound: String(localized: "The previous request is no longer retained by the server.")
        case .httpFailure: String(localized: "Jonwork could not complete the request. Try again later.")
        case .transportFailure: String(localized: "Jonwork could not connect. Check your network and try again.")
        case .malformedEvent: String(localized: "Jonwork received an unreadable update.")
        case .eventTooLarge, .eventBufferOverflow, .eventQueueOverflow:
            String(localized: "Jonwork received too much live data. Reconnecting…")
        case .eventStreamEnded: String(localized: "The Jonwork connection ended. Reconnecting…")
        }
    }

    var redactedDiagnostic: String {
        switch self {
        case let .httpFailure(statusCode): "http_status_\(statusCode)"
        case let .transportFailure(code): "transport_code_\(code)"
        case let .gateway(code, _): "gateway_\(code)"
        default: String(describing: self)
        }
    }

    var isRecoverableTransportFailure: Bool {
        switch self {
        case .timedOut, .networkUnavailable, .connectionLost, .transportFailure,
             .eventStreamEnded, .eventTooLarge, .eventBufferOverflow, .eventQueueOverflow,
             .replayCursorExpired, .conflict:
            return true
        default:
            return false
        }
    }
}

protocol PiServiceProtocol: Sendable {
    func cancelAllRequests() async
    func discover() async throws -> PiGatewayWire.Discovery
    func listRepositories() async throws -> [PiGatewayWire.Repository]
    func listModels() async throws -> [PiGatewayWire.Model]
    func listSessions(repositoryID: String?) async throws -> [PiGatewayWire.SessionSummary]
    func createSession(repositoryID: String, name: String?, clientID: String, idempotencyKey: String) async throws -> PiGatewayWire.Snapshot
    func restoreSession(sessionID: String, clientID: String, context: PiMutationContext) async throws -> PiGatewayWire.Snapshot
    func snapshot(sessionID: String) async throws -> PiGatewayWire.Snapshot
    func events(sessionID: String, clientID: String, afterEventID: String) -> AsyncThrowingStream<PiGatewayWire.Event, Error>
    func mutate(_ action: PiConversationAction, sessionID: String, clientID: String, context: PiMutationContext) async throws -> PiGatewayWire.MutationReceipt
    func mutationReceipt(sessionID: String, idempotencyKey: String, clientID: String) async throws -> PiGatewayWire.MutationReceiptLookup
    func uploadAttachment(
        data: Data,
        fileName: String,
        mediaType: String,
        repositoryID: String,
        idempotencyKey: String
    ) async throws -> PiGatewayWire.Attachment
}

extension PiServiceProtocol {
    func cancelAllRequests() async {}
    func discover() async throws -> PiGatewayWire.Discovery { throw PiServiceError.invalidResponse }
    func listRepositories() async throws -> [PiGatewayWire.Repository] { throw PiServiceError.invalidResponse }
    func listModels() async throws -> [PiGatewayWire.Model] { throw PiServiceError.invalidResponse }
    func listSessions(repositoryID _: String?) async throws -> [PiGatewayWire.SessionSummary] { throw PiServiceError.invalidResponse }
    func createSession(repositoryID _: String, name _: String?, clientID _: String, idempotencyKey _: String) async throws -> PiGatewayWire.Snapshot { throw PiServiceError.invalidResponse }
    func restoreSession(sessionID _: String, clientID _: String, context _: PiMutationContext) async throws -> PiGatewayWire.Snapshot { throw PiServiceError.invalidResponse }
    func snapshot(sessionID _: String) async throws -> PiGatewayWire.Snapshot { throw PiServiceError.invalidResponse }
    func events(sessionID _: String, clientID _: String, afterEventID _: String) -> AsyncThrowingStream<PiGatewayWire.Event, Error> {
        AsyncThrowingStream { $0.finish(throwing: PiServiceError.invalidResponse) }
    }
    func mutate(_: PiConversationAction, sessionID _: String, clientID _: String, context _: PiMutationContext) async throws -> PiGatewayWire.MutationReceipt { throw PiServiceError.invalidResponse }
    func mutationReceipt(sessionID _: String, idempotencyKey _: String, clientID _: String) async throws -> PiGatewayWire.MutationReceiptLookup { throw PiServiceError.invalidResponse }
    func uploadAttachment(data _: Data, fileName _: String, mediaType _: String, repositoryID _: String, idempotencyKey _: String) async throws -> PiGatewayWire.Attachment { throw PiServiceError.invalidResponse }
}

final class PiService: PiServiceProtocol, @unchecked Sendable {
    static let maximumEventBytes = 512 * 1024
    static let maximumBufferedEventBytes = 1024 * 1024
    static let maximumQueuedEvents = 128

    private let configuration: PiServerConfiguration
    private let session: URLSession
    private let stateLock = NSLock()
    private var discoveredLimits: PiGatewayWire.Limits?

    init(configuration: PiServerConfiguration, session: URLSession? = nil) {
        self.configuration = configuration
        self.session = session ?? URLSession(configuration: .ephemeral)
    }

    func cancelAllRequests() async {
        await withCheckedContinuation { continuation in
            session.getAllTasks { tasks in
                tasks.forEach { $0.cancel() }
                continuation.resume()
            }
        }
    }

    func discover() async throws -> PiGatewayWire.Discovery {
        let discovery: PiGatewayWire.Discovery = try await get(".well-known/pi-gateway", authenticated: false)
        try discovery.validate(baseURL: configuration.baseURL)
        stateLock.withLock { discoveredLimits = discovery.limits }
        return discovery
    }

    func listRepositories() async throws -> [PiGatewayWire.Repository] {
        let response: ItemResponse<PiGatewayWire.Repository> = try await get("v1/repositories")
        return response.items
    }

    func listModels() async throws -> [PiGatewayWire.Model] {
        let response: ItemResponse<PiGatewayWire.Model> = try await get("v1/models")
        return response.items
    }

    func listSessions(repositoryID: String?) async throws -> [PiGatewayWire.SessionSummary] {
        let query = repositoryID?.piNilIfEmpty.map { [URLQueryItem(name: "repositoryId", value: $0)] } ?? []
        let response: ItemResponse<PiGatewayWire.SessionSummary> = try await get("v1/sessions", queryItems: query)
        return response.items
    }

    func createSession(
        repositoryID: String,
        name: String?,
        clientID: String,
        idempotencyKey: String
    ) async throws -> PiGatewayWire.Snapshot {
        let body = CreateSessionRequest(clientId: clientID, repositoryId: repositoryID, name: name?.piNilIfEmpty)
        let snapshot: PiGatewayWire.Snapshot = try await request(
            method: "POST",
            path: "v1/sessions",
            headers: ["Idempotency-Key": try Self.idempotencyKey(idempotencyKey)],
            body: JSONEncoder().encode(body)
        )
        try snapshot.validate()
        return snapshot
    }

    func restoreSession(
        sessionID: String,
        clientID: String,
        context: PiMutationContext
    ) async throws -> PiGatewayWire.Snapshot {
        let snapshot: PiGatewayWire.Snapshot = try await mutationRequest(
            method: "POST",
            path: "v1/sessions/\(try Self.segment(sessionID))/restore",
            context: context,
            body: JSONEncoder().encode(ClientRequest(clientId: clientID))
        )
        try snapshot.validate()
        return snapshot
    }

    func snapshot(sessionID: String) async throws -> PiGatewayWire.Snapshot {
        let snapshot: PiGatewayWire.Snapshot = try await get("v1/sessions/\(try Self.segment(sessionID))")
        try snapshot.validate()
        return snapshot
    }

    func state(sessionID: String) async throws -> PiGatewayWire.Snapshot {
        try await snapshot(sessionID: sessionID)
    }

    func events(
        sessionID: String,
        clientID: String,
        afterEventID: String
    ) -> AsyncThrowingStream<PiGatewayWire.Event, Error> {
        AsyncThrowingStream(bufferingPolicy: .bufferingOldest(Self.maximumQueuedEvents)) { continuation in
            let task = Task { [session, configuration] in
                do {
                    var components = URLComponents(
                        url: configuration.baseURL.appending(path: "v1/sessions/\(try Self.segment(sessionID))/events"),
                        resolvingAgainstBaseURL: false
                    )
                    components?.queryItems = [.init(name: "clientId", value: clientID)]
                    guard let url = components?.url else { throw PiServiceError.invalidServerURL }
                    var request = URLRequest(url: url)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue(afterEventID, forHTTPHeaderField: "Last-Event-ID")
                    try Self.authorize(&request, token: configuration.token)
                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.validate(response: response, data: nil)
                    guard response.mimeType == "text/event-stream" else { throw PiServiceError.invalidResponse }

                    var parser = PiSSERecordParser(
                        maximumEventBytes: Self.maximumEventBytes,
                        maximumBufferedEventBytes: Self.maximumBufferedEventBytes
                    )
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if let record = try parser.consume(byte) {
                            try Self.yield(try Self.decodeEvent(record), to: continuation)
                        }
                    }
                    if let record = try parser.finish() {
                        try Self.yield(try Self.decodeEvent(record), to: continuation)
                    }
                    throw PiServiceError.eventStreamEnded
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func mutate(
        _ action: PiConversationAction,
        sessionID: String,
        clientID: String,
        context: PiMutationContext
    ) async throws -> PiGatewayWire.MutationReceipt {
        let encoded: (String, String, Data)
        switch action {
        case let .rename(name):
            encoded = ("PATCH", "v1/sessions/\(try Self.segment(sessionID))", try encode(["clientId": clientID, "name": name]))
        case .takeOver:
            encoded = ("POST", "v1/sessions/\(try Self.segment(sessionID))/takeover", try JSONEncoder().encode(ClientRequest(clientId: clientID)))
        case .release:
            encoded = ("POST", "v1/sessions/\(try Self.segment(sessionID))/release", try JSONEncoder().encode(ClientRequest(clientId: clientID)))
        default:
            encoded = ("POST", "v1/sessions/\(try Self.segment(sessionID))/commands", try encodeCommand(action, clientID: clientID))
        }
        return try await mutationRequest(method: encoded.0, path: encoded.1, context: context, body: encoded.2)
    }

    func mutationReceipt(
        sessionID: String,
        idempotencyKey: String,
        clientID: String
    ) async throws -> PiGatewayWire.MutationReceiptLookup {
        try await request(
            method: "GET",
            path: "v1/sessions/\(try Self.segment(sessionID))/mutation-receipt",
            headers: [
                "Idempotency-Key": try Self.idempotencyKey(idempotencyKey),
                "X-Client-Id": clientID,
            ]
        )
    }

    func uploadAttachment(
        data: Data,
        fileName: String,
        mediaType: String,
        repositoryID: String,
        idempotencyKey: String
    ) async throws -> PiGatewayWire.Attachment {
        let normalizedFileName = fileName.precomposedStringWithCanonicalMapping
        guard !data.isEmpty,
              !normalizedFileName.isEmpty,
              normalizedFileName != ".",
              normalizedFileName != "..",
              !normalizedFileName.contains("\0"),
              !normalizedFileName.contains("/"),
              !normalizedFileName.contains("\\"),
              normalizedFileName.lengthOfBytes(using: .utf8) <= 255
        else { throw PiServiceError.invalidResponse }
        let encodedFileName = Self.percentEncodeHeaderValue(normalizedFileName)
        guard encodedFileName.utf8.count <= 255 else { throw PiServiceError.invalidResponse }
        guard let limits = stateLock.withLock({ discoveredLimits }) else {
            throw PiServiceError.capabilityUnavailable(["discovery"])
        }
        guard data.count <= min(limits.attachmentMaxBytes, 10 * 1024 * 1024) else {
            throw PiServiceError.invalidResponse
        }
        let digest = Data(SHA256.hash(data: data)).base64EncodedString()
        let headers = [
            "Idempotency-Key": try Self.idempotencyKey(idempotencyKey),
            "X-File-Name": encodedFileName,
            "Content-Type": mediaType,
            "Content-Length": String(data.count),
            "Content-Digest": "sha-256=:\(digest):",
        ]
        return try await request(
            method: "POST",
            path: "v1/attachments",
            queryItems: [.init(name: "repositoryId", value: repositoryID)],
            headers: headers,
            body: data,
            timeoutInterval: TimeInterval(limits.attachmentUploadTimeoutMs) / 1_000
        )
    }

    private func mutationRequest<Response: Decodable>(
        method: String,
        path: String,
        context: PiMutationContext,
        body: Data
    ) async throws -> Response {
        try await request(
            method: method,
            path: path,
            headers: [
                "Idempotency-Key": try Self.idempotencyKey(context.idempotencyKey),
                "If-Match": "\"\(context.revision)\"",
            ],
            body: body
        )
    }

    private func get<Response: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        authenticated: Bool = true
    ) async throws -> Response {
        try await request(method: "GET", path: path, queryItems: queryItems, authenticated: authenticated)
    }

    private func request<Response: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        authenticated: Bool = true,
        timeoutInterval: TimeInterval? = nil
    ) async throws -> Response {
        do {
            var components = URLComponents(url: configuration.baseURL.appending(path: path), resolvingAgainstBaseURL: false)
            if !queryItems.isEmpty { components?.queryItems = queryItems }
            guard let url = components?.url else { throw PiServiceError.invalidServerURL }
            var request = URLRequest(url: url)
            request.httpMethod = method
            request.httpBody = body
            let limits = stateLock.withLock { discoveredLimits }
            if let timeoutInterval {
                request.timeoutInterval = timeoutInterval
            } else if path == ".well-known/pi-gateway" {
                request.timeoutInterval = 10
            } else if method == "GET", let limits {
                request.timeoutInterval = TimeInterval(limits.readTimeoutMs) / 1_000
            } else if let limits {
                request.timeoutInterval = TimeInterval(limits.mutationTimeoutMs) / 1_000
            }
            if body != nil, headers["Content-Type"] == nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
            if authenticated { try Self.authorize(&request, token: configuration.token) }
            let maximumBodyBytes = path == ".well-known/pi-gateway" ? 1_048_576 : 25 * 1024 * 1024
            let (data, response) = try await boundedResponse(
                for: request,
                maximumBodyBytes: maximumBodyBytes
            )
            try Self.validate(response: response, data: data)
            guard response.mimeType == "application/json" || response.mimeType?.hasSuffix("+json") == true else {
                throw PiServiceError.invalidResponse
            }
            return try JSONDecoder.piGateway.decode(Response.self, from: data)
        } catch {
            throw Self.map(error)
        }
    }

    private func boundedResponse(
        for request: URLRequest,
        maximumBodyBytes: Int
    ) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        let declaredLength = response.expectedContentLength
        guard declaredLength < 0
                || declaredLength <= Int64(maximumBodyBytes)
        else {
            bytes.task.cancel()
            throw PiServiceError.invalidResponse
        }
        var data = Data()
        if declaredLength > 0 {
            data.reserveCapacity(Int(declaredLength))
        }
        for try await byte in bytes {
            guard data.count < maximumBodyBytes else {
                bytes.task.cancel()
                throw PiServiceError.invalidResponse
            }
            data.append(byte)
        }
        return (data, response)
    }

    private func encodeCommand(_ action: PiConversationAction, clientID: String) throws -> Data {
        let object: [String: Any]
        switch action {
        case let .send(text, attachmentIDs, delivery):
            let type = switch delivery { case .prompt: "prompt"; case .steer: "steer"; case .followUp: "follow_up" }
            object = ["clientId": clientID, "type": type, "text": text, "attachmentIds": attachmentIDs]
        case .abort:
            object = ["clientId": clientID, "type": "abort"]
        case let .retry(operationID):
            object = ["clientId": clientID, "type": "retry", "operationId": operationID]
        case let .setModel(provider, modelID):
            object = ["clientId": clientID, "type": "set_model", "provider": provider, "modelId": modelID]
        case let .setThinkingLevel(level):
            object = ["clientId": clientID, "type": "set_thinking_level", "level": level.rawValue]
        case let .compact(instructions):
            object = ["clientId": clientID, "type": "compact", "instructions": instructions ?? NSNull()]
        case .rename, .takeOver, .release:
            throw PiServiceError.invalidResponse
        }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func encode(_ object: [String: String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private static func segment(_ value: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard !value.isEmpty, value.count <= 128,
              value.unicodeScalars.allSatisfy(allowed.contains)
        else { throw PiServiceError.invalidServerURL }
        return value
    }

    private static func idempotencyKey(_ value: String) throws -> String {
        guard (8 ... 128).contains(value.count) else { throw PiServiceError.invalidResponse }
        return value
    }

    private static func percentEncodeHeaderValue(_ value: String) -> String {
        let hexadecimal = Array("0123456789ABCDEF".utf8)
        var result: [UInt8] = []
        for byte in value.utf8 {
            switch byte {
            case 0x41 ... 0x5A, 0x61 ... 0x7A, 0x30 ... 0x39, 0x2D, 0x2E, 0x5F, 0x7E:
                result.append(byte)
            default:
                result.append(0x25)
                result.append(hexadecimal[Int(byte >> 4)])
                result.append(hexadecimal[Int(byte & 0x0F)])
            }
        }
        return String(decoding: result, as: UTF8.self)
    }

    private static func authorize(_ request: inout URLRequest, token: String?) throws {
        guard let token else { throw PiServiceError.authenticationRequired }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private static func validate(response: URLResponse, data: Data?) throws {
        guard let response = response as? HTTPURLResponse else { throw PiServiceError.invalidResponse }
        guard (200 ..< 300).contains(response.statusCode) else {
            if let data,
               let structured = try? JSONDecoder.piGateway.decode(PiGatewayWire.ErrorResponse.self, from: data)
            {
                switch structured.error.code {
                case "unauthenticated": throw PiServiceError.authenticationRequired
                case "forbidden", "not_controller": throw PiServiceError.accessDenied
                case "session_not_found", "session_not_running": throw PiServiceError.sessionUnavailable
                case "revision_conflict": throw PiServiceError.conflict
                case "replay_cursor_expired": throw PiServiceError.replayCursorExpired
                case "mutation_not_found": throw PiServiceError.mutationNotFound
                default: throw PiServiceError.gateway(code: structured.error.code, retryable: structured.error.retryable)
                }
            }
            switch response.statusCode {
            case 401: throw PiServiceError.authenticationRequired
            case 403: throw PiServiceError.accessDenied
            case 404: throw PiServiceError.sessionUnavailable
            case 409: throw PiServiceError.conflict
            default: throw PiServiceError.httpFailure(statusCode: response.statusCode)
            }
        }
    }

    private static func map(_ error: Error) -> Error {
        if let error = error as? PiServiceError { return error }
        if let error = error as? PiAdapterError { return error }
        if error is DecodingError { return PiServiceError.invalidResponse }
        guard let error = error as? URLError else { return PiServiceError.invalidResponse }
        switch error.code {
        case .timedOut: return PiServiceError.timedOut
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return PiServiceError.networkUnavailable
        case .networkConnectionLost: return PiServiceError.connectionLost
        case .cancelled: return CancellationError()
        default: return PiServiceError.transportFailure(code: error.errorCode)
        }
    }

    private static func decodeEvent(_ record: PiSSERecord) throws -> PiGatewayWire.Event {
        do {
            let event = try JSONDecoder.piGateway.decode(PiGatewayWire.Event.self, from: record.data)
            guard record.id == event.id, record.event == event.type else { throw PiServiceError.malformedEvent }
            return event
        } catch let error as PiServiceError {
            throw error
        } catch {
            throw PiServiceError.malformedEvent
        }
    }

    private static func yield(
        _ event: PiGatewayWire.Event,
        to continuation: AsyncThrowingStream<PiGatewayWire.Event, Error>.Continuation
    ) throws {
        switch continuation.yield(event) {
        case .enqueued: break
        case .dropped: throw PiServiceError.eventQueueOverflow
        case .terminated: throw CancellationError()
        @unknown default: throw PiServiceError.eventQueueOverflow
        }
    }
}

struct PiSSERecord: Equatable, Sendable { let id: String; let event: String; let data: Data }

struct PiSSERecordParser: Sendable {
    private let maximumEventBytes: Int
    private let maximumBufferedEventBytes: Int
    private var line: [UInt8] = []
    private var data: [UInt8] = []
    private var id: String?
    private var event: String?
    private var bufferedEventBytes = 0

    init(maximumEventBytes: Int, maximumBufferedEventBytes: Int) {
        precondition(maximumEventBytes > 0)
        precondition(maximumBufferedEventBytes >= maximumEventBytes)
        self.maximumEventBytes = maximumEventBytes
        self.maximumBufferedEventBytes = maximumBufferedEventBytes
    }

    mutating func consume(_ byte: UInt8) throws -> PiSSERecord? {
        bufferedEventBytes += 1
        guard bufferedEventBytes <= maximumBufferedEventBytes else { throw PiServiceError.eventBufferOverflow }
        if byte == 0x0A { return try consumeLine() }
        line.append(byte)
        return nil
    }

    mutating func finish() throws -> PiSSERecord? {
        if !line.isEmpty { _ = try consumeLine() }
        return try dispatchEvent()
    }

    private mutating func consumeLine() throws -> PiSSERecord? {
        if line.last == 0x0D { line.removeLast() }
        defer { line.removeAll(keepingCapacity: true) }
        if line.isEmpty {
            let record = try dispatchEvent()
            bufferedEventBytes = 0
            return record
        }
        guard line.first != UInt8(ascii: ":") else { return nil }
        guard let raw = String(bytes: line, encoding: .utf8), let colon = raw.firstIndex(of: ":") else { return nil }
        let field = String(raw[..<colon])
        var value = String(raw[raw.index(after: colon)...])
        if value.first == " " { value.removeFirst() }
        switch field {
        case "id": id = value
        case "event": event = value
        case "data":
            if !data.isEmpty { data.append(0x0A) }
            data.append(contentsOf: value.utf8)
            guard data.count <= maximumEventBytes else { throw PiServiceError.eventTooLarge }
        default: break
        }
        return nil
    }

    private mutating func dispatchEvent() throws -> PiSSERecord? {
        guard !data.isEmpty else { return nil }
        defer { id = nil; event = nil; data.removeAll(keepingCapacity: true) }
        guard let id, let event else { throw PiServiceError.malformedEvent }
        return .init(id: id, event: event, data: Data(data))
    }
}

private struct ItemResponse<Item: Decodable>: Decodable { let items: [Item] }
private struct CreateSessionRequest: Encodable { let clientId: String; let repositoryId: String; let name: String? }
private struct ClientRequest: Encodable { let clientId: String }

private extension String {
    var piNilIfEmpty: String? { isEmpty ? nil : self }
}
