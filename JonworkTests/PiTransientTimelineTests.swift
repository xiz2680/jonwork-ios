@testable import Jonwork
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct PiTransientTimelineTests {
    @Test
    @MainActor
    func `transient timeline messages remain in memory and are excluded from storage saves`() async throws {
        try await JonworkTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake { $0.update(\.title, to: "Pi transient timeline") }
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }

        let message = session.appendTransientMessage(role: .assistant) {
            $0.update(\.document, to: "Transient answer")
        }
        session.save()

        #expect(session.isTransientMessage(message.objectId))
        #expect(session.messages.contains { $0.objectId == message.objectId })
        #expect(!sdb.listMessages(within: conversation.id).contains { $0.objectId == message.objectId })

        session.discard(messageIdentifier: message.objectId)
        #expect(!session.messages.contains { $0.objectId == message.objectId })
    }

    @Test
    @MainActor
    func `deleting conversation removes Pi binding before storage`() async throws {
        try await JonworkTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake { $0.update(\.title, to: "Pi deletion") }
        ConversationManager.shared.scanAll()
        PiSessionCoordinator.shared.bind(
            conversationID: conversation.id,
            sessionID: "session",
            repository: "/repo",
            clientID: "client",
            baseURL: try #require(URL(string: "https://pi.example.test"))
        )

        ConversationManager.shared.deleteConversation(identifier: conversation.id)

        #expect(PiSessionCoordinator.shared.binding(for: conversation.id) == nil)
        #expect(sdb.conversationWith(identifier: conversation.id) == nil)
    }
}
