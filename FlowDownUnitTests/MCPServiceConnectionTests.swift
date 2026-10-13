@testable import FlowDown
import Combine
import Foundation
import MCP
import Storage
import Testing

@Suite(.serialized)
struct MCPServiceConnectionTests {
    @Test
    func `revocation interrupts prepare reconnect and discards its result`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        var allowsLegacyNetworking = true
        let connection = MCPBlockingConnectionSpy()
        let server = sdb.modelContextServerMake { server in
            server.update(\.name, to: "Blocking Prepare MCP")
            server.update(\.endpoint, to: "https://blocking-prepare.example.test/mcp")
            server.update(\.isEnabled, to: true)
        }
        let service = MCPService(
            legacyNetworkingPolicy: { allowsLegacyNetworking },
            connectionFactory: { _ in connection }
        )
        defer { sdb.modelContextServerRemove(identifier: server.id) }

        try await waitUntil { !service.connections.isEmpty }
        connection.prepareForBlockingConnect()
        let prepareTask = Task { await service.prepareForConversation() }
        try await waitUntil { connection.connectIsBlocked }

        allowsLegacyNetworking = false
        service.updateFromDatabase()
        let errors = await prepareTask.value

        #expect(errors.isEmpty)
        #expect(connection.disconnectCount > 0)
        #expect(service.connections.isEmpty)
        #expect(sdb.modelContextServerWith(server.id)?.connectionStatus == .disconnected)
    }

    @Test
    func `revocation during capability discovery cannot report test success`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        var allowsLegacyNetworking = true
        let connection = MCPBlockingConnectionSpy(blockList: true)
        let server = sdb.modelContextServerMake { server in
            server.update(\.name, to: "Blocking List MCP")
            server.update(\.endpoint, to: "https://blocking-list.example.test/mcp")
            server.update(\.isEnabled, to: false)
        }
        let service = MCPService(
            legacyNetworkingPolicy: { allowsLegacyNetworking },
            connectionFactory: { _ in connection }
        )
        defer { sdb.modelContextServerRemove(identifier: server.id) }

        let resultTask = Task {
            await withCheckedContinuation { continuation in
                service.testConnection(serverID: server.id) { result in
                    continuation.resume(returning: result)
                }
            }
        }
        try await waitUntil { connection.listIsBlocked }

        allowsLegacyNetworking = false
        service.updateFromDatabase()
        let result = await resultTask.value

        if case .success = result {
            Issue.record("revoked capability discovery returned success")
        }
        #expect(connection.disconnectCount > 0)
        #expect(service.connections.isEmpty)
        #expect(sdb.modelContextServerWith(server.id)?.connectionStatus == .disconnected)
    }

    @Test
    func `revocation during tool call interrupts request and discards success`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        var allowsLegacyNetworking = true
        let connection = MCPBlockingConnectionSpy(blockCall: true)
        let server = sdb.modelContextServerMake { server in
            server.update(\.name, to: "Blocking Call MCP")
            server.update(\.endpoint, to: "https://blocking-call.example.test/mcp")
            server.update(\.isEnabled, to: true)
        }
        let service = MCPService(
            legacyNetworkingPolicy: { allowsLegacyNetworking },
            connectionFactory: { _ in connection }
        )
        defer { sdb.modelContextServerRemove(identifier: server.id) }

        try await waitUntil { !service.connections.isEmpty }
        let callTask = Task {
            do {
                _ = try await service.callTool(name: "blocked", from: server.id)
                return true
            } catch {
                return false
            }
        }
        try await waitUntil { connection.callIsBlocked }

        allowsLegacyNetworking = false
        service.updateFromDatabase()
        let returnedSuccess = await callTask.value

        #expect(!returnedSuccess)
        #expect(connection.disconnectCount > 0)
        #expect(service.connections.isEmpty)
        #expect(sdb.modelContextServerWith(server.id)?.connectionStatus == .disconnected)
    }

    @Test
    func `production policy does not connect enabled persisted servers`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let server = sdb.modelContextServerMake { server in
            server.update(\.name, to: "Persisted Enabled MCP")
            server.update(\.endpoint, to: "https://production-policy.example.test/mcp")
            server.update(\.isEnabled, to: true)
        }
        let connection = MCPConnectionSpy(toolNames: ["must-not-discover"])
        let service = MCPService(
            legacyNetworkingPolicy: { false },
            connectionFactory: { _ in connection }
        )
        defer {
            sdb.modelContextServerRemove(identifier: server.id)
            MCPService.shared.updateFromDatabase()
        }

        service.updateFromDatabase()
        _ = await service.prepareForConversation()
        service.ensureOrReconnect(server.id)
        let tools = await service.getAllTools()
        let serverTools = await service.listServerTools()
        let testConnectionWasRejected = await withCheckedContinuation { continuation in
            service.testConnection(serverID: server.id) { result in
                switch result {
                case .success:
                    continuation.resume(returning: false)
                case .failure:
                    continuation.resume(returning: true)
                }
            }
        }
        try await Task.sleep(for: .milliseconds(100))

        #expect(service.servers.value.contains { $0.id == server.id })
        #expect(service.connections.isEmpty)
        #expect(connection.connectCount == 0)
        #expect(connection.listToolInfoCount == 0)
        #expect(tools.isEmpty)
        #expect(serverTools.isEmpty)
        #expect(testConnectionWasRejected)
    }

    @Test
    func `revoked legacy networking disconnects and does not restore existing connection`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let server = sdb.modelContextServerMake { server in
            server.update(\.name, to: "Revoked MCP")
            server.update(\.endpoint, to: "https://revoked-policy.example.test/mcp")
            server.update(\.isEnabled, to: true)
        }
        var allowsLegacyNetworking = true
        let connection = MCPConnectionSpy(toolNames: [])
        let service = MCPService(
            legacyNetworkingPolicy: { allowsLegacyNetworking },
            connectionFactory: { _ in connection }
        )
        defer {
            sdb.modelContextServerRemove(identifier: server.id)
            MCPService.shared.updateFromDatabase()
        }

        let deadline = ContinuousClock.now + .seconds(2)
        while connection.connectCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try await Task.sleep(for: .milliseconds(100))
        let connectCountBeforeRevocation = connection.connectCount
        #expect(connectCountBeforeRevocation > 0)

        allowsLegacyNetworking = false
        service.updateFromDatabase()
        service.ensureOrReconnect(server.id)
        try await Task.sleep(for: .milliseconds(100))

        #expect(service.connections.isEmpty)
        #expect(connection.disconnectCount > 0)
        #expect(connection.connectCount == connectCountBeforeRevocation)
    }

    @Test
    func `testConnection uses injected connection factory`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let service = MCPService.shared
        let originalFactory = service.connectionFactory

        let server = service.create { server in
            server.update(\.name, to: "Unit MCP")
            server.update(\.endpoint, to: "https://example.com/mcp")
            server.update(\.isEnabled, to: false)
        }

        let connection = MCPConnectionSpy(toolNames: ["search", "fetch"])
        service.connectionFactory = { _ in connection }

        defer {
            service.connectionFactory = originalFactory
            service.remove(server.id)
        }

        let summary = try await withCheckedThrowingContinuation { continuation in
            service.testConnection(serverID: server.id) { result in
                continuation.resume(with: result)
            }
        }

        #expect(summary == "Unit MCP: search, Unit MCP: fetch")
        #expect(connection.connectCount == 1)
    }
}

private func waitUntil(
    timeout: Duration = .seconds(2),
    condition: () -> Bool
) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(condition())
}

private final class MCPBlockingConnectionSpy: MCPConnectionControlling {
    private let lock = NSLock()
    private var connectContinuation: CheckedContinuation<Void, any Error>?
    private var listContinuation: CheckedContinuation<[MCPToolInfo], any Error>?
    private var callContinuation: CheckedContinuation<(content: [Tool.Content], isError: Bool?), any Error>?
    private var shouldBlockConnect = false
    private var shouldBlockList: Bool
    private var shouldBlockCall: Bool
    private var reportedConnected = true
    private var storedDisconnectCount = 0

    init(blockList: Bool = false, blockCall: Bool = false) {
        shouldBlockList = blockList
        shouldBlockCall = blockCall
    }

    var hasClient: Bool { true }

    var isConnected: Bool {
        lock.withLock { reportedConnected }
    }

    var disconnectCount: Int {
        lock.withLock { storedDisconnectCount }
    }

    var connectIsBlocked: Bool {
        lock.withLock { connectContinuation != nil }
    }

    var listIsBlocked: Bool {
        lock.withLock { listContinuation != nil }
    }

    var callIsBlocked: Bool {
        lock.withLock { callContinuation != nil }
    }

    func prepareForBlockingConnect() {
        lock.withLock {
            reportedConnected = false
            shouldBlockConnect = true
        }
    }

    func connect() async throws {
        let shouldBlock = lock.withLock { shouldBlockConnect }
        guard shouldBlock else { return }
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock { connectContinuation = continuation }
        }
    }

    func disconnect() {
        let continuations = lock.withLock {
            storedDisconnectCount += 1
            reportedConnected = false
            let continuations = (connectContinuation, listContinuation, callContinuation)
            connectContinuation = nil
            listContinuation = nil
            callContinuation = nil
            return continuations
        }
        continuations.0?.resume(throwing: CancellationError())
        continuations.1?.resume(throwing: CancellationError())
        continuations.2?.resume(throwing: CancellationError())
    }

    func listToolInfos(serverID _: ModelContextServer.ID, serverName _: String) async throws -> [MCPToolInfo] {
        let shouldBlock = lock.withLock { shouldBlockList }
        guard shouldBlock else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { listContinuation = continuation }
        }
    }

    func callTool(name _: String, arguments _: [String: Value]?) async throws -> (content: [Tool.Content], isError: Bool?) {
        let shouldBlock = lock.withLock { shouldBlockCall }
        guard shouldBlock else { return ([], nil) }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { callContinuation = continuation }
        }
    }
}

private final class MCPConnectionSpy: MCPConnectionControlling {
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    private(set) var listToolInfoCount = 0
    private let toolNames: [String]

    init(toolNames: [String]) {
        self.toolNames = toolNames
    }

    var hasClient: Bool {
        true
    }

    var isConnected: Bool {
        true
    }

    func connect() async throws {
        connectCount += 1
    }

    func disconnect() {
        disconnectCount += 1
    }

    func listToolInfos(serverID: ModelContextServer.ID, serverName: String) async throws -> [MCPToolInfo] {
        listToolInfoCount += 1
        return toolNames.map { toolName in
            MCPToolInfo(
                name: toolName,
                serverID: serverID,
                serverName: serverName,
            )
        }
    }

    func callTool(name _: String, arguments _: [String: Value]?) async throws -> (content: [Tool.Content], isError: Bool?) {
        ([], nil)
    }
}
