import AuthenticationServices
import CryptoKit
import Foundation

struct PiOAuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let refreshExpiresAt: Date?

    init(accessToken: String, refreshToken: String?, expiresAt: Date, refreshExpiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.refreshExpiresAt = refreshExpiresAt
    }

    var requiresRefresh: Bool { expiresAt <= Date().addingTimeInterval(60) }
    var canRefresh: Bool {
        return refreshToken != nil
            && (refreshExpiresAt == nil || refreshExpiresAt! > Date().addingTimeInterval(60))
    }
}

protocol PiOAuthAuthorizing: Sendable {
    @MainActor
    func authorize(discovery: PiGatewayWire.Discovery, baseURL: URL) async throws -> PiOAuthTokens
    func refresh(_ tokens: PiOAuthTokens, discovery: PiGatewayWire.Discovery) async throws -> PiOAuthTokens
    func revoke(_ tokens: PiOAuthTokens, discovery: PiGatewayWire.Discovery) async throws
}

actor PiCredentialProvider {
    private let baseURL: URL
    private let authorizer: any PiOAuthAuthorizing
    private let discovery: PiGatewayWire.Discovery
    private let profileStore: PiServerProfileStore
    private var tokens: PiOAuthTokens?
    private var generation: UInt64 = 0
    private var refreshTask: Task<PiOAuthTokens, Error>?
    private var isActive = true

    init(
        baseURL: URL,
        tokens: PiOAuthTokens,
        authorizer: any PiOAuthAuthorizing,
        discovery: PiGatewayWire.Discovery,
        profileStore: PiServerProfileStore
    ) {
        self.baseURL = baseURL
        self.tokens = tokens
        self.authorizer = authorizer
        self.discovery = discovery
        self.profileStore = profileStore
    }

    func accessToken() throws -> String {
        guard isActive, let tokens else { throw PiServiceError.authenticationRequired }
        return tokens.accessToken
    }

    func refresh(rejectedAccessToken: String) async throws -> String {
        guard isActive, let current = tokens else { throw PiServiceError.authenticationRequired }
        if current.accessToken != rejectedAccessToken { return current.accessToken }
        guard current.canRefresh else {
            failClosed()
            throw PiServiceError.authenticationRequired
        }

        let refreshGeneration = generation
        let task: Task<PiOAuthTokens, Error>
        if let refreshTask {
            task = refreshTask
        } else {
            task = Task { [authorizer, discovery] in
                try await authorizer.refresh(current, discovery: discovery)
            }
            refreshTask = task
        }

        do {
            let refreshed = try await task.value
            guard isActive, generation == refreshGeneration, !Task.isCancelled else {
                throw CancellationError()
            }
            if let tokens, tokens.accessToken != rejectedAccessToken {
                refreshTask = nil
                return tokens.accessToken
            }
            try profileStore.save(baseURL: baseURL, oauthTokens: refreshed)
            tokens = refreshed
            refreshTask = nil
            return refreshed.accessToken
        } catch is CancellationError {
            if generation == refreshGeneration { refreshTask = nil }
            throw CancellationError()
        } catch let error where PiAuthenticationRecoveryPolicy.requiresFreshSignIn(after: error)
            || error as? PiServiceError == .accessDenied
        {
            if generation == refreshGeneration {
                refreshTask = nil
                failClosed()
            }
            throw PiServiceError.authenticationRequired
        } catch {
            if generation == refreshGeneration { refreshTask = nil }
            throw error
        }
    }

    func invalidate() {
        generation &+= 1
        isActive = false
        tokens = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    private func failClosed() {
        generation &+= 1
        isActive = false
        tokens = nil
        refreshTask?.cancel()
        refreshTask = nil
        try? profileStore.removeOAuthTokens(baseURL: baseURL)
    }
}

extension PiOAuthAuthorizing {
    func revoke(_: PiOAuthTokens, discovery _: PiGatewayWire.Discovery) async throws {}
}

enum PiOAuthError: Error, LocalizedError, Equatable {
    case invalidAuthorizationResponse
    case invalidCredentials
    case stateMismatch
    case refreshUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizationResponse: String(localized: "Jonwork sign-in returned an invalid response.")
        case .invalidCredentials: String(localized: "The email or password is incorrect.")
        case .stateMismatch: String(localized: "Jonwork sign-in could not be verified.")
        case .refreshUnavailable: String(localized: "Your Jonwork sign-in expired. Sign in again to continue.")
        }
    }
}

struct PiNativeSignInCredentials: Equatable, Sendable {
    let email: String
    let password: String
}

enum PiInstallationIdentity {
    private static let key = "Pi.NativeInstallationID"

    static func current(defaults: UserDefaults = .standard) -> String {
        if let value = defaults.string(forKey: key),
           value.range(of: #"^[A-Za-z0-9._-]{8,128}$"#, options: .regularExpression) != nil
        {
            return value
        }
        let value = "ios-" + UUID().uuidString.lowercased()
        defaults.set(value, forKey: key)
        return value
    }
}

final class PiPasswordOAuthClient: PiOAuthAuthorizing, @unchecked Sendable {
    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
        let tokenType: String
        let refreshExpiresIn: Double
        let scope: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
            case refreshExpiresIn = "refresh_expires_in"
            case scope
        }
    }

    private let lock = NSLock()
    private var credentials: PiNativeSignInCredentials?
    private let installationID: String
    private let session: URLSession

    init(
        credentials: PiNativeSignInCredentials? = nil,
        installationID: String = PiInstallationIdentity.current(),
        session: URLSession = .shared
    ) {
        self.credentials = credentials
        self.installationID = installationID
        self.session = session
    }

    @MainActor
    func authorize(discovery: PiGatewayWire.Discovery, baseURL: URL) async throws -> PiOAuthTokens {
        try discovery.validate(baseURL: baseURL)
        let credentials = lock.withLock { () -> PiNativeSignInCredentials? in
            defer { self.credentials = nil }
            return self.credentials
        }
        guard let credentials else { throw PiOAuthError.refreshUnavailable }

        guard let credentialEndpoint = discovery.authentication.credentialEndpoint else {
            throw PiServiceError.unsupportedAuthentication
        }
        var request = URLRequest(url: credentialEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": credentials.email,
            "password": credentials.password,
            "installationId": installationID,
            "deviceName": "Jonwork iPhone",
        ])
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw PiService.mapTransportError(error)
        }
        guard let response = response as? HTTPURLResponse else {
            throw PiOAuthError.invalidAuthorizationResponse
        }
        if response.statusCode == 401 { throw PiOAuthError.invalidCredentials }
        if response.statusCode == 403 { throw PiServiceError.accessDenied }
        if response.statusCode == 404 || (500 ... 599).contains(response.statusCode) {
            throw PiServiceError.gatewayUnavailable
        }
        if response.statusCode == 426 {
            throw PiServiceError.unsupportedGatewayVersion("unknown")
        }
        guard (200 ..< 300).contains(response.statusCode),
              data.count <= 1_048_576,
              response.mimeType == "application/json" || response.mimeType?.hasSuffix("+json") == true
        else { throw PiOAuthError.invalidAuthorizationResponse }
        guard let value = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw PiOAuthError.invalidAuthorizationResponse
        }
        guard (32 ... 4_096).contains(value.accessToken.count),
              (32 ... 4_096).contains(value.refreshToken.count),
              value.tokenType == "Bearer",
              value.scope == "pi.gateway",
              value.expiresIn.isFinite,
              (60 ... 3_600).contains(value.expiresIn),
              value.refreshExpiresIn.isFinite,
              value.refreshExpiresIn >= 300
        else { throw PiOAuthError.invalidAuthorizationResponse }
        let now = Date()
        return .init(
            accessToken: value.accessToken,
            refreshToken: value.refreshToken,
            expiresAt: now.addingTimeInterval(value.expiresIn),
            refreshExpiresAt: now.addingTimeInterval(value.refreshExpiresIn)
        )
    }

    func refresh(_ tokens: PiOAuthTokens, discovery: PiGatewayWire.Discovery) async throws -> PiOAuthTokens {
        try await refreshClient().refresh(tokens, discovery: discovery)
    }

    func revoke(_ tokens: PiOAuthTokens, discovery: PiGatewayWire.Discovery) async throws {
        try await refreshClient().revoke(tokens, discovery: discovery)
    }

    private func refreshClient() -> PiOAuthClient {
        PiOAuthClient(anchor: { ASPresentationAnchor() }, session: session)
    }
}

final class PiOAuthClient: NSObject, PiOAuthAuthorizing, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    private struct TokenResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
        let tokenType: String
        let refreshExpiresIn: Double
        let scope: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
            case tokenType = "token_type"
            case refreshExpiresIn = "refresh_expires_in"
            case scope
        }
    }

    private let anchor: @MainActor () -> ASPresentationAnchor
    private let session: URLSession
    @MainActor private var webSession: ASWebAuthenticationSession?
    @MainActor private var webSessionID: UUID?
    @MainActor private var webContinuation: CheckedContinuation<URL, Error>?

    init(
        anchor: @escaping @MainActor () -> ASPresentationAnchor,
        session: URLSession = .shared
    ) {
        self.anchor = anchor
        self.session = session
    }

    @MainActor
    func authorize(discovery: PiGatewayWire.Discovery, baseURL: URL) async throws -> PiOAuthTokens {
        try discovery.validate(baseURL: baseURL)
        let authorization = try PiOAuthAuthorizationRequest(authentication: discovery.authentication)
        let callbackURL = try await startWebSession(url: authorization.url)
        try Task.checkCancellation()
        let code = try authorization.code(from: callbackURL)
        return try await exchange(
            endpoint: discovery.authentication.tokenEndpoint,
            parameters: [
                "grant_type": "authorization_code",
                "code": code,
                "client_id": discovery.authentication.clientId,
                "redirect_uri": PiOAuthAuthorizationRequest.redirectURI,
                "code_verifier": authorization.verifier,
            ]
        )
    }

    func refresh(_ tokens: PiOAuthTokens, discovery: PiGatewayWire.Discovery) async throws -> PiOAuthTokens {
        guard let refreshToken = tokens.refreshToken else { throw PiOAuthError.refreshUnavailable }
        return try await exchange(
            endpoint: discovery.authentication.tokenEndpoint,
            parameters: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": discovery.authentication.clientId,
            ]
        )
    }

    func revoke(_ tokens: PiOAuthTokens, discovery: PiGatewayWire.Discovery) async throws {
        if let refreshToken = tokens.refreshToken {
            try await revoke(
                refreshToken,
                hint: "refresh_token",
                discovery: discovery
            )
        }
        try await revoke(tokens.accessToken, hint: "access_token", discovery: discovery)
    }

    @MainActor
    private func startWebSession(url: URL) async throws -> URL {
        try Task.checkCancellation()
        guard webContinuation == nil else { throw PiOAuthError.invalidAuthorizationResponse }
        let identifier = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                webContinuation = continuation
                webSessionID = identifier
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "jonwork") { [weak self] url, error in
                    Task { @MainActor in
                        guard let self else { return }
                        if let authenticationError = error as? ASWebAuthenticationSessionError,
                           authenticationError.code == .canceledLogin {
                            self.finishWebSession(.failure(CancellationError()), identifier: identifier)
                        } else if let error {
                            self.finishWebSession(.failure(error), identifier: identifier)
                        } else if let url {
                            self.finishWebSession(.success(url), identifier: identifier)
                        } else {
                            self.finishWebSession(.failure(PiOAuthError.invalidAuthorizationResponse), identifier: identifier)
                        }
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                webSession = session
                if !session.start() {
                    finishWebSession(.failure(PiOAuthError.invalidAuthorizationResponse), identifier: identifier)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self, webSessionID == identifier else { return }
                webSession?.cancel()
                finishWebSession(.failure(CancellationError()), identifier: identifier)
            }
        }
    }

    @MainActor
    private func finishWebSession(_ result: Result<URL, Error>, identifier: UUID) {
        guard webSessionID == identifier, let continuation = webContinuation else { return }
        webSessionID = nil
        webContinuation = nil
        webSession = nil
        continuation.resume(with: result)
    }

    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor { anchor() }

    private func exchange(
        endpoint: URL,
        parameters: [String: String]
    ) async throws -> PiOAuthTokens {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = PiFormURLEncoder.encode(parameters)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw PiService.mapTransportError(error)
        }
        guard let response = response as? HTTPURLResponse else {
            throw PiOAuthError.invalidAuthorizationResponse
        }
        if response.statusCode == 400,
           let oauthError = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data),
           oauthError.error == "invalid_grant"
        {
            throw PiOAuthError.refreshUnavailable
        }
        if response.statusCode == 403 { throw PiServiceError.accessDenied }
        if response.statusCode == 404 || (500 ... 599).contains(response.statusCode) {
            throw PiServiceError.gatewayUnavailable
        }
        guard (200 ..< 300).contains(response.statusCode),
              data.count <= 1_048_576,
              response.mimeType == "application/json" || response.mimeType?.hasSuffix("+json") == true
        else { throw PiOAuthError.invalidAuthorizationResponse }
        guard let value = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw PiOAuthError.invalidAuthorizationResponse
        }
        guard (32 ... 4_096).contains(value.accessToken.count),
              (32 ... 4_096).contains(value.refreshToken.count),
              value.tokenType == "Bearer",
              value.scope == "pi.gateway",
              value.expiresIn.isFinite,
              (60 ... 3_600).contains(value.expiresIn),
              value.refreshExpiresIn.isFinite,
              value.refreshExpiresIn >= 300
        else {
            throw PiOAuthError.invalidAuthorizationResponse
        }
        let now = Date()
        return .init(
            accessToken: value.accessToken,
            refreshToken: value.refreshToken,
            expiresAt: now.addingTimeInterval(value.expiresIn),
            refreshExpiresAt: now.addingTimeInterval(value.refreshExpiresIn)
        )
    }

    private func revoke(
        _ token: String,
        hint: String,
        discovery: PiGatewayWire.Discovery
    ) async throws {
        var request = URLRequest(url: discovery.authentication.revocationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = PiFormURLEncoder.encode([
            "client_id": discovery.authentication.clientId,
            "token": token,
            "token_type_hint": hint,
        ])
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw PiService.mapTransportError(error)
        }
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode),
              data.count <= 1_048_576,
              response.mimeType == "application/json" || response.mimeType?.hasSuffix("+json") == true,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Bool],
              object == ["revoked": true]
        else { throw PiOAuthError.invalidAuthorizationResponse }
    }


}

struct PiOAuthAuthorizationRequest {
    static let redirectURI = "jonwork://oauth/pi"
    let verifier: String
    let state: String
    let url: URL

    init(authentication: PiGatewayWire.Authentication) throws {
        verifier = Self.base64URL(Data((0 ..< 32).map { _ in UInt8.random(in: .min ... .max) }))
        state = UUID().uuidString
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        var components = URLComponents(url: authentication.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: authentication.clientId),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: authentication.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        guard let url = components?.url else { throw PiOAuthError.invalidAuthorizationResponse }
        self.url = url
    }

    func code(from url: URL) throws -> String {
        guard let callback = URLComponents(url: url, resolvingAgainstBaseURL: false),
              callback.scheme == "jonwork", callback.host == "oauth", callback.path == "/pi",
              callback.user == nil, callback.password == nil, callback.port == nil, callback.fragment == nil,
              let items = callback.queryItems,
              items.filter({ $0.name == "state" }).count == 1,
              items.first(where: { $0.name == "state" })?.value == state,
              !items.contains(where: { $0.name == "error" }),
              items.filter({ $0.name == "code" }).count == 1,
              let code = items.first(where: { $0.name == "code" })?.value,
              !code.isEmpty, code.count <= 4096
        else { throw PiOAuthError.stateMismatch }
        return code
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

private struct OAuthErrorResponse: Decodable {
    let error: String
}

enum PiFormURLEncoder {
    static func encode(_ parameters: [String: String]) -> Data {
        let body = parameters
            .sorted { $0.key < $1.key }
            .map { "\(encodeComponent($0.key))=\(encodeComponent($0.value))" }
            .joined(separator: "&")
        return Data(body.utf8)
    }

    private static func encodeComponent(_ value: String) -> String {
        let hexadecimal = Array("0123456789ABCDEF".utf8)
        var encoded: [UInt8] = []
        encoded.reserveCapacity(value.utf8.count)
        for byte in value.utf8 {
            switch byte {
            case 0x41 ... 0x5A, 0x61 ... 0x7A, 0x30 ... 0x39, 0x2A, 0x2D, 0x2E, 0x5F:
                encoded.append(byte)
            case 0x20:
                encoded.append(0x2B)
            default:
                encoded.append(0x25)
                encoded.append(hexadecimal[Int(byte >> 4)])
                encoded.append(hexadecimal[Int(byte & 0x0F)])
            }
        }
        return String(decoding: encoded, as: UTF8.self)
    }
}
