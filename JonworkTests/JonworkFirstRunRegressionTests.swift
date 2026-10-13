@testable import Jonwork
import Foundation
import Testing
import UIKit

@Suite(.serialized)
struct JonworkFirstRunRegressionTests {
    @Test
    @MainActor
    func `Jonwork entry bypasses the Jonwork settings surface`() throws {
        let presented = SettingController.makeJonworkWorkspaceController()
        let navigation = try #require(presented as? UINavigationController)

        #expect(navigation.modalPresentationStyle == .fullScreen)
        #expect(navigation.viewControllers.count >= 1)
        #expect(navigation.viewControllers.first is SettingController.SettingContent.PiServerController)
        #expect(!(navigation.viewControllers.first is SettingController.SettingContent))
    }

    @Test
    @MainActor
    func `fresh workspace entry shows native sign in before presentation`() throws {
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let workspace = SettingController.SettingContent.PiServerController(
            profileStore: PiServerProfileStore(defaults: defaults, credentials: EmptyPiCredentialStore()),
            autoConnect: false
        )
        let navigation = UINavigationController(rootViewController: workspace)
        workspace.prepareForEntry()
        workspace.prepareForEntry()
        #expect(navigation.topViewController is PiSignInViewController)
        #expect(navigation.viewControllers.count == 2)
        #expect(workspace.presentedViewController == nil)
        let signIn = try #require(navigation.topViewController as? PiSignInViewController)
        signIn.loadViewIfNeeded()
        let backButton = try #require(descendant(identifier: "PiSignInBackButton", in: signIn.view) as? UIButton)
        #expect(backButton.isHidden)
    }

    @Test
    @MainActor
    func `compatible saved credentials bypass the login form`() throws {
        let suiteName = "JonworkFirstRunRegressionTests.saved.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configuration = PiGatewayDeploymentConfiguration.live
        let profileStore = PiServerProfileStore(defaults: defaults, credentials: SavedPiCredentialStore())
        try profileStore.save(baseURL: configuration.baseURL, token: "fixture-token")
        let workspace = SettingController.SettingContent.PiServerController(
            profileStore: profileStore,
            gatewayConfiguration: configuration,
            autoConnect: false
        )
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.setNavigationBarHidden(true, animated: false)
        SettingController.configureJonworkWorkspace(in: navigation, workspace: workspace)
        #expect(!navigation.isNavigationBarHidden)
        #expect(workspace.hasSavedToken)
        #expect(navigation.topViewController === workspace)
        #expect(navigation.viewControllers.count == 1)
    }

    @Test
    func `onboarding appears once before login including installs that previously skipped it`() throws {
        let suiteName = "JonworkFirstRunRegressionTests.onboarding.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(WelcomeExperience.shouldPresent(in: defaults))
        defaults.set("0", forKey: "WelcomeExperience.lastSeenVersion")
        #expect(WelcomeExperience.shouldPresent(in: defaults))
        WelcomeExperience.markPresented(in: defaults)
        #expect(!WelcomeExperience.shouldPresent(in: defaults))
    }

    @Test
    @MainActor
    func `completing all guide pages replaces the guide with one native login stack`() throws {
        let suiteName = "JonworkFirstRunRegressionTests.guideRoute.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let workspace = SettingController.SettingContent.PiServerController(
            profileStore: PiServerProfileStore(defaults: defaults, credentials: EmptyPiCredentialStore()),
            autoConnect: false
        )
        let welcome = WelcomePageViewController()
        let navigation = UINavigationController(rootViewController: welcome)
        welcome.dismissesOnCompletion = false
        welcome.onComplete = {
            SettingController.configureJonworkWorkspace(in: navigation, workspace: workspace)
        }
        welcome.loadViewIfNeeded()
        let button = try #require(descendant(identifier: "JonworkOnboardingContinue", in: welcome.view) as? UIButton)
        for _ in 0 ..< 3 { button.sendActions(for: .touchUpInside) }
        #expect(navigation.topViewController is PiSignInViewController)
        #expect(navigation.viewControllers.count == 2)
        #expect(!navigation.viewControllers.contains(where: { $0 === welcome }))
        #expect(welcome.onComplete == nil)
        workspace.prepareForEntry()
        #expect(navigation.viewControllers.count == 2)
    }

    @Test
    func `Jonwork surface policy never admits an unbound local conversation path`() {
        #expect(!JonworkSurfacePolicy.allowsLegacyConversations)
        #expect(!JonworkSurfacePolicy.shouldCreateInitialConversation(isConversationListEmpty: true))
        #expect(!JonworkSurfacePolicy.permitsConversation(hasJonworkBinding: false))
        #expect(!JonworkSurfacePolicy.permitsLegacyProviderAccess(hasJonworkBinding: false))
    }

    @Test
    @MainActor
    func `workspace sign in stays in its existing navigation stack`() async throws {
        let suiteName = "JonworkFirstRunRegressionTests.navigation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let configuration = PiGatewayDeploymentConfiguration(
            environment: .debug,
            baseURL: PiGatewayDeploymentConfiguration.Environment.debug.requiredBaseURL
        )
        let workspace = SettingController.SettingContent.PiServerController(
            profileStore: PiServerProfileStore(
                defaults: defaults,
                credentials: EmptyPiCredentialStore()
            ),
            gatewayConfiguration: configuration,
            autoConnect: false
        )
        let navigation = UINavigationController(rootViewController: workspace)
        navigation.loadViewIfNeeded()
        workspace.loadViewIfNeeded()

        workspace.tableView(
            workspace.tableView,
            didSelectRowAt: IndexPath(row: 0, section: 0)
        )
        try await waitUntil {
            navigation.topViewController is PiSignInViewController
        }

        #expect(navigation.viewControllers.count == 2)
        #expect(navigation.topViewController is PiSignInViewController)
        #expect(workspace.presentedViewController == nil)
        #expect(navigation.presentedViewController == nil)
    }

    @Test
    @MainActor
    func `sign in collects no password and starts shared Jonwork authorization`() throws {
        let controller = PiSignInViewController()
        controller.loadViewIfNeeded()
        #expect(descendant(identifier: "PiEmailField", in: controller.view) == nil)
        #expect(descendant(identifier: "PiPasswordField", in: controller.view) == nil)
        let button = try #require(descendant(identifier: "PiNativeSignInButton", in: controller.view) as? UIButton)
        var submissions = 0
        controller.onSubmit = { submissions += 1 }
        button.sendActions(for: .touchUpInside)
        #expect(submissions == 1)
        controller.setLoading(true)
        button.sendActions(for: .touchUpInside)
        #expect(submissions == 1)
        #expect(!button.isEnabled)
        controller.setLoading(false)
        button.sendActions(for: .touchUpInside)
        #expect(submissions == 2)
        #expect(button.isEnabled)
    }

    @Test
    @MainActor
    func `retryable authorization failure can be retried without stored credentials`() throws {
        let controller = PiSignInViewController()
        controller.loadViewIfNeeded()
        let error = try #require(descendant(identifier: "PiSignInError", in: controller.view) as? UILabel)
        controller.setLoading(true)
        controller.showError(PiServiceError.networkUnavailable)
        controller.setLoading(false)
        #expect(!error.isHidden)
        let button = try #require(descendant(identifier: "PiNativeSignInButton", in: controller.view) as? UIButton)
        var submitted = false
        controller.onSubmit = { submitted = true }
        button.sendActions(for: .touchUpInside)
        #expect(submitted)
        #expect(error.isHidden)
    }

    @Test
    @MainActor
    func `browser obscuring sign in preserves authorization but explicit dismissal cancels once`() {
        let controller = PiSignInViewController()
        var cancellations = 0
        controller.onCancelAuthentication = { cancellations += 1 }
        controller.authenticationPresentationDidDisappear(isLeaving: false)
        #expect(cancellations == 0)
        #expect(controller.onCancelAuthentication != nil)
        controller.authenticationPresentationDidDisappear(isLeaving: true)
        controller.authenticationPresentationDidDisappear(isLeaving: true)
        #expect(cancellations == 1)
        #expect(controller.onCancelAuthentication == nil)
    }

    @Test
    @MainActor
    func `full screen sign in keeps a visible escape control`() throws {
        let controller = PiSignInViewController()
        controller.loadViewIfNeeded()

        let backButton = try #require(
            descendant(identifier: "PiSignInBackButton", in: controller.view) as? UIButton
        )
        #expect(backButton.isHidden == false)
        #expect(backButton.isEnabled)
    }

    @MainActor
    private func textField(identifier: String, in root: UIView) throws -> UITextField {
        try #require(descendant(identifier: identifier, in: root) as? UITextField)
    }

    @MainActor
    private func descendant(identifier: String, in root: UIView) -> UIView? {
        if root.accessibilityIdentifier == identifier { return root }
        for subview in root.subviews {
            if let match = descendant(identifier: identifier, in: subview) { return match }
        }
        return nil
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            await Task.yield()
        }
        Issue.record("Timed out waiting for navigation state")
    }
}

private struct EmptyPiCredentialStore: PiCredentialStoring, Sendable {
    func saveToken(_: String, server _: URL) throws {}
    func token(server _: URL) throws -> String? { nil }
    func removeToken(server _: URL) throws {}
    func saveOAuthTokens(_: PiOAuthTokens, server _: URL) throws {}
    func oauthTokens(server _: URL) throws -> PiOAuthTokens? { nil }
    func removeOAuthTokens(server _: URL) throws {}
}

private struct SavedPiCredentialStore: PiCredentialStoring, Sendable {
    func saveToken(_: String, server _: URL) throws {}
    func token(server _: URL) throws -> String? { "fixture-token" }
    func removeToken(server _: URL) throws {}
    func saveOAuthTokens(_: PiOAuthTokens, server _: URL) throws {}
    func oauthTokens(server _: URL) throws -> PiOAuthTokens? { nil }
    func removeOAuthTokens(server _: URL) throws {}
}
