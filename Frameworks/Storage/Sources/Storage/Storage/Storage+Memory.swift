//
//  Storage+Memory.swift
//  Storage
//
//  Created by Alan Ye on 8/14/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    enum MemoryError: Error, LocalizedError {
        case insertFailed(String)
        case retrieveFailed(String)
        case deleteFailed(String)
        case memoryNotFound(String)
        case databaseError(String)

        var localizedDescription: String {
            switch self {
            case let .insertFailed(message):
                "Failed to insert memory: \(message)"
            case let .retrieveFailed(message):
                "Failed to retrieve memories: \(message)"
            case let .deleteFailed(message):
                "Failed to delete memory: \(message)"
            case let .memoryNotFound(id):
                "Memory with ID \(id) not found"
            case let .databaseError(message):
                "Database error: \(message)"
            }
        }
    }

    func insertMemory(_ memory: Memory) throws {
        try insertMemory(memorys: [memory])
    }

    func insertMemory(memorys: [Memory]) throws {
        guard !memorys.isEmpty else {
            return
        }

        let modified = Date.now
//        memorys.forEach { $0.markModified(modified) }

        do {
            try runTransaction { [weak self] in
                guard let self else { return }

                let diff = try diffSyncable(objects: memorys, handle: $0)
                guard !diff.isEmpty else {
                    return
                }

                // 恢复修改时间
                diff.insert.forEach { $0.markModified($0.creation) }

                try $0.insertOrReplace(diff.insertOrReplace(), intoTable: Memory.tableName)

                if !diff.deleted.isEmpty {
                    let deletedIds = diff.deleted.map(\.objectId)
                    let update = StatementUpdate().update(table: Memory.tableName)
                        .set(Memory.Properties.removed)
                        .to(true)
                        .set(Memory.Properties.modified)
                        .to(modified)
                        .where(Memory.Properties.objectId.in(deletedIds))

                    try $0.exec(update)
                }

                var changes = diff.insert.map { ($0, UploadQueue.Changes.insert) }
                    + diff.updated.map { ($0, UploadQueue.Changes.update) }
                    + diff.deleted.map { ($0, UploadQueue.Changes.delete) }
                // 按 modified 升序
                changes.sort { $0.0.modified < $1.0.modified }

                try pendingUploadEnqueue(sources: changes, handle: $0)
            }
        } catch {
            throw MemoryError.insertFailed(error.localizedDescription)
        }
    }

    func getAllMemories() throws -> [Memory] {
        do {
            return try db.getObjects(
                fromTable: Memory.tableName,
                where: Memory.Properties.removed == false,
                orderBy: [
                    Memory.Properties.creation.order(.descending),
                ],
            )
        } catch {
            throw MemoryError.retrieveFailed(error.localizedDescription)
        }
    }

    func getMemoriesWithLimit(_ limit: Int) throws -> [Memory] {
        do {
            return try db.getObjects(
                fromTable: Memory.tableName,
                where: Memory.Properties.removed == false,
                orderBy: [
                    Memory.Properties.creation.order(.descending),
                ],
                limit: limit,
            )
        } catch {
            throw MemoryError.retrieveFailed(error.localizedDescription)
        }
    }

    func getMemory(id: String) throws -> Memory? {
        do {
            return try db.getObject(
                fromTable: Memory.tableName,
                where: Memory.Properties.objectId == id && Memory.Properties.removed == false,
            )
        } catch {
            throw MemoryError.retrieveFailed(error.localizedDescription)
        }
    }

    func searchMemories(query: String, limit: Int = 20) throws -> [Memory] {
        do {
            return try db.getObjects(
                fromTable: Memory.tableName,
                where: Memory.Properties.removed == false && Memory.Properties.content.like("%\(query)%"),
                orderBy: [
                    Memory.Properties.creation.order(.descending),
                ],
                limit: limit,
            )
        } catch {
            throw MemoryError.retrieveFailed(error.localizedDescription)
        }
    }

    func getMemoryCount() throws -> Int {
        do {
            let objects: [Memory] = try db.getObjects(fromTable: Memory.tableName, where: Memory.Properties.removed == false)
            return objects.count
        } catch {
            throw MemoryError.retrieveFailed(error.localizedDescription)
        }
    }

    func updateMemory(_ memory: Memory) throws {
        do {
            let existingMemory = try db.getObject(
                fromTable: Memory.tableName,
                where: Memory.Properties.objectId == memory.objectId,
            ) as Memory?

            guard existingMemory != nil else {
                throw MemoryError.memoryNotFound(memory.objectId)
            }

            try db.insertOrReplace([memory], intoTable: Memory.tableName)
            try pendingUploadEnqueue(sources: [(memory, .update)])

        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.insertFailed(error.localizedDescription)
        }
    }

    func deleteMemory(id: Memory.ID, handle: Handle? = nil) throws {
        do {
            let existingMemory: Memory? = if let handle {
                try handle.getObject(
                    fromTable: Memory.tableName,
                    where: Memory.Properties.objectId == id,
                )
            } else {
                try db.getObject(
                    fromTable: Memory.tableName,
                    where: Memory.Properties.objectId == id,
                )
            }

            guard let existingMemory else {
                throw MemoryError.memoryNotFound(id)
            }

            existingMemory.markModified()

            let update = StatementUpdate().update(table: Memory.tableName)
                .set(Memory.Properties.removed)
                .to(true)
                .set(Memory.Properties.modified)
                .to(existingMemory.modified)
                .where(Memory.Properties.objectId == id)

            if let handle {
                try handle.exec(update)
            } else {
                try db.exec(update)
            }

            try pendingUploadEnqueue(sources: [(existingMemory, .delete)], handle: handle)

        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.deleteFailed(error.localizedDescription)
        }
    }

    func deleteAllMemories(handle: Handle? = nil) throws {
        do {
            let memorys: [Memory] = if let handle {
                try handle.getObjects(fromTable: Memory.tableName, where: Memory.Properties.removed == false)
            } else {
                try db.getObjects(fromTable: Memory.tableName, where: Memory.Properties.removed == false)
            }

            guard !memorys.isEmpty else {
                return
            }

            let deletedIds = memorys.map(\.objectId)
            let modified = Date.now
            memorys.forEach { $0.markModified(modified) }

            let update = StatementUpdate().update(table: Memory.tableName)
                .set(Memory.Properties.removed)
                .to(true)
                .set(Memory.Properties.modified)
                .to(modified)
                .where(Memory.Properties.objectId.in(deletedIds))

            if let handle {
                try handle.exec(update)
            } else {
                try db.exec(update)
            }

            try pendingUploadEnqueue(sources: memorys.map { ($0, .delete) }, handle: handle)
        } catch {
            throw MemoryError.deleteFailed(error.localizedDescription)
        }
    }

    func deleteOldMemories(keepCount: Int) throws {
        do {
            let allMemories: [Memory] = try db.getObjects(fromTable: Memory.tableName, where: Memory.Properties.removed == false)

            let totalCount = allMemories.count
            guard totalCount > keepCount else { return }

            let memoriesToDelete: [Memory] = try db.getObjects(
                fromTable: Memory.tableName,
                where: Memory.Properties.removed == false,
                orderBy: [
                    Memory.Properties.creation.order(.ascending),
                ],
                limit: totalCount - keepCount,
            )

            guard !memoriesToDelete.isEmpty else {
                return
            }

            let deletedIds = memoriesToDelete.map(\.objectId)
            let modified = Date.now
            memoriesToDelete.forEach { $0.markModified(modified) }

            let update = StatementUpdate().update(table: Memory.tableName)
                .set(Memory.Properties.removed)
                .to(true)
                .set(Memory.Properties.modified)
                .to(modified)
                .where(Memory.Properties.objectId.in(deletedIds))

            try db.exec(update)

            try pendingUploadEnqueue(sources: memoriesToDelete.map { ($0, .delete) })

        } catch {
            throw MemoryError.deleteFailed(error.localizedDescription)
        }
    }
}
