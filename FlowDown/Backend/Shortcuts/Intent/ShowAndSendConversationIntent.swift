//
//  ShowAndSendConversationIntent.swift
//  FlowDown
//
//  Created by qaq on 12/11/2025.
//

import AppIntents
import Foundation
import Storage

struct ShowAndSendConversationIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Show and Send Conversation"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Switch to a conversation and automatically send the message."),
            categoryName: LocalizedStringResource("Conversations"),
        )
    }

    static var openAppWhenRun: Bool {
        true
    }

    @Parameter(title: "Conversation")
    var conversation: ShortcutsEntities.ConversationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$conversation) and send message")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let identifier = conversation.id

        await MainActor.run {
            guard sdb.conversationWith(identifier: identifier) != nil else {
                Logger.app.errorFile("conversation not found: \(identifier)")
                return
            }

            ChatSelection.shared.select(identifier, options: [.collapseSidebar, .focusEditor])

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("TriggerSendMessage"),
                    object: identifier,
                )
            }
        }

        let message = String(
            localized: "Switched to conversation and triggered send",
        )
        let dialog = IntentDialog(.init(stringLiteral: message))
        return .result(dialog: dialog)
    }
}
