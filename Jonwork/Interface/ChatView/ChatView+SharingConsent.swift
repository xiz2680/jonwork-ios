import Storage
import UIKit

extension ChatView {
    private func sharingScope(for conversationID: Conversation.ID) -> PiSharingConsent.Scope? {
        let coordinator = PiSessionCoordinator.shared
        guard let binding = coordinator.binding(for: conversationID),
              let state = coordinator.viewState(for: conversationID),
              let model = state.conversation.model
        else { return nil }
        return .init(
            workspaceURL: binding.baseURL,
            repository: binding.repository,
            connectionID: binding.clientID,
            provider: model.provider,
            modelID: model.id
        )
    }

    func hasPiSharingPermission(conversationID: Conversation.ID) -> Bool {
        guard let scope = sharingScope(for: conversationID) else { return false }
        return PiSharingConsent.shared.isAuthorized(scope)
    }

    func performPiSharingOperation(
        conversationID: Conversation.ID,
        operation: (PiSharingConsent.Fence) async throws -> Bool
    ) async rethrows -> Bool {
        guard let scope = sharingScope(for: conversationID) else { return false }
        return try await PiSharingConsent.shared.perform(
            scope,
            currentScope: { [weak self] in self?.sharingScope(for: conversationID) },
            requestPermission: { [weak self] in
                guard let self else { return false }
                return await self.requestPiSharingPermission(for: scope)
            },
            operation: operation
        )
    }

    private func requestPiSharingPermission(for scope: PiSharingConsent.Scope) async -> Bool {
        guard let presenter = parentViewController,
              presenter.viewIfLoaded?.window != nil,
              presenter.presentedViewController == nil
        else { return false }
        let disclosure = String(localized: "Your messages, conversation history, attachments, and tool results are sent to this workspace and its AI provider. These services may retain the data under their own policies. You can revoke permission in Settings. Cancel keeps your draft and sends nothing.")
        let workspace = scope.workspaceURL.host ?? scope.workspaceURL.absoluteString
        let recipient = [scope.provider, scope.modelID].joined(separator: "/")
        let message = [disclosure, "", workspace, scope.repository, recipient].joined(separator: "\n")
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let alert = UIAlertController(
                title: String(localized: "Share Conversation Data?"),
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
                continuation.resume(returning: false)
            })
            alert.addAction(UIAlertAction(title: String(localized: "Allow Sharing"), style: .default) { _ in
                continuation.resume(returning: true)
            })
            alert.preferredAction = alert.actions.first
            presenter.present(alert, animated: true)
        }
    }
}
