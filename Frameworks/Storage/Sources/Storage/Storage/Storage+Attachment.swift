//
//  Created by ktiays on 2025/2/24.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation
import WCDBSwift

public extension Storage {
    func attachment(for messageID: String) -> [Attachment] {
        (
            try? db.getObjects(
                fromTable: Attachment.tableName,
                where: Attachment.Properties.messageId == messageID && Attachment.Properties.removed == false,
                orderBy: [
                    Attachment.Properties.creation
                        .order(.ascending),
                ],
            ),
        ) ?? []
    }

    typealias AttachmentMakeInitDataBlock = (Attachment) -> Void
    func attachmentMake(with messageID: String, skipSave: Bool = false, block: AttachmentMakeInitDataBlock? = nil) -> Attachment {
        let attachment = Attachment(deviceId: Self.deviceId)
        attachment.messageId = messageID

        if let block {
            block(attachment)
        }

        attachment.creation = .now
        attachment.modified = attachment.creation

        if skipSave {
            return attachment
        }

        try? runTransaction {
            try $0.insert([attachment], intoTable: Attachment.tableName)
            try self.pendingUploadEnqueue(sources: [(attachment, .insert)], handle: $0)
        }
        return attachment
    }

    func attachmentsUpdate(_ attachments: [Attachment]) {
        guard !attachments.isEmpty else {
            return
        }

        let modified = Date.now
//        attachments.forEach { $0.markModified(modified) }

        try? runTransaction { [weak self] in
            guard let self else { return }

            let diff = try diffSyncable(objects: attachments, handle: $0)
            guard !diff.isEmpty else {
                return
            }

            // 恢复修改时间
            diff.insert.forEach { $0.markModified($0.creation) }

            try $0.insertOrReplace(diff.insertOrReplace(), intoTable: Attachment.tableName)

            if !diff.deleted.isEmpty {
                let deletedIds = diff.deleted.map(\.objectId)
                let update = StatementUpdate().update(table: Attachment.tableName)
                    .set(Attachment.Properties.removed)
                    .to(true)
                    .set(Attachment.Properties.modified)
                    .to(modified)
                    .where(Attachment.Properties.objectId.in(deletedIds))

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

    func attachmentsMarkDelete(messageId: Message.ID, handle: Handle? = nil) throws {
        guard !messageId.isEmpty else {
            return
        }

        try runTransaction(handle: handle) { [weak self] in
            guard let self else { return }

            let object: Attachment? = try $0.getObject(fromTable: Attachment.tableName, where: Attachment.Properties.messageId == messageId)

            guard let object else {
                return
            }

            object.removed = true
            object.markModified()

            let update = StatementUpdate().update(table: Attachment.tableName)
                .set(Attachment.Properties.removed)
                .to(true)
                .set(Attachment.Properties.modified)
                .to(object.modified)
                .where(Attachment.Properties.messageId == messageId)

            try $0.exec(update)

            try pendingUploadEnqueue(sources: [(object, .delete)], handle: $0)
        }
    }

    func attachmentsMarkDelete(messageIds: [Message.ID], skipSync: Bool = false, handle: Handle? = nil) throws {
        guard !messageIds.isEmpty else {
            return
        }

        try runTransaction(handle: handle) { [weak self] in
            guard let self else { return }

            let objects: [Attachment] = try $0.getObjects(
                fromTable: Attachment.tableName,
                where: Attachment.Properties.messageId.in(messageIds)
                    && Attachment.Properties.removed == false,
            )

            guard !objects.isEmpty else {
                return
            }

            let modified = Date.now

            for object in objects {
                object.removed = true
                object.markModified(modified)
            }

            let update = StatementUpdate().update(table: Attachment.tableName)
                .set(Attachment.Properties.removed)
                .to(true)
                .set(Attachment.Properties.modified)
                .to(modified)
                .where(Attachment.Properties.messageId.in(messageIds))

            try $0.exec(update)

            guard !skipSync else {
                return
            }

            try pendingUploadEnqueue(sources: objects.map { ($0, .delete) }, handle: $0)
        }
    }

    func attachmentsMarkDelete(skipSync: Bool = false, handle: Handle? = nil) throws {
        try runTransaction(handle: handle) { [weak self] in
            guard let self else { return }

            let objects: [Attachment] = try $0.getObjects(
                fromTable: Attachment.tableName,
                where: Attachment.Properties.removed == false,
            )

            guard !objects.isEmpty else {
                return
            }

            let modified = Date.now

            for object in objects {
                object.removed = true
                object.markModified(modified)
            }

            let update = StatementUpdate().update(table: Attachment.tableName)
                .set(Attachment.Properties.removed)
                .to(true)
                .set(Attachment.Properties.modified)
                .to(modified)
                .where(Attachment.Properties.removed == false)

            try $0.exec(update)

            guard !skipSync else {
                return
            }

            try pendingUploadEnqueue(sources: objects.map { ($0, .delete) }, handle: $0)
        }
    }
}
