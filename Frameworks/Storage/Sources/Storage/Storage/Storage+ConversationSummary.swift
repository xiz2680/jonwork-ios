//
//  Storage+ConversationSummary.swift
//  Storage
//
//  Created by Alan Ye on 3/23/26.
//

import Foundation
import WCDBSwift

public extension Storage {
    func insertOrUpdateSummary(_ summary: ConversationSummary) throws {
        try runTransaction { [weak self] handle in
            guard let self else { return }

            let existingObject: ConversationSummary? = try handle.getObject(
                fromTable: ConversationSummary.tableName,
                where: ConversationSummary.Properties.objectId == summary.objectId,
            )

            try handle.insertOrReplace([summary], intoTable: ConversationSummary.tableName)

            let changes: UploadQueue.Changes = existingObject != nil ? .update : .insert
            try pendingUploadEnqueue(sources: [(summary, changes)], handle: handle)
        }
    }

    func getSummary(forConversation conversationId: String) throws -> ConversationSummary? {
        try db.getObject(
            fromTable: ConversationSummary.tableName,
            where: ConversationSummary.Properties.conversationId == conversationId
                && ConversationSummary.Properties.removed == false,
        )
    }

    func getRecentSummaries(limit: Int = 15) throws -> [ConversationSummary] {
        try db.getObjects(
            fromTable: ConversationSummary.tableName,
            where: ConversationSummary.Properties.removed == false,
            orderBy: [ConversationSummary.Properties.modified.order(.descending)],
            limit: limit,
        )
    }

    func deleteSummary(forConversation conversationId: String) throws {
        try runTransaction { [weak self] handle in
            guard let self else { return }

            let existingObject: ConversationSummary? = try handle.getObject(
                fromTable: ConversationSummary.tableName,
                where: ConversationSummary.Properties.conversationId == conversationId
                    && ConversationSummary.Properties.removed == false,
            )

            let modified = Date.now
            let update = StatementUpdate().update(table: ConversationSummary.tableName)
                .set(ConversationSummary.Properties.removed).to(true)
                .set(ConversationSummary.Properties.modified).to(modified)
                .where(ConversationSummary.Properties.conversationId == conversationId)
            try handle.exec(update)

            if let existingObject {
                existingObject.removed = true
                existingObject.markModified(modified)
                try pendingUploadEnqueue(sources: [(existingObject, .delete)], handle: handle)
            }
        }
    }
}
