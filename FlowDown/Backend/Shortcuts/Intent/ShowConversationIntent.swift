//
//  ShowConversationIntent.swift
//  FlowDown
//
//  Created by qaq on 12/11/2025.
//

import AppIntents
import Foundation
import Storage

struct ShowConversationIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Show Conversation"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Switch to a conversation without sending any messages."),
            categoryName: LocalizedStringResource("Conversations"),
        )
    }

    static var openAppWhenRun: Bool {
        true
    }

    @Parameter(title: "Conversation")
    var conversation: ShortcutsEntities.ConversationEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$conversation)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let identifier = conversation.id

        await MainActor.run {
            guard sdb.conversationWith(identifier: identifier) != nil else {
                Logger.app.errorFile("conversation not found: \(identifier)")
                return
            }

            ChatSelection.shared.select(identifier, options: [.collapseSidebar, .focusEditor])
        }

        let message = String(
            localized: "Switched to conversation",
        )
        let dialog = IntentDialog(.init(stringLiteral: message))
        return .result(dialog: dialog)
    }
}
