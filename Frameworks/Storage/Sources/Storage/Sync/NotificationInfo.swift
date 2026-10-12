//
//  NotificationInfo.swift
//  Storage
//
//  Created by 秋星桥 on 2026/1/4.
//

import Foundation

public final class ConversationNotificationInfo: Sendable {
    public let modifications: [Conversation.ID]
    public let deletions: [Conversation.ID]
    public var isEmpty: Bool {
        modifications.isEmpty && deletions.isEmpty
    }

    public init(modifications: [Conversation.ID], deletions: [Conversation.ID]) {
        self.modifications = modifications
        self.deletions = deletions
    }
}

public final class CloudModelNotificationInfo: Sendable {
    public let modifications: [CloudModel.ID]
    public let deletions: [CloudModel.ID]
    public var isEmpty: Bool {
        modifications.isEmpty && deletions.isEmpty
    }

    public init(modifications: [CloudModel.ID], deletions: [CloudModel.ID]) {
        self.modifications = modifications
        self.deletions = deletions
    }
}

public final class ModelContextServerNotificationInfo: Sendable {
    public let modifications: [ModelContextServer.ID]
    public let deletions: [ModelContextServer.ID]
    public var isEmpty: Bool {
        modifications.isEmpty && deletions.isEmpty
    }

    public init(modifications: [ModelContextServer.ID], deletions: [ModelContextServer.ID]) {
        self.modifications = modifications
        self.deletions = deletions
    }
}

public final class MemoryNotificationInfo: Sendable {
    public let modifications: [Memory.ID]
    public let deletions: [Memory.ID]
    public var isEmpty: Bool {
        modifications.isEmpty && deletions.isEmpty
    }

    public init(modifications: [Memory.ID], deletions: [Memory.ID]) {
        self.modifications = modifications
        self.deletions = deletions
    }
}

public final class MessageNotificationInfo: Sendable {
    public let modifications: [Conversation.ID: [Message.ID]]
    public let deletions: [Conversation.ID: [Message.ID]]
    public var isEmpty: Bool {
        modifications.isEmpty && deletions.isEmpty
    }

    public init(modifications: [Conversation.ID: [Message.ID]], deletions: [Conversation.ID: [Message.ID]]) {
        self.modifications = modifications
        self.deletions = deletions
    }
}

public final class ChatTemplateNotificationInfo: Sendable {
    public let modifications: [ChatTemplateRecord.ID]
    public let deletions: [ChatTemplateRecord.ID]
    public var isEmpty: Bool {
        modifications.isEmpty && deletions.isEmpty
    }

    public init(modifications: [ChatTemplateRecord.ID], deletions: [ChatTemplateRecord.ID]) {
        self.modifications = modifications
        self.deletions = deletions
    }
}

public final class ConversationSummaryNotificationInfo: Sendable {
    public let modifications: [ConversationSummary.ID]
    public let deletions: [ConversationSummary.ID]
    public var isEmpty: Bool {
        modifications.isEmpty && deletions.isEmpty
    }

    public init(modifications: [ConversationSummary.ID], deletions: [ConversationSummary.ID]) {
        self.modifications = modifications
        self.deletions = deletions
    }
}
