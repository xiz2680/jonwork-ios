@testable import FlowDown
import Foundation
import MCP
import Storage
import Testing

@Suite(.serialized)
struct MCPServiceConnectionTests {
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

private final class MCPConnectionSpy: MCPConnectionControlling {
    private(set) var connectCount = 0
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

    func disconnect() {}

    func listToolInfos(serverID: ModelContextServer.ID, serverName: String) async throws -> [MCPToolInfo] {
        toolNames.map { toolName in
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
