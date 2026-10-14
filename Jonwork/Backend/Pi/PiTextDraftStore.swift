import Foundation

/// Draft text stays in memory for this authenticated app session. No transcript,
/// credentials, attachment bytes, or file references enter persistent storage.
/// The coordinator clears all drafts when authentication is revoked.
@MainActor
final class PiTextDraftStore {
    private struct Scope: Hashable {
        let workspace: URL
        let repository: String
        let session: String
        let connection: String

        init(_ binding: PiSessionCoordinator.Binding) {
            workspace = binding.baseURL
            repository = binding.repository
            session = binding.sessionID
            connection = binding.clientID
        }
    }

    private var drafts: [Scope: String] = [:]

    func text(binding: PiSessionCoordinator.Binding) -> String { drafts[Scope(binding)] ?? "" }

    func save(_ text: String, binding: PiSessionCoordinator.Binding) {
        if text.isEmpty { drafts.removeValue(forKey: Scope(binding)) }
        else { drafts[Scope(binding)] = text }
    }

    func remove(binding: PiSessionCoordinator.Binding) { drafts.removeValue(forKey: Scope(binding)) }
    func removeAll() { drafts.removeAll() }
}
