import Foundation
@testable import Storage
import Testing

struct ConversationStorageTests {
    @Test
    func `conversation create update duplicate remove and upload queue lifecycle`() throws {
        try StorageTestSupport.withTemporaryStorage { storage in
            let conversation = storage.conversationMake { conversation in
                conversation.update(\.title, to: "Original")
                conversation.update(\.shouldAutoRename, to: false)
            }

            #expect(storage.conversationList().map(\.id) == [conversation.id])
            #expect(storage.conversationListAllIdentifiers() == Set([conversation.id]))
            #expect(storage.pendingUploadList(tables: [Conversation.tableName]).count == 1)
            #expect(storage.pendingUploadList(tables: [Conversation.tableName]).first?.changes == .insert)

            conversation.update(\.title, to: "Updated")
            storage.conversationUpdate(object: conversation)

            #expect(storage.conversationWith(identifier: conversation.id)?.title == "Updated")
            #expect(storage.pendingUploadList(tables: [Conversation.tableName]).count == 1)
            #expect(storage.pendingUploadList(tables: [Conversation.tableName]).first?.changes == .update)

            let message = storage.makeMessage(with: conversation.id) { message in
                message.update(\.role, to: .user)
                message.update(\.document, to: "Hello")
            }
            let attachment = storage.attachmentMake(with: message.id) { attachment in
                attachment.update(\.name, to: "note.txt")
                attachment.update(\.type, to: "text/plain")
                attachment.update(\.representedDocument, to: "Attachment Body")
            }

            let duplicateID = try #require(
                storage.conversationDuplicate(identifier: conversation.id) { duplicate in
                    duplicate.update(\.title, to: "Copy")
                },
            )
            let duplicateConversation = try #require(storage.conversationWith(identifier: duplicateID))
            let duplicateMessages = storage.listMessages(within: duplicateID)
            let duplicateMessage = try #require(duplicateMessages.first)
            let duplicateAttachment = try #require(storage.attachment(for: duplicateMessage.id).first)

            #expect(duplicateConversation.title == "Copy")
            #expect(duplicateMessages.count == 1)
            #expect(duplicateMessage.id != message.id)
            #expect(duplicateAttachment.id != attachment.id)

            let conversationQueues = storage.pendingUploadList(tables: [Conversation.tableName])
            #expect(conversationQueues.count == 2)
            #expect(conversationQueues.contains { $0.objectId == conversation.id && $0.changes == .update })
            #expect(conversationQueues.contains { $0.objectId == duplicateID && $0.changes == .insert })

            storage.conversationRemove(conversationWith: conversation.id)

            #expect(storage.conversationWith(identifier: conversation.id) == nil)
            #expect(storage.conversationListAllIdentifiers() == Set([duplicateID]))

            let removalQueues = storage.pendingUploadList(tables: [Conversation.tableName])
            #expect(removalQueues.count == 2)
            #expect(removalQueues.contains { $0.objectId == conversation.id && $0.changes == .delete })
            #expect(removalQueues.contains { $0.objectId == duplicateID && $0.changes == .insert })
        }
    }
}
