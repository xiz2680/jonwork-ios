//
//  MessageV1.swift
//  Objects
//
//  Created by 秋星桥 on 1/23/25.
//

import Foundation
import MarkdownParser
import WCDBSwift

package final class MessageV1: Identifiable, Codable, TableNamed, TableCodable {
    package static let tableName: String = "Message"

    package var id: Int64 = .init()
    package var conversationId: ConversationV1.ID = .init()
    package var creation: Date = .init()
    package var role: Message.Role = .system
    package var thinkingDuration: TimeInterval = 0
    package var reasoningContent: String = ""
    package var isThinkingFold: Bool = false
    package var document: String = ""
    package var documentNodes: [MarkdownBlockNode] = []
    package var webSearchStatus: Message.WebSearchStatus = .init()
    package var toolStatus: Message.ToolStatus = .init()

    package enum CodingKeys: String, CodingTableKey {
        package typealias Root = MessageV1
        package static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true, isAutoIncrement: true, isUnique: true)
            BindColumnConstraint(conversationId, isNotNull: true)
            BindColumnConstraint(creation, isNotNull: true, defaultTo: Date(timeIntervalSince1970: 0))
            BindColumnConstraint(role, isNotNull: true, defaultTo: Message.Role.system.rawValue)
            BindColumnConstraint(thinkingDuration, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(reasoningContent, isNotNull: true, defaultTo: "")
            BindColumnConstraint(isThinkingFold, isNotNull: true, defaultTo: false)
            BindColumnConstraint(document, isNotNull: true, defaultTo: "")
            BindColumnConstraint(documentNodes, isNotNull: true, defaultTo: [MarkdownBlockNode]())
            BindColumnConstraint(webSearchStatus, isNotNull: true, defaultTo: Message.WebSearchStatus())
            BindColumnConstraint(toolStatus, isNotNull: true, defaultTo: Message.ToolStatus())

            BindForeginKey(
                conversationId,
                foreignKey: ForeignKey()
                    .references(with: ConversationV1.tableName)
                    .columns(ConversationV1.CodingKeys.id)
                    .onDelete(.cascade),
            )
        }

        case id
        case conversationId
        case creation
        case role
        case thinkingDuration
        case reasoningContent
        case isThinkingFold
        case document
        case documentNodes
        case webSearchStatus
        case toolStatus
    }

    package var isAutoIncrement: Bool = false // 用于定义是否使用自增的方式插入
    package var lastInsertedRowID: Int64 = 0 // 用于获取自增插入后的主键值
}

extension MessageV1: Equatable {
    package static func == (lhs: MessageV1, rhs: MessageV1) -> Bool {
        lhs.id == rhs.id &&
            lhs.conversationId == rhs.conversationId &&
            lhs.creation == rhs.creation &&
            lhs.role == rhs.role &&
            lhs.thinkingDuration == rhs.thinkingDuration &&
            lhs.reasoningContent == rhs.reasoningContent &&
            lhs.isThinkingFold == rhs.isThinkingFold &&
            lhs.document == rhs.document &&
            lhs.webSearchStatus == rhs.webSearchStatus
    }
}

extension MessageV1: Hashable {
    package func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(conversationId)
        hasher.combine(creation)
        hasher.combine(role)
        hasher.combine(thinkingDuration)
        hasher.combine(reasoningContent)
        hasher.combine(isThinkingFold)
        hasher.combine(document)
        hasher.combine(webSearchStatus)
    }
}
