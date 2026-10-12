import Foundation
@testable import Storage
import Testing

struct MessageStorageTests {
    @Test
    func `message lookup and deleteAfter remove later messages and attachments`() throws {
        try StorageTestSupport.withTemporaryStorage { storage in
            let conversation = storage.conversationMake { conversation in
                conversation.update(\.title, to: "Thread")
            }
            let first = storage.makeMessage(with: conversation.id) { message in
                message.update(\.role, to: .user)
                message.update(\.document, to: "First")
            }
            let second = storage.makeMessage(with: conversation.id) { message in
                message.update(\.role, to: .assistant)
                message.update(\.document, to: "Second")
            }
            let third = storage.makeMessage(with: conversation.id) { message in
                message.update(\.role, to: .assistant)
                message.update(\.document, to: "Third")
            }
            _ = storage.attachmentMake(with: second.id) { attachment in
                attachment.update(\.name, to: "second.txt")
                attachment.update(\.type, to: "text/plain")
            }
            _ = storage.attachmentMake(with: third.id) { attachment in
                attachment.update(\.name, to: "third.txt")
                attachment.update(\.type, to: "text/plain")
            }

            #expect(storage.conversationIdentifierLookup(identifier: second.id) == conversation.id)
            #expect(storage.listMessages(within: conversation.id).map(\.id) == [first.id, second.id, third.id])
            #expect(storage.attachment(for: second.id).count == 1)
            #expect(storage.attachment(for: third.id).count == 1)

            storage.deleteAfter(messageIdentifier: first.id)

            #expect(storage.listMessages(within: conversation.id).map(\.id) == [first.id])
            #expect(storage.attachment(for: second.id).isEmpty)
            #expect(storage.attachment(for: third.id).isEmpty)

            let queues = storage.pendingUploadList(tables: [Message.tableName])
            #expect(queues.count == 3)
            #expect(queues.contains { $0.objectId == first.id && $0.changes == .insert })
            #expect(queues.contains { $0.objectId == second.id && $0.changes == .delete })
            #expect(queues.contains { $0.objectId == third.id && $0.changes == .delete })
        }
    }
}
