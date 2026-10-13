//
//  MCPService.swift
//  FlowDown
//
//  Created by LiBr on 6/29/25.
//

import Combine
import Foundation
import MCP
import Storage

class MCPService: NSObject {
    static let shared = MCPService()
    static let executor = MCPServiceActor.shared
    typealias ConnectionFactory = (ModelContextServer) -> any MCPConnectionControlling
    typealias LegacyNetworkingPolicy = () -> Bool

    // MARK: - Properties

    let servers: CurrentValueSubject<[ModelContextServer], Never> = .init([])
    private(set) var connections: [ModelContextServer.ID: any MCPConnectionControlling] = [:]
    private var inFlightConnections: [ObjectIdentifier: (ModelContextServer.ID, any MCPConnectionControlling)] = [:]
    private var cancellables = Set<AnyCancellable>()
    var connectionFactory: ConnectionFactory
    private let legacyNetworkingPolicy: LegacyNetworkingPolicy

    // MARK: - Initialization

    override private convenience init() {
        self.init(
            legacyNetworkingPolicy: { JonworkSurfacePolicy.allowsLegacyProviderNetworking },
            connectionFactory: { MCPConnection(config: $0) }
        )
    }

    init(
        legacyNetworkingPolicy: @escaping LegacyNetworkingPolicy,
        connectionFactory: @escaping ConnectionFactory
    ) {
        self.legacyNetworkingPolicy = legacyNetworkingPolicy
        self.connectionFactory = connectionFactory
        super.init()
        for server in sdb.modelContextServerList() {
            updateServerStatus(server.id, status: .disconnected)
        }
        updateFromDatabase()
        setupServerSync()

        NotificationCenter.default.publisher(for: SyncEngine.ModelContextServerChanged)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                logger.infoFile("Recived SyncEngine.ModelContextServerChanged")
                self?.updateFromDatabase()
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupServerSync() {
        servers
            .map { $0.filter(\.isEnabled) }
            .removeDuplicates()
            .ensureMainThread()
            .sink { [weak self] enabledServers in
                guard let self else { return }
                Task {
                    await MCPService.executor.run {
                        guard self.allowsLegacyNetworking else {
                            self.disconnectAllLegacyConnections()
                            return
                        }
                        await self.syncServerConnections(enabledServers)
                    }
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    @discardableResult
    func prepareForConversation() async -> [Swift.Error] {
        guard allowsLegacyNetworking else {
            disconnectAllLegacyConnections()
            return []
        }
        var errors: [Swift.Error] = []
        let snapshot = connections // for thread safety
        for (serverID, connection) in snapshot {
            guard let server = server(with: serverID), server.isEnabled else { continue }
            if connection.isConnected { continue }
            do {
                try await MCPService.executor.run {
                    try await connection.connect()
                }
                guard allowsLegacyNetworking else {
                    discardLegacyConnection(connection, serverID: serverID)
                    return []
                }
            } catch {
                if !allowsLegacyNetworking {
                    discardLegacyConnection(connection, serverID: serverID)
                    return []
                }
                Logger.network.errorFile("failed to connect to server \(serverID): \(error.localizedDescription)")
                errors.append(error)
            }
        }
        return errors
    }

    func insert(_ server: ModelContextServer) {
        sdb.modelContextServerPut(object: server)
        updateFromDatabase()
    }

    @MainActor
    @discardableResult
    func importServer(from data: Data) throws -> ModelContextServer {
        let server = try ModelContextServer.decodeCompatible(from: data)

        // Basic validation: endpoint is required.
        if server.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NSError(
                domain: "MCPImport",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid MCP server configuration: missing endpoint."],
            )
        }

        // Always treat imports as a new local object.
        server.update(\.deviceId, to: Storage.deviceId)
        server.update(\.objectId, to: UUID().uuidString)
        server.update(\.removed, to: false)

        let now = Date.now
        server.update(\.creation, to: now)
        server.update(\.modified, to: now)

        // Reset volatile connection state.
        server.update(\.lastConnected, to: nil)
        server.update(\.connectionStatus, to: .disconnected)

        insert(server)
        return server
    }

    func exportServerData(_ server: ModelContextServer) throws -> Data {
        if server.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NSError(
                domain: "MCPExport",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid MCP server configuration: missing endpoint."],
            )
        }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(server)

        // Validate round-trip decodability (including legacy format support).
        _ = try ModelContextServer.decodeCompatible(from: data)
        return data
    }

    func ensureOrReconnect(_ serverID: ModelContextServer.ID) {
        guard allowsLegacyNetworking else {
            disconnectLegacyConnection(serverID)
            return
        }
        if let connection = connections[serverID], connection.hasClient { return }
        guard let server = sdb.modelContextServerWith(serverID) else { return }
        updateServerStatus(serverID, status: .disconnected)
        Task {
            await MCPService.executor.run {
                await self.connectToServer(server)
            }
        }
    }

    func testConnection(
        serverID: ModelContextServer.ID,
        completion: @escaping (Result<String, Swift.Error>) -> Void,
    ) {
        guard allowsLegacyNetworking else {
            disconnectLegacyConnection(serverID)
            completion(.failure(MCPError.serverDisabled))
            return
        }
        Task {
            await MCPService.executor.run {
                do {
                    guard let server = self.server(with: serverID) else {
                        throw MCPError.invalidConfiguration
                    }
                    self.connections[serverID]?.disconnect()
                    self.connections.removeValue(forKey: serverID)
                    self.updateServerStatus(serverID, status: .disconnected)
                    let connection = try await self.connectOnce(server)
                    guard self.allowsLegacyNetworking else {
                        connection.disconnect()
                        throw MCPError.serverDisabled
                    }
                    if server.isEnabled { self.connections[serverID] = connection }
                    self.registerInFlightConnection(connection, serverID: serverID)
                    defer { self.unregisterInFlightConnection(connection) }
                    guard self.allowsLegacyNetworking else {
                        self.discardLegacyConnection(connection, serverID: serverID)
                        throw MCPError.serverDisabled
                    }
                    let toolInfos = try await connection.listToolInfos(
                        serverID: serverID,
                        serverName: server.displayName,
                    )
                    guard self.allowsLegacyNetworking else {
                        self.discardLegacyConnection(connection, serverID: serverID)
                        throw MCPError.serverDisabled
                    }
                    let toolSummary = toolInfos.map { toolInfo in
                        if let toolServer = self.server(with: serverID) {
                            return "\(toolServer.displayName): \(toolInfo.name)"
                        }
                        return toolInfo.name
                    }.joined(separator: ", ")
                    completion(.success(toolSummary))
                } catch {
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Private Connection Management

    private func syncServerConnections(_ eligibleServers: [ModelContextServer]) async {
        guard allowsLegacyNetworking else {
            disconnectAllLegacyConnections()
            return
        }
        for server in eligibleServers {
            ensureOrReconnect(server.id)
        }

        let eligibleServerIds = Set(eligibleServers.map(\.id))
        for (serverId, connection) in Array(connections) {
            if !eligibleServerIds.contains(serverId) {
                connection.disconnect()
                connections.removeValue(forKey: serverId)
                updateServerStatus(serverId, status: .disconnected)
            }
        }
    }

    private func connectToServer(_ config: ModelContextServer) async {
        guard allowsLegacyNetworking else {
            disconnectLegacyConnection(config.id)
            return
        }
        updateServerStatus(config.id, status: .connecting)

        do {
            let connection = try await MCPService.executor.run {
                try await self.connectOnce(config)
            }
            guard allowsLegacyNetworking else {
                connection.disconnect()
                return
            }
            connections[config.id] = connection
        } catch {
            Logger.network.errorFile("failed to connect to server \(config.id): \(error.localizedDescription)")
            updateServerStatus(config.id, status: .disconnected)
        }
    }

    private func connectOnce(_ config: ModelContextServer) async throws -> any MCPConnectionControlling {
        guard allowsLegacyNetworking else { throw MCPError.serverDisabled }
        let connection = connectionFactory(config)
        registerInFlightConnection(connection, serverID: config.id)
        defer { unregisterInFlightConnection(connection) }
        guard allowsLegacyNetworking else {
            discardLegacyConnection(connection, serverID: config.id)
            throw MCPError.serverDisabled
        }
        try await connection.connect()
        guard allowsLegacyNetworking else {
            connection.disconnect()
            throw MCPError.serverDisabled
        }
        await negotiateCapabilities(connection: connection, config: config)
        guard allowsLegacyNetworking else {
            connection.disconnect()
            throw MCPError.serverDisabled
        }
        updateServerStatus(config.id, status: .connected)
        return connection
    }

    private func updateServerStatus(_ serverId: ModelContextServer.ID, status: ModelContextServer.ConnectionStatus) {
        // 连接状态不进行同步
        edit(identifier: serverId, skipSync: true) {
            $0.update(\.connectionStatus, to: status)
            if status == .connected {
                $0.update(\.lastConnected, to: .now)
            }
        }
    }

    private func negotiateCapabilities(connection: any MCPConnectionControlling, config: ModelContextServer) async {
        guard allowsLegacyNetworking else {
            connection.disconnect()
            return
        }
        var discoveredCapabilities: [String] = []

        do {
            let tools = try await connection.listToolInfos(
                serverID: config.id,
                serverName: config.displayName,
            )
            guard allowsLegacyNetworking else {
                discardLegacyConnection(connection, serverID: config.id)
                return
            }
            if !tools.isEmpty {
                discoveredCapabilities.append("tools")
            }
        } catch {
            Logger.network.errorFile("failed to list tools: \(error.localizedDescription)")
        }
        guard allowsLegacyNetworking else {
            discardLegacyConnection(connection, serverID: config.id)
            return
        }

        // capabilities不进行同步
        edit(identifier: config.id, skipSync: true) {
            $0.assign(\.capabilities, to: StringArrayCodable(discoveredCapabilities))
        }
    }

    func listServerTools() async -> [MCPTool] {
        guard allowsLegacyNetworking else {
            disconnectAllLegacyConnections()
            return []
        }
        let toolInfos = await getAllTools()
        return toolInfos.map { MCPTool(toolInfo: $0, mcpService: self) }
    }

    // MARK: - Database Methods

    func updateFromDatabase() {
        if !allowsLegacyNetworking {
            disconnectAllLegacyConnections()
        }
        servers.send(sdb.modelContextServerList())
    }

    var allowsLegacyNetworking: Bool {
        legacyNetworkingPolicy()
    }

    func disconnectLegacyConnection(_ serverID: ModelContextServer.ID) {
        connections.removeValue(forKey: serverID)?.disconnect()
        updateServerStatus(serverID, status: .disconnected)
    }

    func discardLegacyConnection(
        _ connection: any MCPConnectionControlling,
        serverID: ModelContextServer.ID
    ) {
        if let storedConnection = connections.removeValue(forKey: serverID) {
            if (storedConnection as AnyObject) !== (connection as AnyObject) {
                storedConnection.disconnect()
            }
        }
        connection.disconnect()
        unregisterInFlightConnection(connection)
        updateServerStatus(serverID, status: .disconnected)
    }

    func disconnectAllLegacyConnections() {
        let trackedConnections = Array(inFlightConnections.values)
        let activeConnections = Array(connections.values) + trackedConnections.map(\.1)
        let serverIDs = Set(connections.keys).union(trackedConnections.map(\.0))
        connections.removeAll()
        inFlightConnections.removeAll()
        var disconnected = Set<ObjectIdentifier>()
        for connection in activeConnections {
            if disconnected.insert(ObjectIdentifier(connection)).inserted {
                connection.disconnect()
            }
        }
        for serverID in serverIDs {
            updateServerStatus(serverID, status: .disconnected)
        }
    }

    func registerInFlightConnection(
        _ connection: any MCPConnectionControlling,
        serverID: ModelContextServer.ID
    ) {
        inFlightConnections[ObjectIdentifier(connection)] = (serverID, connection)
    }

    func unregisterInFlightConnection(_ connection: any MCPConnectionControlling) {
        inFlightConnections.removeValue(forKey: ObjectIdentifier(connection))
    }

    func create(block: Storage.ModelContextServerMakeInitDataBlock? = nil) -> ModelContextServer {
        defer { updateFromDatabase() }
        return sdb.modelContextServerMake(block)
    }

    func server(with identifier: ModelContextServer.ID?) -> ModelContextServer? {
        guard let identifier else { return nil }
        return sdb.modelContextServerWith(identifier)
    }

    func remove(_ identifier: ModelContextServer.ID) {
        defer { updateFromDatabase() }
        sdb.modelContextServerRemove(identifier: identifier)
    }

    func edit(identifier: ModelContextServer.ID, skipSync: Bool = false, block: @escaping (inout ModelContextServer) -> Void) {
        defer { updateFromDatabase() }
        sdb.modelContextServerEdit(identifier: identifier, skipSync: skipSync, block)
    }
}
