import CryptoKit
import Foundation

/// Native metadata is scoped to an authenticated binding and erased on sign-out.
/// Transcript and draft contents never enter UserDefaults.
@MainActor
final class PiConversationPreferences {
    struct Configuration: Codable, Equatable {
        let provider: String
        let modelID: String
        let thinkingLevel: PiGatewayWire.ThinkingLevel
    }

    struct Flags: Codable, Equatable {
        var favorite = false
        var pinned = false
    }

    private struct State: Codable {
        var configurations: [String: Configuration] = [:]
        var flags: [String: Flags] = [:]
    }

    private let defaults: UserDefaults
    private let key = "Pi.Authenticated.NativePreferences"
    private var state: State

    init(defaults: UserDefaults) {
        self.defaults = defaults
        state = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(State.self, from: $0) } ?? State()
    }

    private func scope(_ binding: PiSessionCoordinator.Binding, session: Bool) -> String {
        let fields = [binding.baseURL.absoluteString, binding.repository, binding.clientID, session ? binding.sessionID : ""]
        let data = (try? JSONEncoder().encode(fields)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func configuration(for binding: PiSessionCoordinator.Binding) -> Configuration? {
        state.configurations[scope(binding, session: false)]
    }

    func save(_ configuration: Configuration, binding: PiSessionCoordinator.Binding) {
        state.configurations[scope(binding, session: false)] = configuration
        persist()
    }

    func flags(for binding: PiSessionCoordinator.Binding) -> Flags {
        state.flags[scope(binding, session: true)] ?? Flags()
    }

    func save(_ flags: Flags, binding: PiSessionCoordinator.Binding) {
        state.flags[scope(binding, session: true)] = flags
        persist()
    }

    private func homePrefix(origin: URL) -> String {
        let digest = SHA256.hash(data: Data(HomeAuthenticationAuthority.originKey(origin).utf8)).map { String(format: "%02x", $0) }.joined()
        return "home|" + digest + "|"
    }

    private func homeScope(identity: HomeGateway.Identity, origin: URL, sessionID: String) -> String {
        let fields = [identity.subject, identity.scopeType.rawValue, identity.scopeId, identity.workspaceId, identity.generation, sessionID]
        let data = try! JSONEncoder().encode(fields)
        return homePrefix(origin: origin) + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func homeFlags(identity: HomeGateway.Identity, origin: URL, sessionID: String) -> Flags {
        state.flags[homeScope(identity: identity, origin: origin, sessionID: sessionID)] ?? Flags()
    }

    func saveHomeFlags(_ flags: Flags, identity: HomeGateway.Identity, origin: URL, sessionID: String) {
        state.flags[homeScope(identity: identity, origin: origin, sessionID: sessionID)] = flags
        persist()
    }

    func removeHomeFlags(origin: URL) {
        let prefix = homePrefix(origin: origin)
        state.flags = state.flags.filter { !$0.key.hasPrefix(prefix) }
        persist()
    }

    func removePiPreferences() {
        state.configurations.removeAll()
        state.flags = state.flags.filter { $0.key.hasPrefix("home|") }
        persist()
    }

    func removeAll() {
        state = State()
        defaults.removeObject(forKey: key)
    }

    private func persist() { defaults.set(try? JSONEncoder().encode(state), forKey: key) }
}
