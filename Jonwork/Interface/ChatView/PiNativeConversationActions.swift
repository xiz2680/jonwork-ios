import Storage
import UIKit

/// Captured private presentations belong to one authentication lifetime.
@MainActor
struct PiPresentationAuthorization {
    private weak var coordinator: PiSessionCoordinator?
    private let conversationID: Conversation.ID?
    private let binding: PiSessionCoordinator.Binding?
    private let epoch: UInt64

    init(conversationID: Conversation.ID?, coordinator: PiSessionCoordinator? = nil) {
        let coordinator = coordinator ?? .shared
        self.coordinator = coordinator
        self.conversationID = conversationID
        binding = coordinator.binding(for: conversationID)
        epoch = coordinator.authenticationEpoch
    }

    var isCurrent: Bool {
        guard let coordinator, let binding else { return false }
        return coordinator.authenticationEpoch == epoch && coordinator.binding(for: conversationID) == binding
    }
}

extension PiSessionCoordinator {
    func nativeFlagsMenu(conversationID: Conversation.ID) -> UIMenu {
        let flags = nativeFlags(for: conversationID)
        let authorization = PiPresentationAuthorization(conversationID: conversationID, coordinator: self)
        return UIMenu(children: [
            UIAction(title: String(localized: flags.favorite ? "Remove Favorite" : "Favorite"), image: UIImage(systemName: flags.favorite ? "star.fill" : "star"), state: flags.favorite ? .on : .off) { [weak self] _ in
                guard let self, authorization.isCurrent else { return }
                var flags = self.nativeFlags(for: conversationID)
                flags.favorite.toggle()
                self.saveNativeFlags(flags, conversationID: conversationID)
            },
            UIAction(title: String(localized: flags.pinned ? "Unpin" : "Pin"), image: UIImage(systemName: flags.pinned ? "pin.fill" : "pin"), state: flags.pinned ? .on : .off) { [weak self] _ in
                guard let self, authorization.isCurrent else { return }
                var flags = self.nativeFlags(for: conversationID)
                flags.pinned.toggle()
                self.saveNativeFlags(flags, conversationID: conversationID)
            },
        ])
    }
}
