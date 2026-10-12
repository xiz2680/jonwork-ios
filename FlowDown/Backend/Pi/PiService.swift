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
        else {
            throw PiServiceError.invalidServerURL
        }
        if scheme == "http", !Self.isLoopback(baseURL.host) {
            throw PiServiceError.insecureTransport
        }
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
    case httpFailure(statusCode: Int)
    case transportFailure(code: Int)
    case malformedEvent
    case eventStreamEnded

    var errorDescription: String? {
        switch self {
        case .invalidServerURL: String(localized: "The Pi server address is invalid.")
        case .insecureTransport: String(localized: "Pi requires HTTPS except for a loopback development server.")
        case .authenticationRequired: String(localized: "Pi authentication failed. Check the access token and reconnect.")
        case .accessDenied: String(localized: "Pi denied this action. Refresh the session and verify controller access.")
        case .sessionUnavailable: String(localized: "This Pi session is no longer running. Return to Pi Server and resume it again.")
        case .conflict: String(localized: "Pi rejected the action because the session state changed. Refresh and try again.")
        case .timedOut: String(localized: "The Pi server timed out. Check the connection and try again.")
        case .networkUnavailable: String(localized: "The Pi server is unreachable. Check the network and server address.")
        case .connectionLost: String(localized: "The Pi connection was interrupted. Reconnecting…")
        case .invalidResponse: String(localized: "Pi returned an invalid response.")
        case .httpFailure: String(localized: "Pi could not complete the server request. Try again later.")
        case .transportFailure: String(localized: "Pi could not complete the connection. Check the server and try again.")
        case .malformedEvent: String(localized: "Pi returned a malformed event stream.")
        case .eventStreamEnded: String(localized: "The Pi event stream ended. Reconnecting…")
        }
    }

    var redactedDiagnostic: String {
        switch self {
        case let .httpFailure(statusCode): "http_status_\(statusCode)"
        case let .transportFailure(code): "transport_code_\(code)"
        default: String(describing: self)
        }
    }
}

protocol PiServiceProtocol: Sendable {
    func health() async throws
    func listModels() async throws -> [PiModel]
    func listRepositories() async throws -> [String]
    func listSessions(repository: String?) async throws -> [PiSessionSummary]
    func createSession(repository: String?, resumePath: String?, clientID: String) async throws -> String
    func state(sessionID: String) async throws -> PiSessionState
    func events(sessionID: String, clientID: String) -> AsyncThrowingStream<PiServerEvent, Error>
    func send(_ command: PiCommand, sessionID: String) async throws
    func takeOver(sessionID: String, clientID: String) async throws
    func release(sessionID: String, clientID: String) async throws
}

final class PiService: PiServiceProtocol, @unchecked Sendable {
    private let configuration: PiServerConfiguration
    private let session: URLSession

    init(configuration: PiServerConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    func health() async throws {
        let _: PiHealthResponse = try await get("health")
    }

    func listModels() async throws -> [PiModel] {
        let response: PiModelsResponse = try await get("api/models")
        return response.models
    }

    func listRepositories() async throws -> [String] {
        let response: PiRepositoriesResponse = try await get("api/repos")
        return response.repos
    }

    func listSessions(repository: String?) async throws -> [PiSessionSummary] {
        var items: [URLQueryItem] = []
        if let repository = repository?.piNilIfEmpty {
            items.append(.init(name: "cwd", value: repository))
        }
        let response: PiSessionsResponse = try await get("api/sessions", queryItems: items)
        return response.sessions
    }

    func createSession(repository: String?, resumePath: String?, clientID: String) async throws -> String {
        let request = PiCreateSessionRequest(
            clientId: clientID,
            cwd: repository?.piNilIfEmpty,
            resumeSessionPath: resumePath?.piNilIfEmpty,
        )
        let response: PiCreateSessionResponse = try await post("api/sessions", body: request)
        return response.sessionId
    }

    func state(sessionID: String) async throws -> PiSessionState {
        try await get("api/sessions/\(escaped(sessionID))/state")
    }

    func events(sessionID: String, clientID: String) -> AsyncThrowingStream<PiServerEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [session, configuration] in
                do {
                    var components = URLComponents(
                        url: configuration.baseURL.appending(path: "api/sessions/\(escaped(sessionID))/events"),
                        resolvingAgainstBaseURL: false,
                    )
                    components?.queryItems = [.init(name: "clientId", value: clientID)]
                    guard let url = components?.url else { throw PiServiceError.invalidServerURL }
                    var request = URLRequest(url: url)
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    Self.authorize(&request, token: configuration.token)
                    let (bytes, response) = try await session.bytes(for: request)
                    try Self.validate(response: response, data: nil)

                    var dataLines: [String] = []
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        if line.isEmpty {
                            if !dataLines.isEmpty {
                                let payload = dataLines.joined(separator: "\n")
                                guard let data = payload.data(using: .utf8) else { throw PiServiceError.malformedEvent }
                                continuation.yield(try Self.decodeEvent(data))
                                dataLines.removeAll(keepingCapacity: true)
                            }
                        } else if line.hasPrefix("data:") {
                            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
                        }
                    }
                    if !dataLines.isEmpty {
                        guard let data = dataLines.joined(separator: "\n").data(using: .utf8) else {
                            throw PiServiceError.malformedEvent
                        }
                        continuation.yield(try Self.decodeEvent(data))
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

    func send(_ command: PiCommand, sessionID: String) async throws {
        let _: PiOKResponse = try await post("api/sessions/\(escaped(sessionID))/command", body: command)
    }

    func takeOver(sessionID: String, clientID: String) async throws {
        let _: PiOKResponse = try await post(
            "api/sessions/\(escaped(sessionID))/takeover",
            body: PiClientRequest(clientId: clientID),
        )
    }

    func release(sessionID: String, clientID: String) async throws {
        let _: PiOKResponse = try await post(
            "api/sessions/\(escaped(sessionID))/release",
            body: PiClientRequest(clientId: clientID),
        )
    }

    private func get<Response: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> Response {
        var components = URLComponents(url: configuration.baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw PiServiceError.invalidServerURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        return try await perform(request)
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: configuration.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await perform(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        do {
            var request = request
            Self.authorize(&request, token: configuration.token)
            let (data, response) = try await session.data(for: request)
            try Self.validate(response: response, data: data)
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw Self.map(error)
        }
    }

    private static func authorize(_ request: inout URLRequest, token: String?) {
        guard let token else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private static func validate(response: URLResponse, data: Data?) throws {
        guard let response = response as? HTTPURLResponse else { throw PiServiceError.invalidResponse }
        guard (200 ..< 300).contains(response.statusCode) else {
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
        if error is DecodingError { return PiServiceError.invalidResponse }
        guard let error = error as? URLError else { return PiServiceError.invalidResponse }
        switch error.code {
        case .timedOut:
            return PiServiceError.timedOut
        case .notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            return PiServiceError.networkUnavailable
        case .networkConnectionLost:
            return PiServiceError.connectionLost
        case .cancelled:
            return CancellationError()
        default:
            return PiServiceError.transportFailure(code: error.errorCode)
        }
    }

    private static func decodeEvent(_ data: Data) throws -> PiServerEvent {
        do {
            return try JSONDecoder().decode(PiServerEvent.self, from: data)
        } catch {
            throw PiServiceError.malformedEvent
        }
    }

    private func escaped(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }
}

private extension String {
    var piNilIfEmpty: String? { isEmpty ? nil : self }
}

private struct PiHealthResponse: Decodable { let ok: Bool }
private struct PiModelsResponse: Decodable { let models: [PiModel] }
private struct PiRepositoriesResponse: Decodable { let repos: [String] }
private struct PiSessionsResponse: Decodable { let sessions: [PiSessionSummary] }
private struct PiCreateSessionRequest: Encodable { let clientId: String; let cwd: String?; let resumeSessionPath: String? }
private struct PiCreateSessionResponse: Decodable { let sessionId: String }
private struct PiClientRequest: Encodable { let clientId: String }
private struct PiOKResponse: Decodable { let ok: Bool }
