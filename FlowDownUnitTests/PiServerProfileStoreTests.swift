@testable import FlowDown
import Foundation
import Testing
import UIKit

@Suite(.serialized)
struct PiServerProfileStoreTests {
    @Test
    func `blank token preserves credential for the same server`() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let url = try #require(URL(string: "https://pi.example.test"))

        try context.store.save(baseURL: url, token: "secret")
        try context.store.save(baseURL: url, token: nil)

        #expect(try context.store.load() == PiServerProfile(baseURL: url, token: "secret"))
        #expect(context.credentials.removedServers.isEmpty)
    }

    @Test
    func `replacing server removes previous credential`() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let first = try #require(URL(string: "https://first.example.test"))
        let second = try #require(URL(string: "https://second.example.test"))

        try context.store.save(baseURL: first, token: "secret")
        try context.store.save(baseURL: second, token: nil)

        #expect(context.credentials.removedServers.contains(first))
        #expect(try context.store.load() == PiServerProfile(baseURL: second, token: nil))
    }

    @Test
    func `failed previous credential removal rolls back replacement atomically`() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let first = try #require(URL(string: "https://first.example.test"))
        let second = try #require(URL(string: "https://second.example.test"))
        try context.store.save(baseURL: first, token: "first-secret")
        context.credentials.failNextRemoval(of: first)

        #expect(throws: PiCredentialTestError.failed) {
            try context.store.save(baseURL: second, token: "second-secret")
        }

        #expect(try context.store.load() == PiServerProfile(baseURL: first, token: "first-secret"))
        #expect(try context.credentials.token(server: second) == nil)
    }

    @Test
    func `failed same-server replacement preserves existing credential`() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let url = try #require(URL(string: "https://pi.example.test"))
        try context.store.save(baseURL: url, token: "original")
        context.credentials.failNextSave(to: url)

        #expect(throws: PiCredentialTestError.failed) {
            try context.store.save(baseURL: url, token: "replacement")
        }
        #expect(try context.store.load()?.token == "original")
    }

    @Test
    func `explicit saved-token removal preserves server profile`() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let url = try #require(URL(string: "https://pi.example.test"))
        try context.store.save(baseURL: url, token: "secret")

        try context.store.removeSavedToken()

        #expect(try context.store.load() == PiServerProfile(baseURL: url, token: nil))
        #expect(try context.store.hasSavedToken() == false)
    }

    @Test
    @MainActor
    func `server screen exposes explicit saved-token removal without revealing token`() throws {
        let context = makeContext()
        defer { context.defaults.removePersistentDomain(forName: context.suiteName) }
        let url = try #require(URL(string: "https://pi.example.test"))
        try context.store.save(baseURL: url, token: "secret")
        let controller = SettingController.SettingContent.PiServerController(
            profileStore: context.store,
            autoConnect: false
        )
        controller.loadViewIfNeeded()

        let tokenCell = controller.tableView(
            controller.tableView,
            cellForRowAt: IndexPath(row: 1, section: 0)
        )
        let cell = controller.tableView(
            controller.tableView,
            cellForRowAt: IndexPath(row: 3, section: 0)
        )
        #expect((cell.contentConfiguration as? UIListContentConfiguration)?.text == String(localized: "Remove Saved Token"))
        #expect(tokenCell.contentView.subviews.compactMap { $0 as? UITextField }.first?.text?.isEmpty != false)
        #expect(controller.hasSavedToken)

        controller.removeSavedToken()
        #expect(!controller.hasSavedToken)
        #expect(try context.store.load()?.token == nil)
    }

    private func makeContext() -> (
        store: PiServerProfileStore,
        credentials: PiCredentialStoreSpy,
        defaults: UserDefaults,
        suiteName: String
    ) {
        let suiteName = "PiServerProfileStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let credentials = PiCredentialStoreSpy()
        return (
            PiServerProfileStore(defaults: defaults, credentials: credentials),
            credentials,
            defaults,
            suiteName
        )
    }
}

private final class PiCredentialStoreSpy: PiCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: [URL: String] = [:]
    private var removals: [URL] = []
    private var failedSave: URL?
    private var failedRemoval: URL?

    var removedServers: [URL] { lock.withLock { removals } }

    func failNextSave(to server: URL) { lock.withLock { failedSave = server } }
    func failNextRemoval(of server: URL) { lock.withLock { failedRemoval = server } }

    func saveToken(_ token: String, server: URL) throws {
        try lock.withLock {
            if failedSave == server {
                failedSave = nil
                throw PiCredentialTestError.failed
            }
            tokens[server] = token
        }
    }

    func token(server: URL) throws -> String? {
        lock.withLock { tokens[server] }
    }

    func removeToken(server: URL) throws {
        try lock.withLock {
            if failedRemoval == server {
                failedRemoval = nil
                throw PiCredentialTestError.failed
            }
            tokens[server] = nil
            removals.append(server)
        }
    }
}

private enum PiCredentialTestError: Error {
    case failed
}
