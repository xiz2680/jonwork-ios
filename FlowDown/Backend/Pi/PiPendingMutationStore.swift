import Foundation
import Security

struct PiPendingMutationRecord: Codable, Equatable, Sendable {
    let sessionID: String
    let clientID: String
    let action: PiConversationAction
    let context: PiMutationContext
    let requestDigest: String
    let receipt: PiGatewayWire.MutationReceipt?
    let createdAt: Date
    let expiresAt: Date

    init(
        sessionID: String,
        clientID: String,
        action: PiConversationAction,
        context: PiMutationContext,
        requestDigest: String,
        receipt: PiGatewayWire.MutationReceipt? = nil,
        createdAt: Date,
        expiresAt: Date
    ) {
        self.sessionID = sessionID
        self.clientID = clientID
        self.action = action
        self.context = context
        self.requestDigest = requestDigest
        self.receipt = receipt
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }
}

struct PiPendingCreationRecord: Codable, Equatable, Sendable {
    let baseURL: URL
    let repositoryID: String
    let resumeSessionID: String?
    let clientID: String
    let idempotencyKey: String
    let revision: Int?
    let requestDigest: String
    let createdAt: Date
    let expiresAt: Date
}

protocol PiPendingMutationStoring: Sendable {
    func load() throws -> [String: PiPendingMutationRecord]
    func save(_ records: [String: PiPendingMutationRecord]) throws
    func loadCreation() throws -> PiPendingCreationRecord?
    func saveCreation(_ record: PiPendingCreationRecord?) throws
}

struct PiPendingMutationStore: PiPendingMutationStoring, Sendable {
    private let service = "com.jonwork.ios.pi-pending-mutations"
    private let account = "records"
    private let creationAccount = "creation"

    func load() throws -> [String: PiPendingMutationRecord] {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess, let data = result as? Data else {
            throw PiCredentialStoreError(status: status)
        }
        return try JSONDecoder().decode([String: PiPendingMutationRecord].self, from: data)
    }

    func save(_ records: [String: PiPendingMutationRecord]) throws {
        let data = records.isEmpty ? nil : try JSONEncoder().encode(records)
        try save(data, account: account)
    }

    func loadCreation() throws -> PiPendingCreationRecord? {
        guard let data = try load(account: creationAccount) else { return nil }
        return try JSONDecoder().decode(PiPendingCreationRecord.self, from: data)
    }

    func saveCreation(_ record: PiPendingCreationRecord?) throws {
        let data = try record.map { try JSONEncoder().encode($0) }
        try save(data, account: creationAccount)
    }

    private func load(account: String) throws -> Data? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw PiCredentialStoreError(status: status)
        }
        return data
    }

    private func save(_ data: Data?, account: String) throws {
        guard let data else {
            let status = SecItemDelete([
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
            ] as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw PiCredentialStoreError(status: status)
            }
            return
        }
        let query = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary
        let attributes = [
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: data,
        ] as CFDictionary
        let update = SecItemUpdate(query, attributes)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw PiCredentialStoreError(status: update) }
        let add = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData: data,
        ] as CFDictionary, nil)
        guard add == errSecSuccess else { throw PiCredentialStoreError(status: add) }
    }
}
