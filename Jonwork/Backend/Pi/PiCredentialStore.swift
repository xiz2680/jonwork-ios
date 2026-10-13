import Foundation
import Security

protocol PiCredentialStoring: Sendable {
    func saveToken(_ token: String, server: URL) throws
    func token(server: URL) throws -> String?
    func removeToken(server: URL) throws
    func saveOAuthTokens(_ tokens: PiOAuthTokens, server: URL) throws
    func oauthTokens(server: URL) throws -> PiOAuthTokens?
    func removeOAuthTokens(server: URL) throws
}

extension PiCredentialStoring {
    func saveOAuthTokens(_ tokens: PiOAuthTokens, server: URL) throws {
        try saveToken(tokens.accessToken, server: server)
    }

    func oauthTokens(server: URL) throws -> PiOAuthTokens? {
        try token(server: server).map {
            .init(accessToken: $0, refreshToken: nil, expiresAt: .distantFuture)
        }
    }

    func removeOAuthTokens(server: URL) throws { try removeToken(server: server) }
}

struct PiCredentialStore: PiCredentialStoring, Sendable {
    private let service = "com.jonwork.ios.pi-server"

    func saveToken(_ token: String, server: URL) throws {
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account(server),
        ] as CFDictionary
        let updateStatus = SecItemUpdate(query, [
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: Data(token.utf8),
        ] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw PiCredentialStoreError(status: updateStatus) }

        let addStatus = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account(server),
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: Data(token.utf8),
        ] as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw PiCredentialStoreError(status: addStatus) }
    }

    func token(server: URL) throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account(server),
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw PiCredentialStoreError(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    func removeToken(server: URL) throws {
        let status = SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account(server),
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PiCredentialStoreError(status: status)
        }
    }

    func saveOAuthTokens(_ tokens: PiOAuthTokens, server: URL) throws {
        let prefix = account(server) + "#oauth"
        try save(JSONEncoder().encode(tokens), account: prefix + ".bundle")
        try? removeLegacyOAuthAccounts(prefix: prefix)
    }

    func oauthTokens(server: URL) throws -> PiOAuthTokens? {
        let prefix = account(server) + "#oauth"
        if let bundle = try data(account: prefix + ".bundle") {
            return try JSONDecoder().decode(PiOAuthTokens.self, from: bundle)
        }
        guard let accessData = try data(account: prefix + ".access"),
              let accessToken = String(data: accessData, encoding: .utf8),
              !accessToken.isEmpty,
              let expiryData = try data(account: prefix + ".expiry"),
              let expiryValue = String(data: expiryData, encoding: .utf8).flatMap(Double.init),
              expiryValue.isFinite
        else { return nil }
        let refreshToken = try data(account: prefix + ".refresh")
            .flatMap { String(data: $0, encoding: .utf8) }
        let refreshExpiresAt = try data(account: prefix + ".refresh-expiry")
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap(Double.init)
            .map(Date.init(timeIntervalSince1970:))
        return .init(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date(timeIntervalSince1970: expiryValue),
            refreshExpiresAt: refreshExpiresAt
        )
    }

    func removeOAuthTokens(server: URL) throws {
        let prefix = account(server) + "#oauth"
        try remove(account: prefix + ".bundle")
        try removeLegacyOAuthAccounts(prefix: prefix)
        try removeToken(server: server)
    }

    private func removeLegacyOAuthAccounts(prefix: String) throws {
        try remove(account: prefix + ".access")
        try remove(account: prefix + ".refresh")
        try remove(account: prefix + ".expiry")
        try remove(account: prefix + ".refresh-expiry")
    }

    private func save(_ data: Data, account: String) throws {
        let query = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account] as CFDictionary
        let status = SecItemUpdate(query, [kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly, kSecValueData: data] as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw PiCredentialStoreError(status: status) }
        let add = SecItemAdd([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly, kSecValueData: data,
        ] as CFDictionary, nil)
        guard add == errSecSuccess else { throw PiCredentialStoreError(status: add) }
    }

    private func data(account: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
            kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw PiCredentialStoreError(status: status) }
        return data
    }

    private func remove(account: String) throws {
        let status = SecItemDelete([
            kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account,
        ] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PiCredentialStoreError(status: status) }
    }

    private func account(_ server: URL) -> String {
        guard var components = URLComponents(url: server, resolvingAgainstBaseURL: false) else {
            return server.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if (components.scheme == "https" && components.port == 443)
            || (components.scheme == "http" && components.port == 80)
        {
            components.port = nil
        }
        return components.url?.absoluteString ?? server.absoluteString
    }
}

struct PiCredentialStoreError: LocalizedError, Equatable {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? String(localized: "Keychain access failed.")
    }
}
