@testable import Jonwork
import Foundation
import Storage

actor JonworkTestContext {
    static let shared = JonworkTestContext()

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
