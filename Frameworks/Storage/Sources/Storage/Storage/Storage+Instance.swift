//
//  Storage+Instance.swift
//  Conversation
//
//  Created by 秋星桥 on 1/21/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    static func db() throws -> Storage {
        if let instance { return instance }
        let new = try Storage(name: "Main")
        instance = new
        return new
    }

    #if DEBUG
        package static func makeForTesting(
            name: String = "Test",
            databaseDir: URL,
        ) throws -> Storage {
            try Storage(name: name, databaseDir: databaseDir)
        }
    #endif

    #if DEBUG
        static func resetForTesting() {
            instance = nil
        }
    #endif

    static func setSyncEngine(_ syncEngine: SyncEngine) {
        instance?.syncEngine = syncEngine
    }

    private static var instance: Storage?
}
