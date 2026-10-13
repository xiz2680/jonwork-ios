import CryptoKit
import Foundation

/// Permission is scoped to a connection, workspace, and selected AI recipient.
/// Only opaque digests are persisted; prompts, tokens, and attachment data are never stored here.
@MainActor
final class PiSharingConsent {
    struct Scope: Equatable, Sendable {
        let workspaceURL: URL
        let repository: String
        let connectionID: String
        let provider: String
        let modelID: String

        fileprivate var digest: String {
            let fields = [workspaceURL.absoluteString, repository, connectionID, provider, modelID]
            let data = try! JSONEncoder().encode(fields)
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        }
    }

    struct Fence: Sendable {
        let scope: Scope
        fileprivate weak var owner: PiSharingConsent?
        fileprivate let generation: UInt64

        @MainActor
        func isValid(for currentScope: Scope?) -> Bool {
            guard let owner else { return false }
            return !Task.isCancelled && currentScope == scope
                && owner.generation == generation && owner.isAuthorized(scope)
        }
    }

    static let shared = PiSharingConsent()
    private let defaults: UserDefaults
    private let key = "Jonwork.AISharingConsent.v1"
    private var generation: UInt64 = 0

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func isAuthorized(_ scope: Scope) -> Bool {
        (defaults.stringArray(forKey: key) ?? []).contains(scope.digest)
    }

    func revokeAll() {
        generation &+= 1
        defaults.removeObject(forKey: key)
    }

    func fence(for scope: Scope) -> Fence? {
        guard isAuthorized(scope) else { return nil }
        return .init(scope: scope, owner: self, generation: generation)
    }

    /// The upload/send closure cannot start before permission and recipient validation.
    func perform(
        _ scope: Scope,
        currentScope: () -> Scope?,
        requestPermission: () async -> Bool,
        operation: (Fence) async throws -> Bool
    ) async rethrows -> Bool {
        guard await authorize(scope, currentScope: currentScope, requestPermission: requestPermission),
              let fence = fence(for: scope), fence.isValid(for: currentScope())
        else { return false }
        return try await operation(fence)
    }

    /// Cancellation, recipient changes, and revocation during the dialog all fail closed.
    func authorize(
        _ scope: Scope,
        currentScope: () -> Scope?,
        requestPermission: () async -> Bool
    ) async -> Bool {
        let requestedGeneration = generation
        guard currentScope() == scope, !Task.isCancelled else { return false }
        if isAuthorized(scope) { return true }
        guard await requestPermission(), !Task.isCancelled,
              generation == requestedGeneration, currentScope() == scope
        else { return false }
        var grants = Set(defaults.stringArray(forKey: key) ?? [])
        grants.insert(scope.digest)
        defaults.set(grants.sorted(), forKey: key)
        return true
    }
}
