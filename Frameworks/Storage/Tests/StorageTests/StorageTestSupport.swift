import Foundation
@testable import Storage

enum StorageTestSupport {
    static func withTemporaryStorage(
        _ body: (Storage) throws -> Void,
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
        )

        let storage = try Storage.makeForTesting(databaseDir: directory)
        defer {
            storage.db.close()
            try? FileManager.default.removeItem(at: directory)
        }

        try body(storage)
    }
}
