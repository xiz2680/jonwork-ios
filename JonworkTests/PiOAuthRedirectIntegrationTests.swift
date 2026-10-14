@testable import Jonwork
import AuthenticationServices
import Foundation
import Network
import Testing

@Suite(.serialized)
struct PiOAuthRedirectIntegrationTests {
    @Test(arguments: [307, 308, 303]) @MainActor
    func realOAuthPostRedirectNeverReachesAnotherOrigin(_ status: Int) async throws {
        let target = try LoopbackOAuthServer(status: 200, target: nil)
        try await target.start()
        defer { target.stop() }
        let source = try LoopbackOAuthServer(status: status, target: target.url.appendingPathComponent("sink"))
        try await source.start()
        defer { source.stop() }
        let discovery = try makeDiscovery(origin: source.url)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let client = PiOAuthClient(anchor: { ASPresentationAnchor() }, session: session)
        let tokens = PiOAuthTokens(accessToken: String(repeating: "a", count: 32), refreshToken: "synthetic-refresh-marker-for-redirect-test", expiresAt: .distantPast)
        await #expect(throws: PiOAuthError.invalidAuthorizationResponse) { _ = try await client.refresh(tokens, discovery: discovery) }
        await #expect(throws: PiOAuthError.invalidAuthorizationResponse) { try await client.revoke(tokens, discovery: discovery) }
        #expect(source.requests == 2)
        #expect(target.requests == 0)
        #expect(target.bodyBytes == 0)
    }

    @Test(arguments: [307, 308, 303]) @MainActor
    func realSameOriginRedirectAndPasswordPostAreAlsoRefused(_ status: Int) async throws {
        let server = try LoopbackOAuthServer(status: status, target: nil, redirectsToSelf: true)
        try await server.start()
        defer { server.stop() }
        let discovery = try makeDiscovery(origin: server.url)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let browser = PiOAuthClient(anchor: { ASPresentationAnchor() }, session: session)
        let tokens = PiOAuthTokens(accessToken: String(repeating: "a", count: 32), refreshToken: "synthetic-marker", expiresAt: .distantPast)
        await #expect(throws: PiOAuthError.invalidAuthorizationResponse) { _ = try await browser.refresh(tokens, discovery: discovery) }
        let password = PiPasswordOAuthClient(credentials: .init(email: "fixture@example.test", password: "synthetic-password-marker"), session: session)
        await #expect(throws: PiOAuthError.invalidAuthorizationResponse) { _ = try await password.authorize(discovery: discovery, baseURL: server.url) }
        #expect(server.requests == 2)
        #expect(server.sinkRequests == 0)
    }

    @Test(arguments: [307, 308, 303])
    func authenticatedPromptAndAttachmentRedirectNeverReachAnotherOrigin(_ status: Int) async throws {
        let target = try LoopbackOAuthServer(status: 200, target: nil)
        try await target.start()
        defer { target.stop() }
        let source = try LoopbackOAuthServer(status: status, target: target.url.appendingPathComponent("sink"))
        try await source.start()
        defer { source.stop() }
        source.discoveryBody = try makeDiscoveryData(origin: source.url)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let service = PiService(configuration: try .init(baseURL: source.url, token: "synthetic-bearer-marker"), session: session)
        _ = try await service.discover()
        do {
            _ = try await service.mutate(.send(text: "synthetic-private-prompt-marker", attachmentIDs: [], delivery: .prompt), sessionID: "fixture-session", clientID: "fixture-client", context: .init(idempotencyKey: "fixture-command-key", revision: 1))
            Issue.record("Redirected command unexpectedly succeeded")
        } catch {}
        do {
            _ = try await service.uploadAttachment(data: Data("synthetic-private-attachment-marker".utf8), fileName: "fixture.txt", mediaType: "text/plain", repositoryID: "fixture-repository", idempotencyKey: "fixture-upload-key")
            Issue.record("Redirected upload unexpectedly succeeded")
        } catch {}
        #expect(source.requests == 3)
        #expect(source.commandRequests == 1)
        #expect(source.uploadRequests == 1)
        #expect(source.commandBodyBytes > 0)
        #expect(source.uploadBodyBytes > 0)
        #expect(target.requests == 0)
        #expect(target.bodyBytes == 0)
    }

    private func makeDiscovery(origin: URL) throws -> PiGatewayWire.Discovery {
        try JSONDecoder.piGateway.decode(PiGatewayWire.Discovery.self, from: makeDiscoveryData(origin: origin))
    }

    private func makeDiscoveryData(origin: URL) throws -> Data {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/PiGatewayV1/discovery.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var auth = try #require(object["authentication"] as? [String: Any])
        for (key, path) in [("authorizationEndpoint", "authorize"), ("credentialEndpoint", "password"), ("tokenEndpoint", "token"), ("revocationEndpoint", "revoke")] {
            auth[key] = origin.appendingPathComponent(path).absoluteString
        }
        object["authentication"] = auth
        return try JSONSerialization.data(withJSONObject: object)
    }
}

/// Two real TCP origins use synthetic markers only; request bodies are counted,
/// never retained or printed. Listener lifecycle is limited to this test.
private final class LoopbackOAuthServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "OAuthRedirectFixture")
    private let lock = NSLock()
    private let status: Int
    private let target: URL?
    private let redirectsToSelf: Bool
    private var requestCount = 0
    private var sinkCount = 0
    private var bodyCount = 0
    private var commandCount = 0
    private var uploadCount = 0
    private var commandBodyCount = 0
    private var uploadBodyCount = 0
    private var connections: [NWConnection] = []
    private var port: UInt16 = 0
    var discoveryBody: Data?

    init(status: Int, target: URL?, redirectsToSelf: Bool = false) throws {
        self.status = status
        self.target = target
        self.redirectsToSelf = redirectsToSelf
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }
    var url: URL { URL(string: "http://127.0.0.1:\(lock.withLock { port })")! }
    var requests: Int { lock.withLock { requestCount } }
    var sinkRequests: Int { lock.withLock { sinkCount } }
    var bodyBytes: Int { lock.withLock { bodyCount } }
    var commandRequests: Int { lock.withLock { commandCount } }
    var uploadRequests: Int { lock.withLock { uploadCount } }
    var commandBodyBytes: Int { lock.withLock { commandBodyCount } }
    var uploadBodyBytes: Int { lock.withLock { uploadBodyCount } }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let self, let port = self.listener.port?.rawValue else { return }
                    self.lock.withLock { self.port = port }
                    self.listener.stateUpdateHandler = nil
                    continuation.resume()
                case let .failed(error):
                    self?.listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                self.lock.withLock { self.connections.append(connection) }
                connection.start(queue: self.queue)
                self.read(connection, accumulated: Data())
            }
            listener.start(queue: queue)
        }
    }
    func stop() {
        listener.cancel()
        for connection in lock.withLock({ connections }) { connection.cancel() }
    }
    private static func chunkedBodyLength(_ data: Data) -> Int? {
        var offset = 0
        var total = 0
        while offset < data.count {
            guard let end = data.range(of: Data("\r\n".utf8), in: offset..<data.count),
                  let line = String(data: data[offset..<end.lowerBound], encoding: .utf8),
                  let count = Int(line.split(separator: ";")[0], radix: 16) else { return nil }
            offset = end.upperBound
            if count == 0 { return total }
            guard data.count - offset >= count + 2 else { return nil }
            total += count
            offset += count + 2
        }
        return nil
    }

    private func read(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self, error == nil else { connection.cancel(); return }
            var bytes = accumulated
            if let data { bytes.append(data) }
            guard let separator = bytes.range(of: Data("\r\n\r\n".utf8)),
                  let headers = String(data: bytes[..<separator.lowerBound], encoding: .utf8) else {
                if !complete { self.read(connection, accumulated: bytes) } else { connection.cancel() }
                return
            }
            let contentLength = headers.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespacesAndNewlines)) } ?? 0
            let available = Data(bytes[separator.upperBound...])
            let bodyLength: Int
            if headers.lowercased().contains("transfer-encoding: chunked") {
                guard let count = Self.chunkedBodyLength(available) else { self.read(connection, accumulated: bytes); return }
                bodyLength = count
            } else {
                guard available.count >= contentLength else { self.read(connection, accumulated: bytes); return }
                bodyLength = contentLength
            }
            let sink = headers.hasPrefix("GET /sink ") || headers.hasPrefix("POST /sink ")
            let requestLine = headers.components(separatedBy: "\r\n")[0].split(separator: " ")
            let route = requestLine.count > 1 ? String(requestLine[1]).components(separatedBy: "?")[0] : ""
            self.lock.withLock {
                self.requestCount += 1
                self.bodyCount += bodyLength
                if sink { self.sinkCount += 1 }
                if route.hasSuffix("/commands") { self.commandCount += 1; self.commandBodyCount += bodyLength }
                if route == "/v1/attachments" { self.uploadCount += 1; self.uploadBodyCount += bodyLength }
            }
            let redirect = self.redirectsToSelf ? self.url.appendingPathComponent("sink") : self.target
            let location = redirect.map { "Location: \($0.absoluteString)\r\n" } ?? ""
            let discovery = headers.hasPrefix("GET /.well-known/pi-gateway ") ? self.discoveryBody : nil
            let body = discovery ?? Data("{}".utf8)
            let response = "HTTP/1.1 \(discovery == nil ? self.status : 200) Fixture\r\n\(discovery == nil ? location : "")Content-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(response.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
