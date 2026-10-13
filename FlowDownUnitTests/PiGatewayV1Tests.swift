@testable import FlowDown
import AuthenticationServices
import Foundation
import Testing

@Suite(.serialized)
struct PiGatewayV1Tests {
    @Test
    func `frozen discovery validates required production capabilities`() throws {
        let discovery = try decodeFixture(PiGatewayWire.Discovery.self, "discovery.json")
        try discovery.validate()
        #expect(discovery.majorVersion == 1)
        #expect(discovery.capabilities.attachments.images)
        #expect(!discovery.capabilities.attachments.files)
    }

    @Test
    func `discovery fails closed for unsupported major and missing capability`() throws {
        let data = try fixture("discovery.json")
        let original = try #require(String(data: data, encoding: .utf8))
        let unsupported = original.replacingOccurrences(of: #""apiVersion":"1.0""#, with: #""apiVersion":"2.0""#)
        let missing = original.replacingOccurrences(of: #""replay":true"#, with: #""replay":false"#)
        let insecureAuth = original.replacingOccurrences(
            of: "https://gateway.example.test/v1/auth/authorize",
            with: "http://gateway.example.test/v1/auth/authorize"
        )

        let unsupportedDiscovery = try JSONDecoder.piGateway.decode(PiGatewayWire.Discovery.self, from: Data(unsupported.utf8))
        #expect(throws: PiServiceError.unsupportedGatewayVersion("2.0")) { try unsupportedDiscovery.validate() }
        let missingDiscovery = try JSONDecoder.piGateway.decode(PiGatewayWire.Discovery.self, from: Data(missing.utf8))
        #expect(throws: PiServiceError.capabilityUnavailable(["replay"])) { try missingDiscovery.validate() }
        let insecureDiscovery = try JSONDecoder.piGateway.decode(PiGatewayWire.Discovery.self, from: Data(insecureAuth.utf8))
        #expect(throws: PiServiceError.unsupportedAuthentication) {
            try insecureDiscovery.validate(baseURL: URL(string: "https://gateway.example.test")!)
        }
    }

    @Test
    func `frozen snapshot and event fixture reduce through adapter into domain timeline`() throws {
        let snapshot = try decodeFixture(PiGatewayWire.Snapshot.self, "snapshot.json")
        let events = try decodeFixture([PiGatewayWire.Event].self, "events.json")
        var adapter = PiEventAdapter()
        var reducer = PiSessionReducer()
        reducer.reduce(try adapter.replace(with: snapshot, clientID: "ios-01"))
        for event in events {
            reducer.reduce(try adapter.adapt(event))
            reducer.observe(revision: adapter.revision, lastEventID: adapter.lastEventID?.string ?? snapshot.lastEventId)
        }

        #expect(adapter.lastEventID?.string == "24")
        #expect(reducer.state.revision == 9)
        #expect(!reducer.state.isStreaming)
        #expect(reducer.state.messages.contains { $0.id == "assistant-message-01" && $0.text == "Inspection complete." })
        #expect(reducer.state.messages.contains { $0.id == "tool-tool-01" && $0.tool?.state == .succeeded })
    }

    @Test(arguments: [
        (#"{"contract":"pi-gateway/1.0","id":"12","sessionId":"session-01","sessionRevision":7,"occurredAt":"2026-10-13T08:00:00.000Z","type":"controller.changed","data":{"previousControllerClientId":null,"controllerClientId":"ios-01","reason":"takeover"}}"#, PiAdapterError.duplicateEvent),
        (#"{"contract":"pi-gateway/1.0","id":"11","sessionId":"session-01","sessionRevision":7,"occurredAt":"2026-10-13T08:00:00.000Z","type":"controller.changed","data":{"previousControllerClientId":null,"controllerClientId":"ios-01","reason":"takeover"}}"#, PiAdapterError.outOfOrderEvent),
        (#"{"contract":"pi-gateway/1.0","id":"14","sessionId":"session-01","sessionRevision":7,"occurredAt":"2026-10-13T08:00:00.000Z","type":"controller.changed","data":{"previousControllerClientId":null,"controllerClientId":"ios-01","reason":"takeover"}}"#, PiAdapterError.eventGap),
    ])
    func `invalid cursor sequences require snapshot recovery`(_ json: String, _ expected: PiAdapterError) throws {
        let snapshot = try decodeFixture(PiGatewayWire.Snapshot.self, "snapshot.json")
        let event = try JSONDecoder.piGateway.decode(PiGatewayWire.Event.self, from: Data(json.utf8))
        var adapter = PiEventAdapter()
        _ = try adapter.replace(with: snapshot, clientID: "ios-01")
        #expect(throws: expected) { try adapter.adapt(event) }
        #expect(expected.requiresSnapshotRecovery)
    }

    @Test
    func `SSE parser requires matching id event and data record fields`() throws {
        var parser = PiSSERecordParser(maximumEventBytes: 1024, maximumBufferedEventBytes: 2048)
        var record: PiSSERecord?
        let value = "id: 13\nevent: operation.accepted\ndata: {\"contract\":\"pi-gateway/1.0\"}\n\n"
        for byte in value.utf8 {
            if let parsed = try parser.consume(byte) { record = parsed }
        }
        #expect(record?.id == "13")
        #expect(record?.event == "operation.accepted")
    }

    @Test
    func `mutation sends idempotency revision and v1 command body`() async throws {
        PiGatewayURLProtocol.handler = { request in
            #expect(request.url?.path == "/v1/sessions/session-01/commands")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "request-1234")
            #expect(request.value(forHTTPHeaderField: "If-Match") == #""7""#)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
            let body = try requestBody(request)
            let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(json["type"] as? String == "prompt")
            #expect(json["attachmentIds"] as? [String] == ["attachment-01"])
            return (202, #"{"status":"applied","sessionId":"session-01","revision":8,"operationId":"operation-01","afterEventId":"13","responseStatus":202}"#)
        }
        let service = try makeService()
        let receipt = try await service.mutate(
            .send(text: "Inspect", attachmentIDs: ["attachment-01"], delivery: .prompt),
            sessionID: "session-01",
            clientID: "ios-01",
            context: .init(idempotencyKey: "request-1234", revision: 7)
        )
        #expect(receipt.revision == 8)
        #expect(receipt.afterEventId == "13")
    }

    @Test
    func `mutation receipt lookup sends canonical identity headers`() async throws {
        PiGatewayURLProtocol.handler = { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/v1/sessions/session-01/mutation-receipt")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "request-1234")
            #expect(request.value(forHTTPHeaderField: "X-Client-Id") == "ios-01")
            return (200, #"{"status":"applied","sessionId":"session-01","revision":8,"operationId":"operation-01","afterEventId":"13","responseStatus":202}"#)
        }

        let result = try await makeService().mutationReceipt(
            sessionID: "session-01",
            idempotencyKey: "request-1234",
            clientID: "ios-01"
        )

        #expect(result == .applied(.init(
            sessionId: "session-01", revision: 8, operationId: "operation-01", afterEventId: "13"
        )))
    }

    @Test
    func `mutation receipt not found maps the frozen structured error`() async throws {
        PiGatewayURLProtocol.handler = { _ in
            (404, #"{"error":{"code":"mutation_not_found","message":"No retained mutation","requestId":"request-01","retryable":false}}"#)
        }

        await #expect(throws: PiServiceError.mutationNotFound) {
            _ = try await makeService().mutationReceipt(
                sessionID: "session-01",
                idempotencyKey: "request-1234",
                clientID: "ios-01"
            )
        }
    }

    @Test
    func `attachment upload uses exact digest normalized filename and discovery timeout`() async throws {
        let discoveryBody = try #require(String(data: fixture("discovery.json"), encoding: .utf8))
        let bytes = Data("exact bytes".utf8)
        PiGatewayURLProtocol.handler = { request in
            if request.url?.path == "/.well-known/pi-gateway" { return (200, discoveryBody) }
            #expect(request.url?.path == "/v1/attachments")
            #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == [
                URLQueryItem(name: "repositoryId", value: "/repo"),
            ])
            #expect(request.value(forHTTPHeaderField: "X-File-Name") == "caf%C3%A9.txt")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "upload-1234")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
            #expect(request.value(forHTTPHeaderField: "Content-Length") == String(bytes.count))
            #expect(request.value(forHTTPHeaderField: "Content-Digest") == "sha-256=:445YGq3ni2TMhvesnzVVynjC3Mp0eUKn8dmzJ1qDT3U=:")
            #expect(request.timeoutInterval == 30)
            let requestData = try requestBody(request)
            #expect(requestData == bytes)
            return (201, #"{"attachmentId":"attachment-01","fileName":"café.txt","mediaType":"application/octet-stream","byteLength":11,"sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","status":"ready","expiresAt":"2026-10-13T09:00:00.000Z"}"#)
        }
        let service = try makeService()
        _ = try await service.discover()
        let decomposed = "cafe\u{301}.txt"

        _ = try await service.uploadAttachment(
            data: bytes,
            fileName: decomposed,
            mediaType: "application/octet-stream",
            repositoryID: "/repo",
            idempotencyKey: "upload-1234"
        )
    }

    @Test(arguments: [".", "..", "folder/file", #"folder\\file"#, "bad\0name"])
    func `attachment upload rejects path-like filenames`(_ fileName: String) async throws {
        let discoveryBody = try #require(String(data: fixture("discovery.json"), encoding: .utf8))
        PiGatewayURLProtocol.handler = { request in
            if request.url?.path == "/.well-known/pi-gateway" { return (200, discoveryBody) }
            return (500, "{}")
        }
        let service = try makeService()
        _ = try await service.discover()

        await #expect(throws: PiServiceError.invalidResponse) {
            _ = try await service.uploadAttachment(
                data: Data([1]),
                fileName: fileName,
                mediaType: "application/octet-stream",
                repositoryID: "/repo",
                idempotencyKey: "upload-1234"
            )
        }
    }

    @Test
    func `response body rejects oversized declared content length before reading`() async throws {
        PiGatewayURLProtocol.responseHeaders = ["Content-Length": "1048577"]
        defer { PiGatewayURLProtocol.responseHeaders = [:] }
        PiGatewayURLProtocol.handler = { _ in
            (200, #"{"contract":"pi-gateway/1.0"}"#)
        }

        await #expect(throws: PiServiceError.invalidResponse) {
            _ = try await makeService().discover()
        }
    }

    @Test
    func `response body rejects chunked overflow at endpoint cap`() async throws {
        PiGatewayURLProtocol.responseHeaders = ["Transfer-Encoding": "chunked"]
        defer { PiGatewayURLProtocol.responseHeaders = [:] }
        let oversized = String(repeating: "x", count: 1_048_577)
        PiGatewayURLProtocol.handler = { _ in (200, oversized) }

        await #expect(throws: PiServiceError.invalidResponse) {
            _ = try await makeService().discover()
        }
    }

    @Test
    func `direct attachment upload enforces discovery maximum before transport`() async throws {
        let discoveryBody = try #require(String(data: fixture("discovery.json"), encoding: .utf8))
        PiGatewayURLProtocol.requests = []
        PiGatewayURLProtocol.handler = { request in
            if request.url?.path == "/.well-known/pi-gateway" { return (200, discoveryBody) }
            return (500, "{}")
        }
        let service = try makeService()
        let discovery = try await service.discover()
        let oversized = Data(count: discovery.limits.attachmentMaxBytes + 1)

        await #expect(throws: PiServiceError.invalidResponse) {
            _ = try await service.uploadAttachment(
                data: oversized,
                fileName: "large.bin",
                mediaType: "application/octet-stream",
                repositoryID: "/repo",
                idempotencyKey: "upload-1234"
            )
        }

        #expect(PiGatewayURLProtocol.requests.map(\.url?.path) == ["/.well-known/pi-gateway"])
    }

    @Test
    func `strict session path rejects slash rather than changing route`() async throws {
        let service = try makeService()
        await #expect(throws: PiServiceError.invalidServerURL) {
            _ = try await service.snapshot(sessionID: "session/escape")
        }
    }

    @Test
    @MainActor
    func `OAuth refresh rotates credentials and revoke uses frozen discovery endpoints`() async throws {
        let discovery = try decodeFixture(PiGatewayWire.Discovery.self, "discovery.json")
        let authorizationCodeParameters = [
            "grant_type": "authorization_code",
            "code": "code with+symbols",
            "client_id": "pi-ios",
            "redirect_uri": "jonwork://oauth/pi",
            "code_verifier": "ABCxyz09*-._~",
        ]
        let decodedAuthorizationCodeParameters = try formValues(
            PiFormURLEncoder.encode(authorizationCodeParameters)
        )
        #expect(decodedAuthorizationCodeParameters == authorizationCodeParameters)
        let authorizationBody = try #require(String(
            data: PiFormURLEncoder.encode(authorizationCodeParameters),
            encoding: .utf8
        ))
        #expect(authorizationBody.contains("code=code+with%2Bsymbols"))
        #expect(authorizationBody.contains("code_verifier=ABCxyz09*-._%7E"))
        #expect(authorizationBody.contains("client_id=pi-ios"))
        #expect(authorizationBody.contains("redirect_uri=jonwork%3A%2F%2Foauth%2Fpi"))
        #expect(!authorizationBody.contains("%5F"))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PiGatewayURLProtocol.self]
        PiGatewayURLProtocol.requests = []
        PiGatewayURLProtocol.handler = { request in
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
            if request.url?.path == "/v1/auth/token" {
                let body = try requestBody(request)
                #expect(String(data: body, encoding: .utf8) == [
                    "client_id=pi-ios",
                    "grant_type=refresh_token",
                    "refresh_token=\(String(repeating: "y", count: 32))",
                ].joined(separator: "&"))
                let values = try formValues(body)
                #expect(values == [
                    "client_id": "pi-ios",
                    "grant_type": "refresh_token",
                    "refresh_token": String(repeating: "y", count: 32),
                ])
                return (200, #"{"access_token":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","token_type":"Bearer","expires_in":900,"refresh_token":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","refresh_expires_in":86400,"scope":"pi.gateway"}"#)
            }
            #expect(request.url?.path == "/v1/auth/revoke")
            return (200, #"{"revoked":true}"#)
        }
        let client = PiOAuthClient(
            anchor: { ASPresentationAnchor() },
            session: URLSession(configuration: configuration)
        )
        let tokens = try await client.refresh(
            .init(
                accessToken: String(repeating: "x", count: 32),
                refreshToken: String(repeating: "y", count: 32),
                expiresAt: .distantPast,
                refreshExpiresAt: Date().addingTimeInterval(3_600)
            ),
            discovery: discovery
        )
        #expect(tokens.accessToken == String(repeating: "a", count: 32))
        #expect(tokens.refreshToken == String(repeating: "b", count: 32))
        try await client.revoke(tokens, discovery: discovery)
        let revocations = PiGatewayURLProtocol.requests
            .filter { $0.url?.path == "/v1/auth/revoke" }
        let encodedRevocations = try revocations.map { request in
            String(data: try requestBody(request), encoding: .utf8)
        }
        #expect(encodedRevocations == [
            "client_id=pi-ios&token=\(String(repeating: "b", count: 32))&token_type_hint=refresh_token",
            "client_id=pi-ios&token=\(String(repeating: "a", count: 32))&token_type_hint=access_token",
        ])
        let revocationValues = try revocations.map { try formValues(requestBody($0)) }
        #expect(revocationValues == [
            [
                "client_id": "pi-ios",
                "token": String(repeating: "b", count: 32),
                "token_type_hint": "refresh_token",
            ],
            [
                "client_id": "pi-ios",
                "token": String(repeating: "a", count: 32),
                "token_type_hint": "access_token",
            ],
        ])
    }

    @Test
    func `snapshot projects text reasoning multiple tools and attachment as stable entities`() throws {
        let snapshot = try decodeFixture(PiGatewayWire.Snapshot.self, "snapshot-mixed.json")
        var reducer = PiSessionReducer()
        reducer.reduce(.snapshot(snapshot, clientID: "ios-01"))

        #expect(reducer.state.messages.first(where: { $0.id == "assistant-mixed" })?.text == "Answer part one. Answer part two.")
        #expect(reducer.state.messages.first(where: { $0.id == "assistant-mixed" })?.reasoning == "First reason. Second reason.")
        #expect(reducer.state.messages.first(where: { $0.id == "tool-parent" })?.tool?.detail == "parent result")
        #expect(reducer.state.messages.first(where: { $0.id == "tool-second" })?.tool?.detail == "second result")
        #expect(reducer.state.messages.first(where: { $0.id == "attachment-attachment-01" })?.text == "diagram.png")
    }

    @Test(arguments: [-1.0, 1.5, 10_000_000_000_000_000_000.0])
    func `malformed tool update sequence requires snapshot recovery`(_ sequence: Double) throws {
        let snapshot = try decodeFixture(PiGatewayWire.Snapshot.self, "snapshot.json")
        let events = try decodeFixture([PiGatewayWire.Event].self, "events.json")
        var adapter = PiEventAdapter()
        _ = try adapter.replace(with: snapshot, clientID: "ios-01")
        for event in events.prefix(6) { _ = try adapter.adapt(event) }
        let original = try #require(String(data: try fixture("events.json"), encoding: .utf8))
        let malformed = original.replacingOccurrences(
            of: #""updateSequence":1"#,
            with: #""updateSequence":\#(sequence)"#
        )
        let update = try JSONDecoder.piGateway.decode([PiGatewayWire.Event].self, from: Data(malformed.utf8))[6]
        #expect(throws: PiAdapterError.invalidPayload("updateSequence")) { try adapter.adapt(update) }
        #expect(PiAdapterError.invalidPayload("updateSequence").requiresSnapshotRecovery)
    }

    @Test
    func `nested tool lifecycle preserves parent relationship`() throws {
        let snapshot = try decodeFixture(PiGatewayWire.Snapshot.self, "snapshot.json")
        let prefix = try decodeFixture([PiGatewayWire.Event].self, "events.json").prefix(5)
        let nestedJSON = #"""
        [
        {"contract":"pi-gateway/1.0","id":"18","sessionId":"session-01","sessionRevision":8,"occurredAt":"2026-10-13T08:00:00.050Z","type":"tool.started","data":{"operationId":"operation-01","turnId":"turn-01","messageId":"assistant-message-01","toolCallId":"parent","parentCallId":null,"toolName":"parent","arguments":{}}},
        {"contract":"pi-gateway/1.0","id":"19","sessionId":"session-01","sessionRevision":8,"occurredAt":"2026-10-13T08:00:00.060Z","type":"tool.started","data":{"operationId":"operation-01","turnId":"turn-01","messageId":"assistant-message-01","toolCallId":"child","parentCallId":"parent","toolName":"child","arguments":{}}},
        {"contract":"pi-gateway/1.0","id":"20","sessionId":"session-01","sessionRevision":8,"occurredAt":"2026-10-13T08:00:00.070Z","type":"tool.completed","data":{"operationId":"operation-01","turnId":"turn-01","messageId":"assistant-message-01","toolCallId":"child","parentCallId":"parent","status":"success","result":{},"error":null}},
        {"contract":"pi-gateway/1.0","id":"21","sessionId":"session-01","sessionRevision":8,"occurredAt":"2026-10-13T08:00:00.080Z","type":"tool.completed","data":{"operationId":"operation-01","turnId":"turn-01","messageId":"assistant-message-01","toolCallId":"parent","parentCallId":null,"status":"success","result":{},"error":null}}
        ]
        """#
        let nested = try JSONDecoder.piGateway.decode([PiGatewayWire.Event].self, from: Data(nestedJSON.utf8))
        var adapter = PiEventAdapter()
        var reducer = PiSessionReducer()
        reducer.reduce(try adapter.replace(with: snapshot, clientID: "ios-01"))
        for event in Array(prefix) + nested { reducer.reduce(try adapter.adapt(event)) }

        #expect(reducer.state.messages.first(where: { $0.id == "tool-child" })?.tool?.parentCallID == "parent")
        #expect(reducer.state.messages.first(where: { $0.id == "tool-parent" })?.tool?.state == .succeeded)
    }

    private func makeService() throws -> PiService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PiGatewayURLProtocol.self]
        return PiService(
            configuration: try .init(baseURL: #require(URL(string: "https://gateway.example.test")), token: "access-token"),
            session: URLSession(configuration: configuration)
        )
    }

    private func decodeFixture<Value: Decodable>(_ type: Value.Type, _ name: String) throws -> Value {
        try JSONDecoder.piGateway.decode(type, from: fixture(name))
    }

    private func fixture(_ name: String) throws -> Data {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/PiGatewayV1", isDirectory: true)
        return try Data(contentsOf: directory.appendingPathComponent(name))
    }
}

private func requestBody(_ request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    let stream = try #require(request.httpBodyStream)
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while true {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count >= 0 else { throw stream.streamError ?? PiServiceError.invalidResponse }
        if count == 0 { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return data
}

private func formValues(_ data: Data) throws -> [String: String] {
    let body = try #require(String(data: data, encoding: .utf8))
    return try Dictionary(uniqueKeysWithValues: body.split(separator: "&").map { pair in
        let components = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let key = try #require(components.first).replacingOccurrences(of: "+", with: " ")
        let value = components.count == 2
            ? String(components[1]).replacingOccurrences(of: "+", with: " ")
            : ""
        return (
            try #require(key.removingPercentEncoding),
            try #require(value.removingPercentEncoding)
        )
    })
}

private final class PiGatewayURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, String))?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var responseHeaders: [String: String] = [:]
    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            Self.requests.append(request)
            let result = try Self.handler?(request) ?? (500, #"{"error":{"code":"internal_error","message":"Missing test handler","requestId":"test","retryable":false}}"#)
            var headers = ["Content-Type": "application/json", "ETag": #""8""#]
            headers.merge(Self.responseHeaders) { _, override in override }
            let response = HTTPURLResponse(
                url: request.url!, statusCode: result.0, httpVersion: nil,
                headerFields: headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(result.1.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}
