//
//  MCPConnection.swift
//  FlowDown
//
//  Created by Alan Ye on 7/10/25.
//

import Combine
import Foundation
import MCP
import Storage

// MARK: - Connection Manager

protocol MCPConnectionControlling: AnyObject {
    var hasClient: Bool { get }
    var isConnected: Bool { get }

    func connect() async throws
    func disconnect()
    func listToolInfos(serverID: ModelContextServer.ID, serverName: String) async throws -> [MCPToolInfo]
    func callTool(name: String, arguments: [String: Value]?) async throws -> (content: [Tool.Content], isError: Bool?)
}

class MCPConnection: MCPConnectionControlling {
    // MARK: - Properties

    private let config: ModelContextServer
    private(set) var client: MCP.Client?

    // MARK: - Initialization

    init(config: ModelContextServer) {
        self.config = config
    }

    // MARK: - Connection Management

    func connect() async throws {
        guard client == nil else {
            Logger.network.infoFile("client already connected for \(config.id)")
            return
        }

        let client = createClient()
        let transport = try config.createTransport()

        Logger.network.infoFile("connecting client for server: \(config.id)")
        try await client.connect(transport: transport)

        self.client = client
        Logger.network.infoFile("successfully connected to server: \(config.id)")
    }

    func disconnect() {
        guard let client else { return }

        Logger.network.infoFile("disconnecting client for server: \(config.id)")
        Task.detached { await client.disconnect() }
        self.client = nil
        Logger.network.infoFile("client disconnected for server: \(config.id)")
    }

    var isConnected: Bool {
        client != nil
    }

    var hasClient: Bool {
        client != nil
    }

    func listToolInfos(serverID: ModelContextServer.ID, serverName: String) async throws -> [MCPToolInfo] {
        guard let client else {
            throw MCPError.connectionFailed
        }

        let tools = try await client.listTools().tools
        return tools.map { tool in
            MCPToolInfo(
                tool: tool,
                serverID: serverID,
                serverName: serverName,
            )
        }
    }

    func callTool(name: String, arguments: [String: Value]? = nil) async throws -> (content: [Tool.Content], isError: Bool?) {
        guard let client else {
            throw MCPError.connectionFailed
        }

        return try await client.callTool(name: name, arguments: arguments)
    }

    private func createClient() -> MCP.Client {
        let bundleId = Bundle.main.bundleIdentifier ?? "flowdown.ai"
        return MCP.Client(name: bundleId, version: AnchorVersion.version)
    }
}
