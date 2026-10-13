import AlertController
import AuthenticationServices
import Storage
import UIKit

extension SettingController.SettingContent {
    final class PiServerController: UITableViewController, UISearchResultsUpdating {
        private enum Section: Int, CaseIterable {
            case connection
            case repositories
            case sessions
        }

        private let domainCoordinator: PiServerDomainCoordinator
        private let gatewayConfiguration: PiGatewayDeploymentConfiguration
        private let autoConnect: Bool
        private let clientID = UUID().uuidString
        private var repositories: [PiRepositoryPresentation] = []
        private var sessions: [PiSessionPresentation] = []
        private var allSessions: [PiSessionPresentation] = []
        private var selectedRepository: String?
        private var isConnected = false
        private var isLoading = false
        private var isSigningOut = false
        private var isRestoringSession = false
        private var compatibilityError: String?
        private var connectTask: Task<Void, Never>?
        private var searchTask: Task<Void, Never>?
        private(set) var hasSavedToken = false
        private lazy var oauthClient = PiOAuthClient { [weak self] in
            self?.view.window ?? ASPresentationAnchor()
        }

        init(
            profileStore: PiServerProfileStore = PiServerProfileStore(),
            gatewayConfiguration: PiGatewayDeploymentConfiguration = .live,
            autoConnect: Bool = true
        ) {
            domainCoordinator = PiServerDomainCoordinator(profileStore: profileStore)
            self.gatewayConfiguration = gatewayConfiguration
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
            let searchController = UISearchController(searchResultsController: nil)
            searchController.searchResultsUpdater = self
            searchController.obscuresBackgroundDuringPresentation = false
            searchController.searchBar.placeholder = String(localized: "Search Conversations")
            navigationItem.searchController = searchController
            navigationItem.hidesSearchBarWhenScrolling = false
            do {
                if gatewayConfiguration.accepts(try domainCoordinator.savedProfile()) {
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
                searchTask?.cancel()
                searchTask = nil
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
            return compatibilityError ?? String(localized: "Sign in securely to access your workspace.")
        }

        func updateSearchResults(for searchController: UISearchController) {
            let query = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            searchTask?.cancel()
            sessions = query.isEmpty ? allSessions : allSessions.filter {
                ($0.name ?? "").localizedCaseInsensitiveContains(query)
                    || $0.id.localizedCaseInsensitiveContains(query)
            }
            tableView.reloadSections(IndexSet(integer: Section.sessions.rawValue), with: .none)
            guard !query.isEmpty, isConnected else { return }
            searchTask = Task { @MainActor [weak self] in
                do {
                    try await Task.sleep(for: .milliseconds(250))
                    guard let self,
                          navigationItem.searchController?.searchBar.text?
                              .trimmingCharacters(in: .whitespacesAndNewlines) == query
                    else { return }
                    sessions = try await domainCoordinator.searchSessions(query: query)
                    tableView.reloadSections(IndexSet(integer: Section.sessions.rawValue), with: .none)
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
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
                    configuration.text = compatibilityError == nil
                        ? (isLoading ? String(localized: "Signing In…") : String(localized: "Sign In"))
                        : String(localized: "Version Incompatible")
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

        override func tableView(
            _: UITableView,
            trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
        ) -> UISwipeActionsConfiguration? {
            guard Section(rawValue: indexPath.section) == .sessions,
                  sessions.indices.contains(indexPath.row),
                  !isLoading,
                  !isSigningOut
            else { return nil }
            let session = sessions[indexPath.row]
            let action = UIContextualAction(style: .destructive, title: String(localized: "Delete")) {
                [weak self] _, _, completion in
                self?.confirmDelete(session: session, completion: completion)
            }
            action.image = UIImage(systemName: "trash")
            let configuration = UISwipeActionsConfiguration(actions: [action])
            configuration.performsFirstActionWithFullSwipe = false
            return configuration
        }

        private func confirmDelete(
            session: PiSessionPresentation,
            completion: @escaping (Bool) -> Void
        ) {
            let alert = UIAlertController(
                title: String(localized: "Delete Conversation?"),
                message: String(localized: "This permanently deletes the conversation from the server."),
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
                completion(false)
            })
            alert.addAction(UIAlertAction(title: String(localized: "Delete"), style: .destructive) {
                [weak self] _ in
                guard let self else {
                    completion(false)
                    return
                }
                Task { @MainActor in
                    do {
                        self.setLoading(true)
                        defer { self.setLoading(false) }
                        self.apply(try await self.domainCoordinator.deleteSession(
                            sessionID: session.id,
                            clientID: self.clientID
                        ))
                        if let selectedRepository = self.selectedRepository,
                           let localID = PiSessionCoordinator.shared.conversationID(
                               sessionID: session.id,
                               repository: selectedRepository,
                               baseURL: self.gatewayConfiguration.baseURL
                           )
                        {
                            ConversationManager.shared.deleteConversation(identifier: localID)
                        }
                        completion(true)
                    } catch {
                        self.presentError(error)
                        completion(false)
                    }
                }
            })
            present(alert, animated: true)
        }

        private func connect() async {
            guard !isLoading, !isSigningOut else { return }
            do {
                let url = gatewayConfiguration.baseURL
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
                allSessions = []
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
                allSessions = []
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
            allSessions = presentation.sessions
            selectedRepository = presentation.selectedRepositoryID
            isConnected = presentation.isConnected
            compatibilityError = nil
            updateSearchResults(for: navigationItem.searchController ?? UISearchController())
        }

        private func reloadSessions() async {
            await selectRepository(selectedRepository)
        }

        private func openSession(resumeSessionID: String?) async {
            guard selectedRepository != nil, !isSigningOut else { return }
            setLoading(true)
            isRestoringSession = resumeSessionID != nil
            navigationItem.prompt = isRestoringSession ? String(localized: "Restoring conversation…") : nil
            defer {
                isRestoringSession = false
                navigationItem.prompt = nil
                setLoading(false)
            }
            do {
                let createdSession = try await domainCoordinator.createOrRestoreSession(
                    clientID: clientID,
                    resumeSessionID: resumeSessionID
                )
                let summary = sessions.first { $0.id == resumeSessionID }
                let existingID = PiSessionCoordinator.shared.conversationID(
                    sessionID: createdSession.sessionID,
                    repository: createdSession.repository,
                    baseURL: createdSession.baseURL
                )
                let conversation: Conversation
                if let existingID,
                   let existing = ConversationManager.shared.conversation(identifier: existingID)
                {
                    conversation = existing
                    ConversationManager.shared.editConversation(identifier: existingID) {
                        if let name = summary?.name?.nilIfBlank { $0.update(\.title, to: name) }
                    }
                } else {
                    conversation = ConversationManager.shared.createNewConversation { conversation in
                        conversation.update(
                            \.title,
                            to: summary?.name?.nilIfBlank
                                ?? String(localized: "New Conversation")
                        )
                        conversation.update(\.modelId, to: "pi:\(createdSession.sessionID)")
                        conversation.update(\.shouldAutoRename, to: false)
                    }
                    let localSession = ConversationSessionManager.shared.session(for: conversation.id)
                    for message in localSession.messages {
                        localSession.discard(messageIdentifier: message.objectId)
                    }
                    localSession.save()
                    localSession.notifyMessagesDidChange()
                }
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
            switch error as? PiServiceError {
            case .unsupportedGatewayVersion, .capabilityUnavailable:
                compatibilityError = String(localized: "Update the Jonwork server, then try again.")
                tableView.reloadData()
            default:
                break
            }
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
