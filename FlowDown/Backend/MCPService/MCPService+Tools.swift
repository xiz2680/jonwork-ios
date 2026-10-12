//
//  MCPService+Tools.swift
//  FlowDown
//
//  Created by Alan Ye on 7/10/25.
//

import AlertController
import ChatClientKit
import Combine
import ConfigurableKit
import Foundation
import MCP
import UIKit

// MARK: - MCPService Tools Extension

extension MCPService {
    func callTool(name: String, arguments: [String: Value]? = nil, from clientName: String) async throws -> (content: [Tool.Content], isError: Bool?) {
        guard let connection = connections[clientName], connection.hasClient else {
            throw MCPError.connectionFailed
        }

        return try await connection.callTool(name: name, arguments: arguments)
    }

    func getAllTools() async -> [MCPToolInfo] {
        var allTools: [MCPToolInfo] = []

        for (serverID, connection) in connections {
            do {
                guard let server = server(with: serverID),
                      server.isEnabled,
                      connection.hasClient
                else {
                    continue
                }
                let name = URL(string: server.endpoint)?.host ?? serverID
                let toolInfos = try await connection.listToolInfos(
                    serverID: serverID,
                    serverName: name,
                )
                allTools.append(contentsOf: toolInfos)
            } catch {
                Logger.network.errorFile("failed to acquire tools from \(serverID): \(error.localizedDescription)")
            }
        }

        return allTools
    }
}
