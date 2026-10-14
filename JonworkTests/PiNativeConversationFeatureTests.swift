@testable import Jonwork
import Foundation
import PDFKit
import Testing

struct PiNativeConversationFeatureTests {
    @Test @MainActor
    func nativePreferencesPersistOnlyWithinBindingScopeAndClearOnSignOut() throws {
        let name = "NativePreferences-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let binding = PiSessionCoordinator.Binding(sessionID: "one", repository: "repo", clientID: "account-client", baseURL: URL(string: "https://one.example")!)
        let store = PiConversationPreferences(defaults: defaults)
        let configuration = PiConversationPreferences.Configuration(provider: "actual-provider", modelID: "registry-model", thinkingLevel: .medium)
        store.save(configuration, binding: binding)
        store.save(.init(favorite: true, pinned: true), binding: binding)
        let restored = PiConversationPreferences(defaults: defaults)
        #expect(restored.configuration(for: binding) == configuration)
        #expect(restored.flags(for: binding).favorite)
        let next = PiSessionCoordinator.Binding(sessionID: "two", repository: binding.repository, clientID: binding.clientID, baseURL: binding.baseURL)
        #expect(restored.configuration(for: next) == configuration)
        #expect(!restored.flags(for: next).favorite)
        let other = PiSessionCoordinator.Binding(sessionID: binding.sessionID, repository: binding.repository, clientID: "other-client", baseURL: binding.baseURL)
        #expect(restored.configuration(for: other) == nil)
        #expect(!restored.flags(for: other).pinned)
        restored.removeAll()
        #expect(PiConversationPreferences(defaults: defaults).configuration(for: binding) == nil)
        #expect(PiConversationPreferences(defaults: defaults).flags(for: binding) == .init())
    }

    @Test @MainActor
    func homeNativeFlagsPartitionEveryVerifiedIdentityFieldAndPurgeOrigin() throws {
        let suite = "HomeFlags." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PiConversationPreferences(defaults: defaults)
        let origin = URL(string: "https://home.fixture.test")!
        let identity = HomeGateway.Identity(subject: "subject-a", scopeType: .personal, scopeId: "", workspaceId: "workspace-a", generation: "generation-a")
        preferences.saveHomeFlags(.init(favorite: true, pinned: true), identity: identity, origin: origin, sessionID: "shared-session")
        #expect(PiConversationPreferences(defaults: defaults).homeFlags(identity: identity, origin: origin, sessionID: "shared-session").pinned)
        let others = [
            HomeGateway.Identity(subject: "subject-b", scopeType: identity.scopeType, scopeId: identity.scopeId, workspaceId: identity.workspaceId, generation: identity.generation),
            HomeGateway.Identity(subject: identity.subject, scopeType: .enterprise, scopeId: "scope-b", workspaceId: identity.workspaceId, generation: identity.generation),
            HomeGateway.Identity(subject: identity.subject, scopeType: identity.scopeType, scopeId: identity.scopeId, workspaceId: "workspace-b", generation: identity.generation),
            HomeGateway.Identity(subject: identity.subject, scopeType: identity.scopeType, scopeId: identity.scopeId, workspaceId: identity.workspaceId, generation: "generation-b"),
        ]
        for other in others { #expect(preferences.homeFlags(identity: other, origin: origin, sessionID: "shared-session") == .init()) }
        #expect(preferences.homeFlags(identity: identity, origin: origin, sessionID: "other-session") == .init())
        #expect(preferences.homeFlags(identity: identity, origin: URL(string: "https://other.fixture.test")!, sessionID: "shared-session") == .init())
        preferences.removePiPreferences()
        #expect(preferences.homeFlags(identity: identity, origin: origin, sessionID: "shared-session").favorite)
        let authority = HomeAuthenticationAuthority(preferences: preferences)
        _ = authority.advance(origin: origin)
        #expect(preferences.homeFlags(identity: identity, origin: origin, sessionID: "shared-session") == .init())
    }

    @Test @MainActor
    func fullAndSelectedExportsContainOnlyAuthoritativeSelectionAndPaginatePDF() throws {
        let first = PiPresentationMessage(id: "user", role: .user, text: "Question", reasoning: "", tool: nil)
        let last = PiPresentationMessage(id: "assistant", role: .assistant, text: String(repeating: "A long report line.\n", count: 400) + "FINAL_SENTINEL", reasoning: "Observed reasoning", tool: nil)
        let selected = PiConversationExport.markdown(title: "Actual title", messages: [last])
        #expect(selected.contains("FINAL_SENTINEL"))
        #expect(!selected.contains("Question"))
        let full = PiConversationExport.markdown(title: "Actual title", messages: [first, last])
        #expect(full.contains("Question"))
        let pdf = try #require(PDFDocument(data: PiConversationExport.pdf(title: "Actual title", messages: [first, last])))
        #expect(pdf.pageCount > 1)
        let text = (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined()
        #expect(text.contains("Question"))
        #expect(text.contains("FINAL_SENTINEL"))
    }
}
