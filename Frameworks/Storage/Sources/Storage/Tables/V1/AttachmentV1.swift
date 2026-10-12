//
//  AttachmentV1.swift
//  Objects
//
//  Created by 秋星桥 on 1/23/25.
//

import Foundation
import WCDBSwift

package final class AttachmentV1: Identifiable, Codable, TableNamed, TableCodable {
    package static let tableName: String = "Attachment"
    package var id: Int64 = .init()
    package var messageId: MessageV1.ID = .init()
    package var data: Data = .init()
    package var previewImageData: Data = .init()
    package var imageRepresentation: Data = .init()
    package var representedDocument: String = ""
    package var type: String = ""
    package var name: String = ""
    package var storageSuffix: String = ""
    /// Records the UUID used when the object was created, for identification during modifications.
    package var objectIdentifier: String = .init()

    package enum CodingKeys: String, CodingTableKey {
        package typealias Root = AttachmentV1
        package static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true, isAutoIncrement: true, isUnique: true)
            BindColumnConstraint(messageId, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(data, isNotNull: true, defaultTo: Date(timeIntervalSince1970: 0))
            BindColumnConstraint(previewImageData, isNotNull: true, defaultTo: Data())
            BindColumnConstraint(representedDocument, isNotNull: true, defaultTo: "")
            BindColumnConstraint(type, isNotNull: true, defaultTo: "")
            BindColumnConstraint(name, isNotNull: true, defaultTo: "")
            BindColumnConstraint(storageSuffix, isNotNull: true, defaultTo: "")
            BindColumnConstraint(imageRepresentation, isNotNull: true, defaultTo: Data())
            BindColumnConstraint(objectIdentifier, isNotNull: true, defaultTo: "")

            BindForeginKey(
                messageId,
                foreignKey: ForeignKey()
                    .references(with: MessageV1.tableName)
                    .columns(MessageV1.CodingKeys.id)
                    .onDelete(.cascade),
            )
        }

        case id
        case messageId
        case data
        case previewImageData
        case imageRepresentation
        case representedDocument
        case type
        case name
        case storageSuffix
        case objectIdentifier
    }

    package var isAutoIncrement: Bool = false // 用于定义是否使用自增的方式插入
    package var lastInsertedRowID: Int64 = 0 // 用于获取自增插入后的主键值
}
