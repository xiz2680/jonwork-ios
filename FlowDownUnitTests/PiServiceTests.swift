@testable import FlowDown
import Foundation
import Testing

@Suite(.serialized)
struct PiServiceTests {
    @Test
    func `SSE parser accepts multiline data and CRLF framing`() throws {
        var parser = PiSSERecordParser(maximumEventBytes: 64, maximumBufferedEventBytes: 128)
        var event: PiSSERecord?
        for byte in "id: 7\r\nevent: session.released\r\ndata: {\"type\":\r\ndata: \"session.released\"}\r\n\r\n".utf8 {
            if let parsed = try parser.consume(byte) { event = parsed }
        }

        let record = try #require(event)
        #expect(record.id == "7")
        #expect(record.event == "session.released")
        #expect(String(data: record.data, encoding: .utf8) == "{\"type\":\n\"session.released\"}")
    }

    @Test
    func `SSE parser rejects an oversized event payload`() throws {
        var parser = PiSSERecordParser(maximumEventBytes: 4, maximumBufferedEventBytes: 64)
        #expect(throws: PiServiceError.eventTooLarge) {
            for byte in "data: 12345\n".utf8 { _ = try parser.consume(byte) }
        }
    }

    @Test
    func `SSE parser rejects cumulative buffered event overflow`() throws {
        var parser = PiSSERecordParser(maximumEventBytes: 4, maximumBufferedEventBytes: 8)
        #expect(throws: PiServiceError.eventBufferOverflow) {
            for byte in ":12345678".utf8 { _ = try parser.consume(byte) }
        }
    }

    @Test
    func `SSE parser resets buffered event budget after dispatch`() throws {
        var parser = PiSSERecordParser(maximumEventBytes: 8, maximumBufferedEventBytes: 32)
        var records: [PiSSERecord] = []
        for byte in "id: 1\nevent: one\ndata: a\n\nid: 2\nevent: two\ndata: b\n\n".utf8 {
            if let record = try parser.consume(byte) { records.append(record) }
        }

        #expect(records.map(\.id) == ["1", "2"])
        #expect(records.map(\.event) == ["one", "two"])
    }

    @Test
    func `request uses bearer authentication and expected repository endpoint`() async throws {
        let service = try makeService(token: "secret") { request in
            #expect(request.url?.path == "/v1/repositories")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
            return (200, #"{"items":[{"id":"/repo","displayName":"Repo"}]}"#)
        }

        #expect(try await service.listRepositories() == [
            PiGatewayWire.Repository(id: "/repo", displayName: "Repo"),
        ])
    }

    @Test
    func `delete session sends fenced idempotent request and requires deleted receipt`() async throws {
        let service = try makeService(token: "secret") { request in
            #expect(request.httpMethod == "DELETE")
            #expect(request.url?.path == "/v1/sessions/session-01")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
            #expect(request.value(forHTTPHeaderField: "Idempotency-Key") == "delete-key-01")
            #expect(request.value(forHTTPHeaderField: "If-Match") == "\"7\"")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try #require(try piServiceRequestBody(request))
            let payload = try JSONDecoder().decode([String: String].self, from: body)
            #expect(payload == ["clientId": "ios-01"])
            return (200, #"{"status":"applied","sessionId":"session-01","revision":8,"operationId":null,"afterEventId":"11","responseStatus":200,"deleted":true}"#)
        }

        let receipt = try await service.deleteSession(
            sessionID: "session-01",
            clientID: "ios-01",
            context: .init(idempotencyKey: "delete-key-01", revision: 7)
        )
        #expect(receipt.deleted == true)
        #expect(receipt.revision == 8)
    }

    @Test
    func `delete session fails closed when the dedicated receipt is incomplete`() async throws {
        let service = try makeService { _ in
            (200, #"{"status":"applied","sessionId":"session-01","revision":8,"operationId":null,"afterEventId":"11","responseStatus":200}"#)
        }

        await #expect(throws: PiServiceError.invalidResponse) {
            try await service.deleteSession(
                sessionID: "session-01",
                clientID: "ios-01",
                context: .init(idempotencyKey: "delete-key-01", revision: 7)
            )
        }
    }

    @Test
    func `delete session rejects a zero revision receipt`() async throws {
        let service = try makeService { _ in
            (200, #"{"status":"applied","sessionId":"session-01","revision":0,"operationId":null,"afterEventId":"11","responseStatus":200,"deleted":true}"#)
        }

        await #expect(throws: PiServiceError.invalidResponse) {
            try await service.deleteSession(
                sessionID: "session-01",
                clientID: "ios-01",
                context: .init(idempotencyKey: "delete-key-01", revision: 7)
            )
        }
    }

    @Test(arguments: [
        #"{"items":[],"total":0,"authoritative":false}"#,
        #"{"items":[],"total":-1,"authoritative":true}"#,
        #"{"items":[]}"#,
    ])
    func `session list rejects non-authoritative or malformed envelopes`(_ response: String) async throws {
        let service = try makeService { request in
            #expect(request.url?.path == "/v1/sessions")
            return (200, response)
        }

        await #expect(throws: Error.self) {
            try await service.listSessions(repositoryID: nil)
        }
    }

    @Test
    func `authentication response maps to actionable typed error`() async throws {
        let service = try makeService { _ in
            (401, #"{"error":"invalid token"}"#)
        }

        await #expect(throws: PiServiceError.authenticationRequired) {
            try await service.listRepositories()
        }
    }

    @Test
    func `missing session maps to actionable typed error`() async throws {
        let service = try makeService { _ in
            (404, #"{"error":"Session not running"}"#)
        }

        await #expect(throws: PiServiceError.sessionUnavailable) {
            try await service.state(sessionID: "missing")
        }
    }

    @Test
    func `transport timeout maps to typed connection error`() async throws {
        let service = try makeService { _ in
            throw URLError(.timedOut)
        }

        await #expect(throws: PiServiceError.timedOut) {
            try await service.listRepositories()
        }
    }

    @Test
    func `unknown HTTP failure exposes safe localized error and redacted diagnostic`() async throws {
        let service = try makeService { _ in
            (502, #"{"error":"upstream token=super-secret at https://private.example/path"}"#)
        }

        do {
            _ = try await service.listRepositories()
            Issue.record("Expected the request to fail")
        } catch let error as PiServiceError {
            #expect(error == .httpFailure(statusCode: 502))
            #expect(error.localizedDescription == String(localized: "Jonwork could not complete the request. Try again later."))
            #expect(error.redactedDiagnostic == "http_status_502")
            #expect(!error.localizedDescription.contains("super-secret"))
            #expect(!error.redactedDiagnostic.contains("private.example"))
        }
    }

    @Test
    func `unknown transport failure exposes safe localized error and numeric diagnostic`() async throws {
        let service = try makeService { _ in throw URLError(.secureConnectionFailed) }

        do {
            _ = try await service.listRepositories()
            Issue.record("Expected the request to fail")
        } catch let error as PiServiceError {
            #expect(error == .transportFailure(code: URLError.secureConnectionFailed.rawValue))
            #expect(error.localizedDescription == String(localized: "Jonwork could not connect. Check your network and try again."))
            #expect(error.redactedDiagnostic == "transport_code_\(URLError.secureConnectionFailed.rawValue)")
        }
    }

    @Test
    func `TLS trust failure is rejected as a typed transport error`() async throws {
        let service = try makeService { _ in throw URLError(.serverCertificateUntrusted) }

        await #expect(throws: PiServiceError.transportFailure(
            code: URLError.serverCertificateUntrusted.rawValue
        )) {
            try await service.listRepositories()
        }
    }

    private func makeService(
        token: String? = "test-access-token",
        handler: @escaping @Sendable (URLRequest) throws -> (Int, String)
    ) throws -> PiService {
        PiURLProtocolStub.handler = handler
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PiURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        return PiService(
            configuration: try PiServerConfiguration(
                baseURL: #require(URL(string: "https://pi.example.test")),
                token: token
            ),
            session: session
        )
    }
}

private func piServiceRequestBody(_ request: URLRequest) throws -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
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

private final class PiURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (Int, String))?

    override class func canInit(with _: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (statusCode, body) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
