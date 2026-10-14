import AuthenticationServices
import CryptoKit
import Foundation

struct HomeDiscovery: Decodable, Equatable, Sendable {
    struct Authentication: Decodable, Equatable, Sendable {
        let type: String
        let clientId: String
        let scopes: [String]
        let pkceMethods: [String]
        let authorizationEndpoint: URL
        let tokenEndpoint: URL
        let revocationEndpoint: URL
        let refreshTokenRotation: String
    }
    struct Capabilities: Decodable, Equatable, Sendable { let mutations: Bool }
    let contract: String
    let apiVersion: String
    let authentication: Authentication
    let handshakePath: String
    let capabilities: Capabilities

    func validate(baseURL: URL) throws {
        guard contract == HomeGateway.contract, apiVersion == "1.0", handshakePath == "/v1/home/handshake", !capabilities.mutations,
              authentication.type == "oauth2_authorization_code", !authentication.clientId.isEmpty,
              authentication.scopes == ["home.read"], authentication.pkceMethods == ["S256"], authentication.refreshTokenRotation == "required"
        else { throw PiServiceError.unsupportedAuthentication }
        for endpoint in [authentication.authorizationEndpoint, authentication.tokenEndpoint, authentication.revocationEndpoint] {
            guard endpoint.scheme?.lowercased() == "https", endpoint.scheme?.lowercased() == baseURL.scheme?.lowercased(),
                  endpoint.host?.lowercased() == baseURL.host?.lowercased(), (endpoint.port ?? 443) == (baseURL.port ?? 443),
                  endpoint.user == nil, endpoint.password == nil, endpoint.fragment == nil, endpoint.query == nil else { throw PiServiceError.unsupportedAuthentication }
        }
    }
}

struct HomeOAuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let refreshExpiresAt: Date
    let scope: String

    func validate() throws {
        guard scope == "home.read", (32...4096).contains(accessToken.count), (32...4096).contains(refreshToken.count) else { throw PiOAuthError.invalidAuthorizationResponse }
    }
}

struct HomeOAuthAuthorizationRequest {
    let verifier: String
    let state: String
    let url: URL

    init(authentication: HomeDiscovery.Authentication) throws {
        guard authentication.scopes == ["home.read"] else { throw PiServiceError.unsupportedAuthentication }
        func base64(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
        verifier = base64(Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
        state = UUID().uuidString
        var components = URLComponents(url: authentication.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "response_type", value: "code"), .init(name: "client_id", value: authentication.clientId),
            .init(name: "redirect_uri", value: PiOAuthAuthorizationRequest.redirectURI), .init(name: "scope", value: "home.read"),
            .init(name: "state", value: state), .init(name: "code_challenge", value: base64(Data(SHA256.hash(data: Data(verifier.utf8))))),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        guard let url = components?.url else { throw PiOAuthError.invalidAuthorizationResponse }
        self.url = url
    }

    func code(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.scheme == "jonwork", components.host == "oauth", components.path == "/pi",
              components.user == nil, components.password == nil, components.port == nil, components.fragment == nil,
              let items = components.queryItems, items.filter({ $0.name == "state" }).count == 1, items.first(where: { $0.name == "state" })?.value == state,
              !items.contains(where: { $0.name == "error" }), items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty, code.count <= 4096 else { throw PiOAuthError.stateMismatch }
        return code
    }
}

@MainActor
protocol HomeOAuthAuthorizing: AnyObject {
    func authorize(discovery: HomeDiscovery, origin: URL) async throws -> HomeOAuthTokens
    func refresh(_ tokens: HomeOAuthTokens, discovery: HomeDiscovery, origin: URL) async throws -> HomeOAuthTokens
    func revoke(_ tokens: HomeOAuthTokens, discovery: HomeDiscovery, origin: URL) async throws
    func cancel()
}

@MainActor
final class HomeOAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding, HomeOAuthAuthorizing {
    private let anchor: () -> ASPresentationAnchor
    private let session: URLSession
    private var browser: ASWebAuthenticationSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var browserID: UUID?
    private var requests: [UUID: Task<(Data, URLResponse), Error>] = [:]

    init(anchor: @escaping () -> ASPresentationAnchor, session: URLSession) { self.anchor = anchor; self.session = session }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor() }

    func authorize(discovery: HomeDiscovery, origin: URL) async throws -> HomeOAuthTokens {
        try discovery.validate(baseURL: origin)
        let request = try HomeOAuthAuthorizationRequest(authentication: discovery.authentication)
        let identifier = UUID()
        let callback: URL = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled, self.continuation == nil else { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                browserID = identifier
                let browser = ASWebAuthenticationSession(url: request.url, callbackURLScheme: "jonwork") { [weak self] callback, error in
                    Task { @MainActor in
                        guard let self, self.browserID == identifier else { return }
                        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin { self.finish(.failure(CancellationError())) }
                        else if let error { self.finish(.failure(error)) }
                        else if let callback { self.finish(.success(callback)) }
                        else { self.finish(.failure(PiOAuthError.invalidAuthorizationResponse)) }
                    }
                }
                browser.presentationContextProvider = self
                browser.prefersEphemeralWebBrowserSession = false
                self.browser = browser
                if !browser.start() { finish(.failure(PiOAuthError.invalidAuthorizationResponse)) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, self.browserID == identifier else { return }
                self.browser?.cancel()
                self.finish(.failure(CancellationError()))
            }
        }
        try Task.checkCancellation()
        return try await exchange(discovery: discovery, origin: origin, parameters: ["grant_type": "authorization_code", "client_id": discovery.authentication.clientId, "code": request.code(from: callback), "redirect_uri": PiOAuthAuthorizationRequest.redirectURI, "code_verifier": request.verifier])
    }

    private func finish(_ result: Result<URL, Error>) {
        let value = continuation
        continuation = nil; browser = nil; browserID = nil
        value?.resume(with: result)
    }

    func cancel() {
        browser?.cancel()
        finish(.failure(CancellationError()))
        let oldRequests = Array(requests.values)
        requests.removeAll()
        oldRequests.forEach { $0.cancel() }
    }

    private func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let identifier = UUID()
        let session = self.session
        let operation = Task { try await session.data(for: request, delegate: PiOAuthRequestDelegate.shared) }
        requests[identifier] = operation
        defer { requests.removeValue(forKey: identifier) }
        let result = try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: { operation.cancel() }
        try Task.checkCancellation()
        return result
    }

    func refresh(_ tokens: HomeOAuthTokens, discovery: HomeDiscovery, origin: URL) async throws -> HomeOAuthTokens {
        try tokens.validate()
        return try await exchange(discovery: discovery, origin: origin, parameters: ["grant_type": "refresh_token", "client_id": discovery.authentication.clientId, "refresh_token": tokens.refreshToken])
    }

    func revoke(_ tokens: HomeOAuthTokens, discovery: HomeDiscovery, origin: URL) async throws {
        try discovery.validate(baseURL: origin)
        try tokens.validate()
        for (token, hint) in [(tokens.refreshToken, "refresh_token"), (tokens.accessToken, "access_token")] {
            var request = URLRequest(url: discovery.authentication.revocationEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = PiFormURLEncoder.encode(["client_id": discovery.authentication.clientId, "token": token, "token_type_hint": hint])
            let (data, response) = try await data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), data.count <= 1_048_576,
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Bool], object == ["revoked": true] else { throw PiOAuthError.invalidAuthorizationResponse }
        }
    }

    private func exchange(discovery: HomeDiscovery, origin: URL, parameters: [String: String]) async throws -> HomeOAuthTokens {
        try discovery.validate(baseURL: origin)
        var request = URLRequest(url: discovery.authentication.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = PiFormURLEncoder.encode(parameters)
        let (data, response) = try await data(for: request)
        if let response = response as? HTTPURLResponse {
            if response.statusCode == 400,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: String], object["error"] == "invalid_grant" { throw PiOAuthError.refreshUnavailable }
            if response.statusCode == 401 || response.statusCode == 403 { throw PiServiceError.authenticationRequired }
        }
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode), data.count <= 1_048_576,
              response.mimeType == "application/json" || response.mimeType?.hasSuffix("+json") == true else { throw PiOAuthError.invalidAuthorizationResponse }
        struct Response: Decodable {
            let access_token: String; let refresh_token: String; let token_type: String; let scope: String
            let expires_in: Double; let refresh_expires_in: Double
        }
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard result.scope == "home.read", result.token_type == "Bearer", result.expires_in.isFinite, (60...3600).contains(result.expires_in),
              result.refresh_expires_in.isFinite, result.refresh_expires_in >= 300 else { throw PiOAuthError.invalidAuthorizationResponse }
        let tokens = HomeOAuthTokens(accessToken: result.access_token, refreshToken: result.refresh_token, expiresAt: Date().addingTimeInterval(result.expires_in), refreshExpiresAt: Date().addingTimeInterval(result.refresh_expires_in), scope: result.scope)
        try tokens.validate()
        return tokens
    }
}
