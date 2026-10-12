//
//  Storage+CloudModel.swift
//  Storage
//
//  Created by 秋星桥 on 1/28/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    func cloudModelList() -> [CloudModel] {
        (
            try? db.getObjects(
                fromTable: CloudModel.tableName,
                where: CloudModel.Properties.removed == false,
                orderBy: [
                    CloudModel.Properties.model_identifier
                        .order(.ascending),
                ],
            ),
        ) ?? []
    }

    func cloudModelPut(_ object: CloudModel) throws {
        try cloudModelPut(objects: [object])
    }

    func cloudModelPut(objects: [CloudModel]) throws {
        guard !objects.isEmpty else {
            return
        }

        let modified = Date.now
//        objects.forEach { $0.markModified(modified) }

        try runTransaction { [weak self] in
            guard let self else { return }

            let diff = try diffSyncable(objects: objects, handle: $0)
            guard !diff.isEmpty else {
                return
            }

            // 恢复修改时间
            diff.insert.forEach { $0.markModified($0.creation) }

            try $0.insertOrReplace(diff.insertOrReplace(), intoTable: CloudModel.tableName)

            if !diff.deleted.isEmpty {
                let deletedIds = diff.deleted.map(\.objectId)
                let update = StatementUpdate().update(table: CloudModel.tableName)
                    .set(CloudModel.Properties.removed)
                    .to(true)
                    .set(CloudModel.Properties.modified)
                    .to(modified)
                    .where(CloudModel.Properties.objectId.in(deletedIds))

                try $0.exec(update)
            }

            var changes = diff.insert.map { ($0, UploadQueue.Changes.insert) }
                + diff.updated.map { ($0, UploadQueue.Changes.update) }
                + diff.deleted.map { ($0, UploadQueue.Changes.delete) }
            // 按 modified 升序
            changes.sort { $0.0.modified < $1.0.modified }

            try pendingUploadEnqueue(sources: changes, handle: $0)
        }
    }

    func cloudModel(with identifier: CloudModel.ID) -> CloudModel? {
        try? db.getObject(
            fromTable: CloudModel.tableName,
            where: CloudModel.Properties.objectId == identifier && CloudModel.Properties.removed == false,
        )
    }

    func cloudModelEdit(identifier: CloudModel.ID, _ block: @escaping (inout CloudModel) -> Void) {
        let read: CloudModel? = try? db.getObject(
            fromTable: CloudModel.tableName,
            where: CloudModel.Properties.objectId == identifier,
        )
        guard var object = read else { return }
        block(&object)
        try? cloudModelPut(objects: [object])
    }

    func cloudModelRemove(identifier: CloudModel.ID, handle: Handle? = nil) {
        let object: CloudModel? = if let handle {
            try? handle.getObject(fromTable: CloudModel.tableName, where: CloudModel.Properties.objectId == identifier)
        } else {
            try? db.getObject(fromTable: CloudModel.tableName, where: CloudModel.Properties.objectId == identifier)
        }

        guard let object else { return }

        object.markModified()

        let update = StatementUpdate().update(table: CloudModel.tableName)
            .set(CloudModel.Properties.removed)
            .to(true)
            .set(CloudModel.Properties.modified)
            .to(object.modified)
            .where(CloudModel.Properties.objectId == identifier)

        if let handle {
            try? handle.exec(update)
        } else {
            try? db.exec(update)
        }

        try? pendingUploadEnqueue(sources: [(object, .delete)], handle: handle)
    }

    func cloudModelRemoveInvalid(handle: Handle? = nil) {
        if let handle {
            try? handle.delete(fromTable: CloudModel.tableName, where: CloudModel.Properties.objectId == "")
        } else {
            try? db.delete(fromTable: CloudModel.tableName, where: CloudModel.Properties.objectId == "")
        }
    }
}
