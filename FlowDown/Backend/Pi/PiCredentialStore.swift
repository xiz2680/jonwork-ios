import Foundation
import Security

protocol PiCredentialStoring: Sendable {
    func saveToken(_ token: String, server: URL) throws
    func token(server: URL) throws -> String?
    func removeToken(server: URL) throws
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

    private func account(_ server: URL) -> String {
        server.absoluteString.lowercased()
    }
}

struct PiCredentialStoreError: LocalizedError, Equatable {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? String(localized: "Keychain access failed.")
    }
}
