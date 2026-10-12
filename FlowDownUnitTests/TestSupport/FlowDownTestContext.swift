@testable import FlowDown
import Foundation
import Storage

actor FlowDownTestContext {
    static let shared = FlowDownTestContext()

    func ensureBootstrappedEnvironment() throws {
        if AppEnvironment.isBootstrapped {
            return
        }

        let storage = try Storage.db()
        let syncEngine = SyncEngine(
            storage: storage,
            containerIdentifier: CloudKitConfig.containerIdentifier,
            mode: .mock,
            automaticallySync: false,
        )
        AppEnvironment.bootstrap(.init(storage: storage, syncEngine: syncEngine))
    }
}
