// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation
import WCDBSwift

package final class ConversationV1: Identifiable, Codable, TableNamed, TableCodable {
    package static let tableName: String = "Conversation"

    package var id: Int64 = .init()
    package var title: String = ""
    package var creation: Date = .init()
    package var icon: Data = .init()
    package var isFavorite: Bool = false
    package var shouldAutoRename: Bool = true
    package var modelId: String? = nil

    package enum CodingKeys: String, CodingTableKey {
        package typealias Root = ConversationV1
        package static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true, isAutoIncrement: true, isUnique: true)
            BindColumnConstraint(title, isNotNull: true, defaultTo: "")
            BindColumnConstraint(creation, isNotNull: true, defaultTo: Date(timeIntervalSince1970: 0))
            BindColumnConstraint(icon, isNotNull: true, defaultTo: Data())
            BindColumnConstraint(isFavorite, isNotNull: true, defaultTo: false)
            BindColumnConstraint(shouldAutoRename, isNotNull: true, defaultTo: true)
            BindColumnConstraint(modelId, isNotNull: false, defaultTo: nil)
        }

        case id
        case title
        case creation
        case icon
        case isFavorite
        case shouldAutoRename
        case modelId
    }

    package var isAutoIncrement: Bool = false // 用于定义是否使用自增的方式插入
    package var lastInsertedRowID: Int64 = 0 // 用于获取自增插入后的主键值
}

extension ConversationV1: Equatable {
    package static func == (lhs: ConversationV1, rhs: ConversationV1) -> Bool {
        lhs.id == rhs.id &&
            lhs.title == rhs.title &&
            lhs.creation == rhs.creation &&
            lhs.icon == rhs.icon &&
            lhs.isFavorite == rhs.isFavorite &&
            lhs.shouldAutoRename == rhs.shouldAutoRename &&
            lhs.modelId == rhs.modelId
    }
}

extension ConversationV1: Hashable {
    package func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(title)
        hasher.combine(creation)
        hasher.combine(icon)
        hasher.combine(isFavorite)
        hasher.combine(shouldAutoRename)
        hasher.combine(modelId)
    }
}
