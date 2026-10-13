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
        } catch {
            if generation == refreshGeneration {
                refreshTask = nil
                failClosed()
            }
            throw PiServiceError.authenticationRequired
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
    case stateMismatch
    case refreshUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidAuthorizationResponse: String(localized: "Jonwork sign-in returned an invalid response.")
        case .stateMismatch: String(localized: "Jonwork sign-in could not be verified.")
        case .refreshUnavailable: String(localized: "Your Jonwork sign-in expired. Sign in again to continue.")
        }
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
        let verifier = Self.base64URL(Data((0 ..< 32).map { _ in UInt8.random(in: .min ... .max) }))
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        let state = UUID().uuidString
        let redirectURI = "jonwork://oauth/pi"
        var components = URLComponents(url: discovery.authentication.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: discovery.authentication.clientId),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "scope", value: discovery.authentication.scopes.joined(separator: " ")),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        guard let authorizationURL = components?.url else { throw PiOAuthError.invalidAuthorizationResponse }
        let callbackURL = try await startWebSession(url: authorizationURL)
        guard let callback = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              callback.scheme == "jonwork",
              callback.host == "oauth",
              callback.path == "/pi",
              callback.queryItems?.first(where: { $0.name == "state" })?.value == state,
              let code = callback.queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty
        else { throw PiOAuthError.stateMismatch }
        return try await exchange(
            endpoint: discovery.authentication.tokenEndpoint,
            parameters: [
                "grant_type": "authorization_code",
                "code": code,
                "client_id": discovery.authentication.clientId,
                "redirect_uri": redirectURI,
                "code_verifier": verifier,
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
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "jonwork") { [weak self] url, error in
                    self?.webSession = nil
                    if let authenticationError = error as? ASWebAuthenticationSessionError,
                       authenticationError.code == .canceledLogin
                    {
                        continuation.resume(throwing: CancellationError())
                    } else if let error {
                        continuation.resume(throwing: error)
                    } else if let url {
                        continuation.resume(returning: url)
                    } else {
                        continuation.resume(throwing: PiOAuthError.invalidAuthorizationResponse)
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                webSession = session
                guard session.start() else {
                    webSession = nil
                    continuation.resume(throwing: PiOAuthError.invalidAuthorizationResponse)
                    return
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.webSession?.cancel() }
        }
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
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode),
              data.count <= 1_048_576,
              response.mimeType == "application/json" || response.mimeType?.hasSuffix("+json") == true
        else { throw PiOAuthError.invalidAuthorizationResponse }
        let value = try JSONDecoder().decode(TokenResponse.self, from: data)
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
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              (200 ..< 300).contains(response.statusCode),
              data.count <= 1_048_576,
              response.mimeType == "application/json" || response.mimeType?.hasSuffix("+json") == true,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Bool],
              object == ["revoked": true]
        else { throw PiOAuthError.invalidAuthorizationResponse }
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
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
