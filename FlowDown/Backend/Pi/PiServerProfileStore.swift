import Foundation

struct PiServerProfile: Equatable, Sendable {
    let baseURL: URL
    let token: String?
}

struct PiServerProfileStore {
    private let baseURLKey = "Pi.Server.BaseURL"
    private let defaults: UserDefaults
    private let credentials: any PiCredentialStoring

    init(
        defaults: UserDefaults = .standard,
        credentials: any PiCredentialStoring = PiCredentialStore()
    ) {
        self.defaults = defaults
        self.credentials = credentials
    }

    func load() throws -> PiServerProfile? {
        guard let rawURL = defaults.string(forKey: baseURLKey),
              let baseURL = URL(string: rawURL)
        else { return nil }
        let oauthToken = try credentials.oauthTokens(server: baseURL)?.accessToken
        let token: String?
        if let oauthToken {
            token = oauthToken
        } else {
            token = try credentials.token(server: baseURL)
        }
        return .init(baseURL: baseURL, token: token)
    }

    func save(baseURL: URL, token: String?) throws {
        let previousURL = defaults.string(forKey: baseURLKey).flatMap(URL.init(string:))
        let normalizedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if normalizedToken.isEmpty, previousURL == baseURL {
            return
        }

        let originalTargetToken = try credentials.token(server: baseURL)
        var targetChanged = false
        do {
            if normalizedToken.isEmpty {
                try credentials.removeToken(server: baseURL)
            } else {
                try credentials.saveToken(normalizedToken, server: baseURL)
            }
            targetChanged = true
            if let previousURL, previousURL != baseURL {
                try credentials.removeToken(server: previousURL)
            }
        } catch {
            if targetChanged {
                if let originalTargetToken {
                    try? credentials.saveToken(originalTargetToken, server: baseURL)
                } else {
                    try? credentials.removeToken(server: baseURL)
                }
            }
            throw error
        }
        defaults.set(baseURL.absoluteString, forKey: baseURLKey)
    }

    func hasSavedToken() throws -> Bool {
        guard let rawURL = defaults.string(forKey: baseURLKey), let baseURL = URL(string: rawURL) else { return false }
        return try credentials.oauthTokens(server: baseURL) != nil || credentials.token(server: baseURL) != nil
    }

    func removeSavedToken() throws {
        guard let rawURL = defaults.string(forKey: baseURLKey), let baseURL = URL(string: rawURL) else { return }
        try credentials.removeOAuthTokens(server: baseURL)
    }

    func save(baseURL: URL, oauthTokens: PiOAuthTokens) throws {
        defaults.set(baseURL.absoluteString, forKey: baseURLKey)
        try credentials.saveOAuthTokens(oauthTokens, server: baseURL)
    }

    func oauthTokens(baseURL: URL) throws -> PiOAuthTokens? {
        try credentials.oauthTokens(server: baseURL)
    }
}
