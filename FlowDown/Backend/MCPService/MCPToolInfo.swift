//
//  MCPToolInfo.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/10/25.
//

import Foundation
import MCP
import Storage

struct MCPToolInfo {
    let name: String
    let description: String?
    let inputSchema: Value?
    let serverID: ModelContextServer.ID
    let serverName: String

    init(
        name: String,
        description: String? = nil,
        inputSchema: Value? = nil,
        serverID: ModelContextServer.ID,
        serverName: String,
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.serverID = serverID
        self.serverName = serverName
    }

    init(tool: Tool, serverID: ModelContextServer.ID, serverName: String) {
        self.init(
            name: tool.name,
            description: tool.description,
            inputSchema: tool.inputSchema,
            serverID: serverID,
            serverName: serverName,
        )
    }
}
