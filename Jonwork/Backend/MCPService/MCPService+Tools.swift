//
//  MCPService+Tools.swift
//  Jonwork
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
        guard allowsLegacyNetworking else {
            disconnectAllLegacyConnections()
            throw MCPError.serverDisabled
        }
        guard let connection = connections[clientName], connection.hasClient else {
            throw MCPError.connectionFailed
        }

        do {
            let result = try await connection.callTool(name: name, arguments: arguments)
            guard allowsLegacyNetworking else {
                discardLegacyConnection(connection, serverID: clientName)
                throw MCPError.serverDisabled
            }
            return result
        } catch {
            if !allowsLegacyNetworking {
                discardLegacyConnection(connection, serverID: clientName)
                throw MCPError.serverDisabled
            }
            throw error
        }
    }

    func getAllTools() async -> [MCPToolInfo] {
        guard allowsLegacyNetworking else {
            disconnectAllLegacyConnections()
            return []
        }
        var allTools: [MCPToolInfo] = []

        for (serverID, connection) in Array(connections) {
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
                guard allowsLegacyNetworking else {
                    discardLegacyConnection(connection, serverID: serverID)
                    disconnectAllLegacyConnections()
                    return []
                }
                allTools.append(contentsOf: toolInfos)
            } catch {
                if !allowsLegacyNetworking {
                    discardLegacyConnection(connection, serverID: serverID)
                    disconnectAllLegacyConnections()
                    return []
                }
                Logger.network.errorFile("failed to acquire tools from \(serverID): \(error.localizedDescription)")
            }
        }

        return allTools
    }
}
