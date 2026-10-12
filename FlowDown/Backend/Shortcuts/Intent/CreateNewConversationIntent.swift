//
//  CreateNewConversationIntent.swift
//  FlowDown
//
//  Created by qaq on 12/11/2025.
//

import AppIntents
import Foundation
import Storage

struct CreateNewConversationIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Create New Conversation"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Create a new conversation and optionally switch to it."),
            categoryName: LocalizedStringResource("Conversations"),
        )
    }

    @Parameter(title: "Switch to Conversation", default: false)
    var switchToConversation: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Create a new conversation") {
            \.$switchToConversation
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<ShortcutsEntities.ConversationEntity> {
        let conversation = await MainActor.run {
            ConversationManager.shared.createNewConversation(autoSelect: false)
        }

        if switchToConversation {
            ChatSelection.shared.select(conversation.id, options: [.collapseSidebar, .focusEditor])
        }

        Logger.app.infoFile("created new conversation via shortcut: \(conversation.id)")
        let entity = ShortcutsEntities.ConversationEntity(conversation: conversation)
        return .result(value: entity)
    }
}
