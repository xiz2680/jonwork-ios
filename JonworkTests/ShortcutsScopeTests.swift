@testable import Jonwork
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ShortcutsScopeTests {
    @Test
    func `production shortcut surface exposes only branded open app action`() {
        #expect(Shortcuts.productionSurface == [.openApp])
    }

    @Test
    func `production shortcut policy fails before invoking legacy work`() {
        var invoked = false

        #expect(throws: ShortcutError.unavailable) {
            try ShortcutAvailability.performLegacyAction(enabled: false) {
                invoked = true
            }
        }
        #expect(!invoked)
    }

    @Test
    func `new conversation url encodes message content for shortcuts`() throws {
        let nilURL = try ShortcutUtilities.newConversationURL(initialMessage: nil)
        let encodedURL = try ShortcutUtilities.newConversationURL(initialMessage: "Hello/World?")

        #expect(nilURL.absoluteString == "jonwork://new/%20")
        #expect(encodedURL.absoluteString == "jonwork://new/Hello%2FWorld%3F")
    }

    @Test
    func `latest conversation transcript includes title user assistant and reasoning`() async throws {
        try await JonworkTestContext.shared.ensureBootstrappedEnvironment()

        let unique = UUID().uuidString
        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Unit \(unique)")
        }
        let userMessage = sdb.makeMessage(with: conversation.id) { message in
            message.update(\.role, to: .user)
            message.update(\.document, to: "Hello \(unique)")
        }
        let assistantMessage = sdb.makeMessage(with: conversation.id) { message in
            message.update(\.role, to: .assistant)
            message.update(\.document, to: "Reply \(unique)")
            message.update(\.reasoningContent, to: "Because \(unique)")
        }

        sdb.messagePut(messages: [userMessage, assistantMessage])

        let transcript = try ShortcutUtilities.latestConversationTranscript()

        #expect(transcript.contains("# Unit \(unique)"))
        #expect(transcript.contains("Hello \(unique)"))
        #expect(transcript.contains("Reply \(unique)"))
        #expect(transcript.contains("Because \(unique)"))
    }

    @Test
    func `shortcut related errors expose localized descriptions`() {
        let shortcutErrors: [ShortcutError] = [
            .unavailable,
            .emptyMessage,
            .modelUnavailable,
            .emptyResponse,
            .imageNotAllowed,
            .imageNotSupportedByModel,
            .invalidImage,
            .audioNotAllowed,
            .audioNotSupportedByModel,
            .invalidAudio,
            .invalidCandidates,
        ]
        let utilityErrors: [ShortcutUtilitiesError] = [
            .unableToCreateURL,
            .invalidMessageEncoding,
            .conversationNotFound,
            .conversationHasNoMessages,
        ]

        for error in shortcutErrors {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
        for error in utilityErrors {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }
}
