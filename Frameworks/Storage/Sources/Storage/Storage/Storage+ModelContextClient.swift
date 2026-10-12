//
//  Storage+ModelContextClient.swift
//  Storage
//
//  Created by LiBr on 6/29/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    func modelContextServerList() -> [ModelContextServer] {
        (
            try? db.getObjects(
                fromTable: ModelContextServer.tableName,
                where: ModelContextServer.Properties.removed == false,
                orderBy: [
                    ModelContextServer.Properties.creation.order(.ascending),
                ],
            ),
        ) ?? []
    }

    typealias ModelContextServerMakeInitDataBlock = (ModelContextServer) -> Void
    func modelContextServerMake(_ block: ModelContextServerMakeInitDataBlock? = nil) -> ModelContextServer {
        let object = ModelContextServer()
        if let block {
            block(object)
        }

        object.creation = .now
        object.modified = object.creation

        try? runTransaction {
            try $0.insert([object], intoTable: ModelContextServer.tableName)
            try self.pendingUploadEnqueue(sources: [(object, .insert)], handle: $0)
        }
        return object
    }

    func modelContextServerPut(object: ModelContextServer) {
        modelContextServerPut(objects: [object])
    }

    func modelContextServerPut(objects: [ModelContextServer], skipSync: Bool = false) {
        guard !objects.isEmpty else {
            return
        }
        let modified = Date.now
//        objects.forEach { $0.markModified(modified) }

        try? runTransaction { [weak self] in
            guard let self else { return }

            let diff = try diffSyncable(objects: objects, handle: $0)
            guard !diff.isEmpty else {
                return
            }

            // 恢复修改时间
//            diff.insert.forEach { $0.markModified($0.creation) }

            try $0.insertOrReplace(diff.insertOrReplace(), intoTable: ModelContextServer.tableName)

            if !diff.deleted.isEmpty {
                let deletedIds = diff.deleted.map(\.objectId)
                let update = StatementUpdate().update(table: ModelContextServer.tableName)
                    .set(ModelContextServer.Properties.removed)
                    .to(true)
                    .set(ModelContextServer.Properties.modified)
                    .to(modified)
                    .where(ModelContextServer.Properties.objectId.in(deletedIds))

                try $0.exec(update)
            }

            if skipSync {
                return
            }

            var changes = diff.insert.map { ($0, UploadQueue.Changes.insert) }
                + diff.updated.map { ($0, UploadQueue.Changes.update) }
                + diff.deleted.map { ($0, UploadQueue.Changes.delete) }
            // 按 modified 升序
            changes.sort { $0.0.modified < $1.0.modified }

            try pendingUploadEnqueue(sources: changes, handle: $0)
        }
    }

    func modelContextServerWith(_ identifier: ModelContextServer.ID) -> ModelContextServer? {
        try? db.getObject(
            fromTable: ModelContextServer.tableName,
            where: ModelContextServer.Properties.objectId == identifier && ModelContextServer.Properties.removed == false,
        )
    }

    func modelContextServerEdit(identifier: ModelContextServer.ID, skipSync: Bool = false, _ block: @escaping (inout ModelContextServer) -> Void) {
        let read: ModelContextServer? = try? db.getObject(
            fromTable: ModelContextServer.tableName,
            where: ModelContextServer.Properties.objectId == identifier,
        )
        guard var object = read else { return }
        block(&object)
        modelContextServerPut(objects: [object], skipSync: skipSync)
    }

    func modelContextServerRemove(identifier: ModelContextServer.ID, handle: Handle? = nil) {
        let object: ModelContextServer? = if let handle {
            try? handle.getObject(fromTable: ModelContextServer.tableName, where: ModelContextServer.Properties.objectId == identifier)
        } else {
            try? db.getObject(fromTable: ModelContextServer.tableName, where: ModelContextServer.Properties.objectId == identifier)
        }

        guard let object else {
            return
        }

        object.markModified()

        let update = StatementUpdate().update(table: ModelContextServer.tableName)
            .set(ModelContextServer.Properties.removed)
            .to(true)
            .set(ModelContextServer.Properties.modified)
            .to(object.modified)
            .where(ModelContextServer.Properties.objectId == identifier)

        if let handle {
            try? handle.exec(update)
        } else {
            try? db.exec(update)
        }

        try? pendingUploadEnqueue(sources: [(object, .delete)], handle: handle)
    }
}
