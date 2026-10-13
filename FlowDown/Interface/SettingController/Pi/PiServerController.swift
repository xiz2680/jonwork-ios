import AlertController
import AuthenticationServices
import Storage
import UIKit

extension SettingController.SettingContent {
    final class PiServerController: UITableViewController {
        static let defaultBaseURL = URL(string: "https://agent.jonwork.com")!

        static func connectionBaseURL(savedProfile: PiServerProfile?) -> URL {
            savedProfile?.baseURL ?? defaultBaseURL
        }

        private enum Section: Int, CaseIterable {
            case connection
            case repositories
            case sessions
        }

        private let domainCoordinator: PiServerDomainCoordinator
        private let autoConnect: Bool
        private let clientID = UUID().uuidString
        private var repositories: [PiRepositoryPresentation] = []
        private var sessions: [PiSessionPresentation] = []
        private var selectedRepository: String?
        private var isConnected = false
        private var isLoading = false
        private var isSigningOut = false
        private var connectTask: Task<Void, Never>?
        private(set) var hasSavedToken = false
        private lazy var oauthClient = PiOAuthClient { [weak self] in
            self?.view.window ?? ASPresentationAnchor()
        }

        init(profileStore: PiServerProfileStore = PiServerProfileStore(), autoConnect: Bool = true) {
            domainCoordinator = PiServerDomainCoordinator(profileStore: profileStore)
            self.autoConnect = autoConnect
            super.init(style: .insetGrouped)
            title = String(localized: "Jonwork Workspace")
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
            navigationItem.largeTitleDisplayMode = .never
            do {
                if try domainCoordinator.savedProfile() != nil {
                    hasSavedToken = try domainCoordinator.hasSavedCredentials()
                    if autoConnect { startConnect() }
                }
            } catch {
                presentError(error)
            }
        }

        override func numberOfSections(in _: UITableView) -> Int {
            Section.allCases.count
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if isMovingFromParent || navigationController?.isBeingDismissed == true {
                connectTask?.cancel()
                connectTask = nil
            }
        }

        override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
            switch Section(rawValue: section) {
            case .connection: 2
            case .repositories: max(repositories.count, 1) + (selectedRepository == nil ? 0 : 1)
            case .sessions: max(sessions.count, 1)
            case nil: 0
            }
        }

        override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
            switch Section(rawValue: section) {
            case .connection: String(localized: "Connection")
            case .repositories: String(localized: "Projects")
            case .sessions: String(localized: "Recent Conversations")
            case nil: nil
            }
        }

        override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
            guard Section(rawValue: section) == .connection else { return nil }
            return String(localized: "Sign in securely to access your workspace.")
        }

        override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var configuration = cell.defaultContentConfiguration()
            configuration.secondaryTextProperties.color = .secondaryLabel
            cell.accessoryType = .none
            cell.accessoryView = nil
            cell.selectionStyle = .default

            switch Section(rawValue: indexPath.section) {
            case .connection:
                if indexPath.row == 0 {
                    configuration.text = isLoading ? String(localized: "Signing In…") : String(localized: "Sign In")
                    configuration.textProperties.color = isLoading || isSigningOut ? .secondaryLabel : .tintColor
                    configuration.image = UIImage(systemName: isLoading ? "arrow.triangle.2.circlepath" : "network")
                    cell.selectionStyle = isLoading || isSigningOut ? .none : .default
                } else {
                    configuration.text = String(localized: "Sign Out")
                    configuration.textProperties.color = hasSavedToken ? .systemRed : .secondaryLabel
                    configuration.image = UIImage(systemName: "key.slash")
                    cell.selectionStyle = hasSavedToken && !isSigningOut ? .default : .none
                }
            case .repositories:
                if repositories.isEmpty {
                    configuration.text = !isConnected
                        ? String(localized: "Sign in to load projects")
                        : String(localized: "No projects found")
                    configuration.textProperties.color = .secondaryLabel
                    cell.selectionStyle = .none
                } else if indexPath.row < repositories.count {
                    let repository = repositories[indexPath.row]
                    configuration.text = repository.displayName
                    cell.accessoryType = repository.id == selectedRepository ? .checkmark : .none
                } else {
                    configuration.text = String(localized: "New Conversation")
                    configuration.textProperties.color = .tintColor
                    configuration.image = UIImage(systemName: "plus.bubble")
                }
            case .sessions:
                if sessions.isEmpty {
                    configuration.text = !isConnected
                        ? String(localized: "Sign in to load conversations")
                        : String(localized: "No recent conversations")
                    configuration.textProperties.color = .secondaryLabel
                    cell.selectionStyle = .none
                } else {
                    let session = sessions[indexPath.row]
                    configuration.text = session.name?.nilIfBlank ?? String(localized: "Untitled")
                    let messageCountKey: String.LocalizationValue = "\(session.messageCount) messages"
                    configuration.secondaryText = session.isRunning
                        ? String(localized: "Live") + " · " + String(localized: messageCountKey)
                        : String(localized: messageCountKey)
                    configuration.image = UIImage(systemName: session.isRunning ? "waveform" : "bubble.left.and.bubble.right")
                    cell.accessoryType = .disclosureIndicator
                }
            case nil:
                break
            }
            cell.contentConfiguration = configuration
            return cell
        }

        override func tableView(_: UITableView, didSelectRowAt indexPath: IndexPath) {
            tableView.deselectRow(at: indexPath, animated: true)
            switch Section(rawValue: indexPath.section) {
            case .connection where indexPath.row == 0:
                startConnect()
            case .connection where indexPath.row == 1 && hasSavedToken && !isSigningOut:
                confirmRemoveSavedToken()
            case .repositories where !repositories.isEmpty && indexPath.row < repositories.count:
                selectedRepository = repositories[indexPath.row].id
                Task { await selectRepository(selectedRepository) }
            case .repositories where selectedRepository != nil && indexPath.row == repositories.count:
                Task { await openSession(resumeSessionID: nil) }
            case .sessions where !sessions.isEmpty:
                Task { await openSession(resumeSessionID: sessions[indexPath.row].id) }
            default:
                break
            }
        }

        private func connect() async {
            guard !isLoading, !isSigningOut else { return }
            do {
                let url = Self.connectionBaseURL(savedProfile: try domainCoordinator.savedProfile())
                setLoading(true)
                defer { setLoading(false) }
                let presentation = try await domainCoordinator.authenticate(baseURL: url, authorizer: oauthClient)
                apply(presentation)
                hasSavedToken = try domainCoordinator.hasSavedCredentials()
            } catch is CancellationError {
                return
            } catch {
                isConnected = false
                repositories = []
                sessions = []
                selectedRepository = nil
                tableView.reloadData()
                presentError(error)
            }
        }

        private func startConnect() {
            guard !isSigningOut else { return }
            connectTask?.cancel()
            connectTask = Task { @MainActor [weak self] in
                await self?.connect()
            }
        }

        private func confirmRemoveSavedToken() {
            let alert = AlertViewController(
                title: "Sign Out?",
                message: "Your sign-in information will be removed from this device."
            ) { context in
                context.addAction(title: "Cancel") { context.dispose() }
                context.addAction(title: "Sign Out", attribute: .accent) { [weak self] in
                    context.dispose()
                    Task { await self?.removeSavedToken() }
                }
            }
            present(alert, animated: true)
        }

        func removeSavedToken() async {
            guard !isSigningOut else { return }
            isSigningOut = true
            tableView.reloadSections(IndexSet(integer: Section.connection.rawValue), with: .none)
            connectTask?.cancel()
            connectTask = nil
            defer {
                isSigningOut = false
                isConnected = false
                repositories = []
                sessions = []
                selectedRepository = nil
                hasSavedToken = (try? domainCoordinator.hasSavedCredentials()) ?? false
                tableView.reloadData()
            }
            do {
                try await domainCoordinator.signOut()
            } catch {
                presentError(error)
            }
        }

        private func selectRepository(_ repositoryID: String?) async {
            guard let repositoryID, !isSigningOut else { return }
            do {
                apply(try await domainCoordinator.selectRepository(repositoryID))
            } catch is CancellationError {
                return
            } catch {
                presentError(error)
            }
        }

        private func apply(_ presentation: PiServerPresentation) {
            repositories = presentation.repositories
            sessions = presentation.sessions
            selectedRepository = presentation.selectedRepositoryID
            isConnected = presentation.isConnected
            tableView.reloadData()
        }

        private func reloadSessions() async {
            await selectRepository(selectedRepository)
        }

        private func openSession(resumeSessionID: String?) async {
            guard selectedRepository != nil, !isSigningOut else { return }
            setLoading(true)
            defer { setLoading(false) }
            do {
                let createdSession = try await domainCoordinator.createOrRestoreSession(
                    clientID: clientID,
                    resumeSessionID: resumeSessionID
                )
                let summary = sessions.first { $0.id == resumeSessionID }
                let conversation = ConversationManager.shared.createNewConversation({ conversation in
                    conversation.update(
                        \.title,
                        to: summary?.name?.nilIfBlank
                            ?? String(localized: "New Conversation")
                    )
                    conversation.update(\.modelId, to: "pi:\(createdSession.sessionID)")
                    conversation.update(\.shouldAutoRename, to: false)
                })
                let localSession = ConversationSessionManager.shared.session(for: conversation.id)
                for message in localSession.messages {
                    localSession.discard(messageIdentifier: message.objectId)
                }
                localSession.save()
                localSession.notifyMessagesDidChange()
                createdSession.bind(conversationID: conversation.id)
                ChatSelection.shared.select(conversation.id, options: [.collapseSidebar, .focusEditor])
                dismiss(animated: true)
            } catch is CancellationError {
                return
            } catch {
                presentError(error)
            }
        }

        private func setLoading(_ loading: Bool) {
            isLoading = loading
            tableView.reloadSections(IndexSet(integer: Section.connection.rawValue), with: .none)
        }

        private func presentError(_ error: Error) {
            let alert = AlertViewController(
                title: "Jonwork",
                message: "\(error.localizedDescription)"
            ) { context in
                context.allowSimpleDispose()
                context.addAction(title: "OK", attribute: .accent) { context.dispose() }
            }
            present(alert, animated: true)
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
