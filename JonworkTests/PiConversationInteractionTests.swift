import Foundation
import Testing
import UIKit
@testable import Jonwork

struct PiConversationInteractionTests {
    @Test @MainActor
    func piMessageMenuContainsOnlyReadOnlyActions() {
        let view = MessageListView()
        let menu = MessageListView.piReadOnlyMenu(content: "remote answer", referenceView: UIView(), anchor: view)
        let titles = menu.children.compactMap { ($0 as? UIAction)?.title }
        #expect(titles == [String(localized: "Copy"), String(localized: "View Raw"), String(localized: "Share"), String(localized: "Read Aloud"), String(localized: "Copy as Image")])
        #expect(menu.children.count == 6)
        #expect(menu.children.allSatisfy { ($0 as? UIAction)?.attributes.contains(.destructive) != true })
    }

    @Test @MainActor
    func piToolDetailsUseActualGatewayDetailWithoutLegacyParameters() {
        let output = MessageListView.piToolDetailsText(title: "Tool completed", detail: "  {\"files\":[\"result.md\"]}  ")
        #expect(output == "Tool completed\n\n" + String(localized: "Result") + "\n\n{\"files\":[\"result.md\"]}")
        #expect(!output.contains(String(localized: "Unable to decode tool parameters.")))
        #expect(MessageListView.piToolDetailsText(title: "Tool running", detail: "   ") == "Tool running")
    }

    @Test @MainActor
    func draftsCannotCrossSessionWorkspaceRepositoryOrConnection() {
        let store = PiTextDraftStore()
        let binding = PiSessionCoordinator.Binding(sessionID: "session-a", repository: "repo-a", clientID: "login-a", baseURL: URL(string: "https://one.example")!)
        store.save("unsent text", binding: binding)
        #expect(store.text(binding: binding) == "unsent text")
        let others = [
            PiSessionCoordinator.Binding(sessionID: "session-b", repository: binding.repository, clientID: binding.clientID, baseURL: binding.baseURL),
            PiSessionCoordinator.Binding(sessionID: binding.sessionID, repository: "repo-b", clientID: binding.clientID, baseURL: binding.baseURL),
            PiSessionCoordinator.Binding(sessionID: binding.sessionID, repository: binding.repository, clientID: "login-b", baseURL: binding.baseURL),
            PiSessionCoordinator.Binding(sessionID: binding.sessionID, repository: binding.repository, clientID: binding.clientID, baseURL: URL(string: "https://two.example")!),
        ]
        for other in others { #expect(store.text(binding: other).isEmpty) }
        store.removeAll()
        #expect(store.text(binding: binding).isEmpty)
        store.save("new draft", binding: binding)
        store.save("", binding: binding)
        #expect(store.text(binding: binding).isEmpty)
    }
}
