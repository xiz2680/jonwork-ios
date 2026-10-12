@testable import FlowDown
import Foundation
import Testing

@Suite(.serialized)
struct PiServiceTests {
    @Test
    func `request uses bearer authentication and expected repository endpoint`() async throws {
        let service = try makeService(token: "secret") { request in
            #expect(request.url?.path == "/api/repos")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
            return (200, #"{"repos":["/repo"]}"#)
        }

        #expect(try await service.listRepositories() == ["/repo"])
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
            #expect(error.localizedDescription == String(localized: "Pi could not complete the server request. Try again later."))
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
            #expect(error.localizedDescription == String(localized: "Pi could not complete the connection. Check the server and try again."))
            #expect(error.redactedDiagnostic == "transport_code_\(URLError.secureConnectionFailed.rawValue)")
        }
    }

    private func makeService(
        token: String? = nil,
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
