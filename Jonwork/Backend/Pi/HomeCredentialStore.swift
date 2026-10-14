import Foundation
import Security
import AuthenticationServices

@MainActor
protocol HomeCredentialStoring {
    func save(_ tokens: HomeOAuthTokens, origin: URL) throws
    func load(origin: URL) throws -> HomeOAuthTokens?
    func remove(origin: URL) throws
}

/// A separate Keychain namespace prevents Pi tokens from becoming Home authority.
struct HomeCredentialStore: HomeCredentialStoring {
    private let service = "com.jonwork.ios.home.read"

    private func query(origin: URL) -> [CFString: Any] {
        [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: Self.account(origin)]
    }

    private static func account(_ origin: URL) -> String {
        "\(origin.scheme?.lowercased() ?? "")://\(origin.host?.lowercased() ?? ""):\(origin.port ?? 443)#home.read"
    }

    func save(_ tokens: HomeOAuthTokens, origin: URL) throws {
        try tokens.validate()
        let data = try JSONEncoder().encode(tokens)
        let key = query(origin: origin)
        let status = SecItemUpdate(key as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw PiCredentialStoreError(status: status) }
        var addition = key
        addition[kSecValueData] = data
        addition[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(addition as CFDictionary, nil)
        guard added == errSecSuccess else { throw PiCredentialStoreError(status: added) }
    }

    func load(origin: URL) throws -> HomeOAuthTokens? {
        var key = query(origin: origin)
        key[kSecReturnData] = true
        key[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(key as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw PiCredentialStoreError(status: status) }
        let tokens = try JSONDecoder().decode(HomeOAuthTokens.self, from: data)
        try tokens.validate()
        return tokens
    }

    func remove(origin: URL) throws {
        let status = SecItemDelete(query(origin: origin) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PiCredentialStoreError(status: status) }
    }
}

@MainActor
final class HomeGatewayClient {
    var onIdentityInvalidated: (() -> Void)?
    let origin: URL
    private let session: URLSession
    private let credentials: any HomeCredentialStoring
    private let authorizerFactory: @MainActor (@escaping () -> ASPresentationAnchor, URLSession) -> any HomeOAuthAuthorizing
    private var tokens: HomeOAuthTokens?
    private var discovery: HomeDiscovery?
    private var identity: HomeGateway.Identity?
    private var generation: UInt64 = 0
    private let authority: HomeAuthenticationAuthority
    private var authorityEpoch: UInt64?
    private var activeAuthorizer: (any HomeOAuthAuthorizing)?
    private var requests: [UUID: Task<(Data, HTTPURLResponse), Error>] = [:]

    init(origin: URL, session: URLSession? = nil, authority: HomeAuthenticationAuthority? = nil, credentials: (any HomeCredentialStoring)? = nil, authorizerFactory: (@MainActor (@escaping () -> ASPresentationAnchor, URLSession) -> any HomeOAuthAuthorizing)? = nil) {
        self.credentials = credentials ?? HomeCredentialStore()
        self.authorizerFactory = authorizerFactory ?? { HomeOAuthClient(anchor: $0, session: $1) }
        self.origin = origin
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        self.session = session ?? URLSession(configuration: configuration)
        self.authority = authority ?? PiSessionCoordinator.shared.homeAuthenticationAuthority
        self.authority.register(self, origin: origin)
    }

    func invalidateLocalAuthority() {
        generation &+= 1
        tokens = nil; identity = nil
        activeAuthorizer?.cancel()
        activeAuthorizer = nil
        let oldRequests = Array(requests.values)
        requests.removeAll()
        oldRequests.forEach { $0.cancel() }
        onIdentityInvalidated?()
    }

    func discover() async throws -> HomeDiscovery {
        let value: HomeDiscovery = try await get(path: "/.well-known/jonwork-home", authenticated: false)
        try value.validate(baseURL: origin)
        discovery = value
        return value
    }

    func signIn(anchor: @escaping () -> ASPresentationAnchor) async throws -> HomeGateway.Handshake {
        invalidateLocalAuthority()
        authorityEpoch = authority.advance(origin: origin, excluding: self)
        let stamp = generation
        let discovery = try await discover()
        let authorizer = authorizerFactory(anchor, session)
        activeAuthorizer = authorizer
        defer { if generation == stamp { activeAuthorizer = nil } }
        var authorized = try credentials.load(origin: origin)
        if let saved = authorized, saved.expiresAt <= Date().addingTimeInterval(60) {
            if saved.refreshExpiresAt > Date() {
                do { authorized = try await authorizer.refresh(saved, discovery: discovery, origin: origin) }
                catch PiOAuthError.refreshUnavailable { authorized = nil }
                catch PiServiceError.authenticationRequired { authorized = nil }
            } else { authorized = nil }
        }
        if authorized == nil { authorized = try await authorizer.authorize(discovery: discovery, origin: origin) }
        guard isCurrent(stamp), let authorized else { throw CancellationError() }
        try authorized.validate()
        tokens = authorized
        let handshake: HomeGateway.Handshake
        do {
            handshake = try await get(path: discovery.handshakePath)
            try handshake.validateReadOnly()
        } catch {
            if isCurrent(stamp) {
                _ = authority.advance(origin: origin)
                try credentials.remove(origin: origin)
            }
            throw error
        }
        guard isCurrent(stamp) else { throw CancellationError() }
        identity = handshake.identity
        try credentials.save(authorized, origin: origin)
        return handshake
    }

    func history() async throws -> HomeGateway.History {
        let stamp = generation
        let expected = try requireIdentity()
        let value: HomeGateway.History = try await get(path: "/v1/home/sessions", query: [.init(name: "limit", value: "50"), .init(name: "offset", value: "0")])
        try validate(value.contract, identity: value.identity, expected: expected, generation: stamp)
        return value
    }

    func snapshot(sessionID: String) async throws -> HomeConversationProjection {
        let stamp = generation
        let expected = try requireIdentity()
        let value: HomeGateway.Snapshot = try await get(path: "/v1/home/sessions/\(try segment(sessionID))")
        try validate(value.contract, identity: value.identity, expected: expected, generation: stamp)
        return try HomeConversationProjection(snapshot: value, expectedIdentity: expected)
    }

    func replay(sessionID: String, turnID: String, afterSequence: Int) async throws -> HomeGateway.Replay {
        guard afterSequence >= 0 else { throw PiServiceError.invalidResponse }
        let stamp = generation
        let expected = try requireIdentity()
        let value: HomeGateway.Replay = try await get(path: "/v1/home/sessions/\(try segment(sessionID))/events", query: [.init(name: "turnId", value: turnID), .init(name: "afterSeq", value: String(afterSequence))])
        try validate(value.contract, identity: value.identity, expected: expected, generation: stamp)
        return value
    }

    func nativeFlags(sessionID: String) throws -> PiConversationPreferences.Flags {
        let identity = try requireIdentity()
        return authority.flags(identity: identity, origin: origin, sessionID: sessionID)
    }

    func saveNativeFlags(_ flags: PiConversationPreferences.Flags, sessionID: String) throws {
        let identity = try requireIdentity()
        authority.saveFlags(flags, identity: identity, origin: origin, sessionID: sessionID)
    }

    func hasSavedCredentials() throws -> Bool { try credentials.load(origin: origin) != nil }

    func signOut(anchor: @escaping () -> ASPresentationAnchor) async throws {
        try await prepareSignOut(anchor: anchor)()
    }

    func prepareSignOut(anchor: @escaping () -> ASPresentationAnchor) -> @MainActor () async throws -> Void {
        let saved = Result { try tokens ?? credentials.load(origin: origin) }
        _ = authority.advance(origin: origin)
        let removal = Result { try credentials.remove(origin: origin) }
        DisposableExporter.cancelAll()
        return { [self] in
            try removal.get()
            if let previous = try saved.get() {
                let discovered: HomeDiscovery
                if let discovery { discovered = discovery } else { discovered = try await discover() }
                try await authorizerFactory(anchor, session).revoke(previous, discovery: discovered, origin: origin)
            }
        }
    }

    private func requireIdentity() throws -> HomeGateway.Identity {
        guard isCurrent(generation), let identity, tokens?.scope == "home.read" else { throw PiServiceError.authenticationRequired }
        return identity
    }

    private func validate(_ contract: String, identity: HomeGateway.Identity, expected: HomeGateway.Identity, generation stamp: UInt64) throws {
        guard isCurrent(stamp) else { throw CancellationError() }
        guard contract == HomeGateway.contract, identity == expected else {
            _ = authority.advance(origin: origin)
            try credentials.remove(origin: origin)
            throw PiServiceError.authenticationRequired
        }
    }

    private func isCurrent(_ stamp: UInt64) -> Bool {
        guard generation == stamp, let authorityEpoch else { return false }
        return authority.isCurrent(authorityEpoch, origin: origin)
    }

    private func segment(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.count <= 512, value.range(of: #"^[A-Za-z0-9._-]+$"#, options: .regularExpression) != nil else { throw PiServiceError.invalidServerURL }
        return value
    }

    private func get<T: Decodable>(path: String, query: [URLQueryItem] = [], authenticated: Bool = true) async throws -> T {
        var components = URLComponents(url: origin.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw PiServiceError.invalidServerURL }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authenticated {
            guard let tokens, tokens.scope == "home.read" else { throw PiServiceError.authenticationRequired }
            request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        }
        let stamp = generation
        let identifier = UUID()
        let session = self.session
        let operation = Task<(Data, HTTPURLResponse), Error> {
            let (bytes, rawResponse) = try await session.bytes(for: request, delegate: PiOAuthRequestDelegate.shared)
            guard let response = rawResponse as? HTTPURLResponse else { throw PiServiceError.invalidResponse }
            var data = Data()
            for try await byte in bytes {
                guard data.count < 8 * 1024 * 1024 else { throw PiServiceError.invalidResponse }
                data.append(byte)
            }
            return (data, response)
        }
        requests[identifier] = operation
        defer { requests.removeValue(forKey: identifier) }
        let (data, response) = try await withTaskCancellationHandler {
            try await operation.value
        } onCancel: { operation.cancel() }
        guard generation == stamp, !authenticated || isCurrent(stamp) else { throw CancellationError() }
        try Task.checkCancellation()
        if [401, 403, 409].contains(response.statusCode) {
            if authenticated {
                _ = authority.advance(origin: origin)
                try credentials.remove(origin: origin)
            }
            throw PiServiceError.authenticationRequired
        }
        if response.statusCode == 404 || response.statusCode == 503 { throw PiServiceError.gatewayUnavailable }
        guard (200..<300).contains(response.statusCode), response.mimeType == "application/json" || response.mimeType?.hasSuffix("+json") == true else { throw PiServiceError.invalidResponse }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
