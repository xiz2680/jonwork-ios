@testable import Jonwork
import Foundation
import Testing

@MainActor
struct PiSharingConsentTests {
    private func scope(
        workspace: String = "https://workspace.example",
        repository: String = "project",
        connection: String = "connection",
        provider: String = "provider",
        model: String = "model"
    ) -> PiSharingConsent.Scope {
        .init(workspaceURL: URL(string: workspace)!, repository: repository,
              connectionID: connection, provider: provider, modelID: model)
    }

    @Test
    func cancellationPreservesDraftAndDoesNotStartUploadOrSend() async {
        let suite = "PiSharingConsentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = PiSharingConsent(defaults: defaults)
        let recipient = scope()
        var draft = "Unsent private text"
        var uploadCalls = 0
        var sendCalls = 0
        let sent = await consent.perform(recipient, currentScope: { recipient }, requestPermission: { false }, operation: { _ in
            uploadCalls += 1
            sendCalls += 1
            draft = ""
            return true
        })
        #expect(!sent)
        #expect(draft == "Unsent private text")
        #expect(uploadCalls == 0 && sendCalls == 0)
        #expect(!consent.isAuthorized(recipient))
    }

    @Test
    func grantSurvivesRelaunchButDoesNotAuthorizeOtherRecipients() async {
        let suite = "PiSharingConsentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let recipient = scope()
        let consent = PiSharingConsent(defaults: defaults)
        #expect(await consent.authorize(recipient, currentScope: { recipient }, requestPermission: { true }))
        let relaunched = PiSharingConsent(defaults: defaults)
        #expect(relaunched.isAuthorized(recipient))
        for changed in [scope(workspace: "https://other.example"), scope(repository: "other"),
                        scope(connection: "other"), scope(provider: "other"), scope(model: "other")] {
            #expect(!relaunched.isAuthorized(changed))
        }
        #expect(await relaunched.authorize(recipient, currentScope: { recipient }, requestPermission: {
            Issue.record("A saved grant must not ask again for the same recipient")
            return false
        }))
        let stored = defaults.stringArray(forKey: "Jonwork.AISharingConsent.v1")!
        #expect(stored.count == 1 && stored[0].count == 64)
        #expect(!stored[0].contains("workspace") && !stored[0].contains("connection"))
    }

    @Test
    func modelChangeWhilePermissionIsShownCannotAuthorizeTheNewModel() async {
        let suite = "PiSharingConsentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = PiSharingConsent(defaults: defaults)
        let original = scope()
        var current = original
        let permitted = await consent.authorize(original, currentScope: { current }, requestPermission: {
            current = scope(model: "changed-during-dialog")
            return true
        })
        #expect(!permitted)
        #expect(!consent.isAuthorized(original) && !consent.isAuthorized(current))
    }

    @Test
    func revocationWhilePermissionIsShownCannotBeUndoneByOldDialog() async {
        let suite = "PiSharingConsentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = PiSharingConsent(defaults: defaults)
        let recipient = scope()
        #expect(!(await consent.authorize(recipient, currentScope: { recipient }, requestPermission: {
            consent.revokeAll()
            return true
        })))
        #expect(!consent.isAuthorized(recipient))
    }

    @Test
    func revocationRequiresNewExplicitPermission() async {
        let suite = "PiSharingConsentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = PiSharingConsent(defaults: defaults)
        let recipient = scope()
        #expect(await consent.authorize(recipient, currentScope: { recipient }, requestPermission: { true }))
        consent.revokeAll()
        var requests = 0
        #expect(!(await consent.authorize(recipient, currentScope: { recipient }, requestPermission: {
            requests += 1
            return false
        })))
        #expect(requests == 1)
        #expect(!consent.isAuthorized(recipient))
    }

    @Test
    func oldFenceStaysInvalidAfterTheSameRecipientIsAuthorizedAgain() async throws {
        let suite = "PiSharingConsentTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let consent = PiSharingConsent(defaults: defaults)
        let recipient = scope()
        #expect(await consent.authorize(recipient, currentScope: { recipient }, requestPermission: { true }))
        let oldFence = try #require(consent.fence(for: recipient))
        consent.revokeAll()
        #expect(await consent.authorize(recipient, currentScope: { recipient }, requestPermission: { true }))
        let newFence = try #require(consent.fence(for: recipient))
        #expect(!oldFence.isValid(for: recipient))
        #expect(newFence.isValid(for: recipient))
    }
}
