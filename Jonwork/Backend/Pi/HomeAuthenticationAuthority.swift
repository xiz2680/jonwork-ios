import Foundation

/// Owned by the existing session coordinator, with weak per-origin clients.
/// All access and Keychain admission run on the main actor.
@MainActor
final class HomeAuthenticationAuthority {
    private final class WeakClient {
        weak var value: HomeGatewayClient?
        init(_ value: HomeGatewayClient) { self.value = value }
    }
    private let preferences: PiConversationPreferences?
    init(preferences: PiConversationPreferences? = nil) { self.preferences = preferences }

    func flags(identity: HomeGateway.Identity, origin: URL, sessionID: String) -> PiConversationPreferences.Flags {
        preferences?.homeFlags(identity: identity, origin: origin, sessionID: sessionID) ?? .init()
    }
    func saveFlags(_ flags: PiConversationPreferences.Flags, identity: HomeGateway.Identity, origin: URL, sessionID: String) {
        preferences?.saveHomeFlags(flags, identity: identity, origin: origin, sessionID: sessionID)
    }

    private var epochs: [String: UInt64] = [:]
    private var clients: [String: [WeakClient]] = [:]

    static func originKey(_ origin: URL) -> String {
        "\(origin.scheme?.lowercased() ?? "")://\(origin.host?.lowercased() ?? ""):\(origin.port ?? 443)"
    }
    func register(_ client: HomeGatewayClient, origin: URL) {
        let key = Self.originKey(origin)
        clients[key, default: []].removeAll { $0.value == nil }
        clients[key, default: []].append(WeakClient(client))
    }
    func advance(origin: URL, excluding: HomeGatewayClient? = nil) -> UInt64 {
        let key = Self.originKey(origin)
        epochs[key, default: 0] &+= 1
        if excluding == nil { preferences?.removeHomeFlags(origin: origin) }
        for client in clients[key, default: []].compactMap(\.value) where client !== excluding { client.invalidateLocalAuthority() }
        NotificationCenter.default.post(name: .homeAuthorizationDidChange, object: nil)
        return epochs[key]!
    }
    func isCurrent(_ epoch: UInt64, origin: URL) -> Bool { epochs[Self.originKey(origin), default: 0] == epoch }
}

extension Notification.Name {
    static let homeAuthorizationDidChange = Notification.Name("HomeAuthorizationDidChange")
}
