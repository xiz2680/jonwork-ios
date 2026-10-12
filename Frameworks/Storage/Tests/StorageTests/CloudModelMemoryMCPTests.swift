import Foundation
@testable import Storage
import Testing

struct CloudModelMemoryMCPTests {
    @Test
    func `cloud models memories and model context servers support CRUD and pending upload tracking`() throws {
        try StorageTestSupport.withTemporaryStorage { storage in
            let cloudModel = CloudModel(
                deviceId: Storage.deviceId,
                model_identifier: "unit-model",
                endpoint: "https://example.com/v1/chat/completions",
                token: "token",
            )
            try storage.cloudModelPut(cloudModel)

            let insertedCloud = try #require(storage.cloudModel(with: cloudModel.id))
            #expect(insertedCloud.model_identifier == "unit-model")
            #expect(storage.pendingUploadList(tables: [CloudModel.tableName]).first?.changes == .insert)

            storage.cloudModelEdit(identifier: cloudModel.id) { model in
                model.update(\.name, to: "Renamed Model")
            }
            #expect(storage.cloudModel(with: cloudModel.id)?.name == "Renamed Model")
            #expect(storage.pendingUploadList(tables: [CloudModel.tableName]).first?.changes == .update)

            let memory = Memory(
                deviceId: Storage.deviceId,
                content: "Remember this",
                conversationId: "conversation-id",
            )
            try storage.insertMemory(memory)

            #expect(try storage.getMemoryCount() == 1)
            #expect(try storage.searchMemories(query: "Remember").count == 1)

            memory.update(\.content, to: "Remember this better")
            try storage.updateMemory(memory)
            #expect(try storage.getMemory(id: memory.id)?.content == "Remember this better")
            #expect(storage.pendingUploadList(tables: [Memory.tableName]).first?.changes == .update)

            let server = storage.modelContextServerMake { server in
                server.update(\.name, to: "Unit MCP")
                server.update(\.endpoint, to: "https://example.com/mcp")
            }

            #expect(storage.modelContextServerList().map(\.id) == [server.id])
            #expect(storage.pendingUploadList(tables: [ModelContextServer.tableName]).first?.changes == .insert)

            storage.modelContextServerEdit(identifier: server.id) { server in
                server.update(\.comment, to: "Updated")
            }
            #expect(storage.modelContextServerWith(server.id)?.comment == "Updated")
            #expect(storage.pendingUploadList(tables: [ModelContextServer.tableName]).first?.changes == .update)

            storage.cloudModelRemove(identifier: cloudModel.id)
            try storage.deleteMemory(id: memory.id)
            storage.modelContextServerRemove(identifier: server.id)

            #expect(storage.cloudModel(with: cloudModel.id) == nil)
            #expect(try storage.getMemory(id: memory.id) == nil)
            #expect(storage.modelContextServerWith(server.id) == nil)

            #expect(storage.pendingUploadList(tables: [CloudModel.tableName]).first?.changes == .delete)
            #expect(storage.pendingUploadList(tables: [Memory.tableName]).first?.changes == .delete)
            #expect(storage.pendingUploadList(tables: [ModelContextServer.tableName]).first?.changes == .delete)
        }
    }
}
