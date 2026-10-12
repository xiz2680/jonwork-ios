//
//  ConversationSummaryMigrationTests.swift
//  StorageTests
//
//  Created by Codex on 2026/03/26.
//

import Foundation
@testable import Storage
import Testing
import WCDBSwift

struct ConversationSummaryMigrationTests {
    @Test
    func `ConversationSummary uses a deterministic sync object id`() {
        let summary = ConversationSummary(deviceId: "device-id", conversationId: "conversation-id")
        #expect(summary.id == ConversationSummary.objectId(forConversationID: "conversation-id"))
    }

    @Test
    func `V5 -> V6 creates ConversationSummary table and bumps userVersion`() throws {
        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let databaseURL = tempDirectory.appendingPathComponent("migration.db")
        let database = Database(at: databaseURL.path)
        defer { database.close() }

        try database.exec(StatementPragma().pragma(.userVersion).to(DBVersion.Version5.rawValue))

        let migration = MigrationV5ToV6()
        try migration.migrate(db: database)

        #expect(try database.isTableExists(ConversationSummary.tableName))
        let userVersion = try database.getValue(from: StatementPragma().pragma(.userVersion))?.intValue
        #expect(userVersion == DBVersion.Version6.rawValue)
    }
}
