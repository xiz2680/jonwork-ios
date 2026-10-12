//
//  MemoryV1.swift
//  Storage
//
//  Created by Alan Ye on 8/14/25.
//

import Foundation
import WCDBSwift

package final class MemoryV1: Identifiable, Codable, TableNamed, TableCodable {
    package static let tableName: String = "Memory"

    package var id: String = UUID().uuidString
    package var content: String = ""
    package var timestamp: Date = .init()
    package var conversationId: String? = nil

    package enum CodingKeys: String, CodingTableKey {
        package typealias Root = MemoryV1
        package static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true, isUnique: true)
            BindColumnConstraint(content, isNotNull: true, defaultTo: "")
            BindColumnConstraint(timestamp, isNotNull: true, defaultTo: Date(timeIntervalSince1970: 0))
            BindColumnConstraint(conversationId, isNotNull: false, defaultTo: nil)
        }

        case id
        case content
        case timestamp
        case conversationId
    }

    package var isAutoIncrement: Bool = false
    package var lastInsertedRowID: Int64 = 0

    package init() {}

    package init(content: String, conversationId: String? = nil) {
        self.content = content
        self.conversationId = conversationId
        timestamp = Date()
    }
}

extension MemoryV1: Equatable {
    package static func == (lhs: MemoryV1, rhs: MemoryV1) -> Bool {
        lhs.id == rhs.id &&
            lhs.content == rhs.content &&
            lhs.timestamp == rhs.timestamp &&
            lhs.conversationId == rhs.conversationId
    }
}

extension MemoryV1: Hashable {
    package func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(content)
        hasher.combine(timestamp)
        hasher.combine(conversationId)
    }
}
