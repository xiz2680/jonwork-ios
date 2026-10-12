import AlertController
import Storage
import UIKit

struct PiCreatedSession: Equatable, Sendable {
    let sessionID: String
    let repository: String
    let clientID: String
    let baseURL: URL

    static func create(
        service: any PiServiceProtocol,
        repository: String,
        resumePath: String?,
        clientID: String,
        baseURL: URL
    ) async throws -> Self {
        let sessionID = try await service.createSession(
            repository: repository,
            resumePath: resumePath,
            clientID: clientID
        )
        return .init(sessionID: sessionID, repository: repository, clientID: clientID, baseURL: baseURL)
    }

    @MainActor
    func bind(conversationID: Conversation.ID, coordinator: PiSessionCoordinator) {
        coordinator.bind(
            conversationID: conversationID,
            sessionID: sessionID,
            repository: repository,
            clientID: clientID,
            baseURL: baseURL
        )
    }
}

extension SettingController.SettingContent {
    final class PiServerController: UITableViewController {
        private enum Section: Int, CaseIterable {
            case connection
            case repositories
            case sessions
        }

        private let profileStore: PiServerProfileStore
        private let autoConnect: Bool
        private let clientID = UUID().uuidString
        private var service: (any PiServiceProtocol)?
        private var repositories: [String] = []
        private var sessions: [PiSessionSummary] = []
        private var selectedRepository: String?
        private var connectedBaseURL: URL?
        private var isLoading = false
        private(set) var hasSavedToken = false

        private lazy var serverField = makeField(
            placeholder: String(localized: "Pi server URL"),
            keyboardType: .URL,
            contentType: .URL
        )
        private lazy var tokenField = makeField(
            placeholder: String(localized: "Access token (optional)"),
            keyboardType: .default,
            contentType: .password,
            secure: true
        )

        init(profileStore: PiServerProfileStore = PiServerProfileStore(), autoConnect: Bool = true) {
            self.profileStore = profileStore
            self.autoConnect = autoConnect
            super.init(style: .insetGrouped)
            title = String(localized: "Pi Server")
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            tableView.keyboardDismissMode = .interactive
            tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
            navigationItem.largeTitleDisplayMode = .never
            do {
                if let profile = try profileStore.load() {
                    serverField.text = profile.baseURL.absoluteString
                    hasSavedToken = profile.token != nil
                    if autoConnect { Task { await connect() } }
                } else {
                    serverField.text = "http://localhost:4317"
                }
            } catch {
                presentError(error)
            }
        }

        override func numberOfSections(in _: UITableView) -> Int {
            Section.allCases.count
        }

        override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
            switch Section(rawValue: section) {
            case .connection: 4
            case .repositories: max(repositories.count, 1) + (selectedRepository == nil ? 0 : 1)
            case .sessions: max(sessions.count, 1)
            case nil: 0
            }
        }

        override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
            switch Section(rawValue: section) {
            case .connection: String(localized: "Connection")
            case .repositories: String(localized: "Repositories")
            case .sessions: String(localized: "Recent Sessions")
            case nil: nil
            }
        }

        override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
            guard Section(rawValue: section) == .connection else { return nil }
            return String(localized: "Tokens are stored in Keychain. Leave the token field blank to keep the saved token. HTTPS is required outside local development.")
        }

        override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
            var configuration = cell.defaultContentConfiguration()
            configuration.secondaryTextProperties.color = .secondaryLabel
            cell.accessoryType = .none
            cell.accessoryView = nil
            cell.selectionStyle = .default
            cell.contentView.subviews.filter { $0 is UITextField }.forEach { $0.removeFromSuperview() }

            switch Section(rawValue: indexPath.section) {
            case .connection:
                if indexPath.row == 0 {
                    configure(cell, with: serverField)
                } else if indexPath.row == 1 {
                    configure(cell, with: tokenField)
                } else if indexPath.row == 2 {
                    configuration.text = isLoading ? String(localized: "Connecting…") : String(localized: "Connect")
                    configuration.textProperties.color = isLoading ? .secondaryLabel : .tintColor
                    configuration.image = UIImage(systemName: isLoading ? "arrow.triangle.2.circlepath" : "network")
                    cell.selectionStyle = isLoading ? .none : .default
                } else {
                    configuration.text = String(localized: "Remove Saved Token")
                    configuration.textProperties.color = hasSavedToken ? .systemRed : .secondaryLabel
                    configuration.image = UIImage(systemName: "key.slash")
                    cell.selectionStyle = hasSavedToken ? .default : .none
                }
            case .repositories:
                if repositories.isEmpty {
                    configuration.text = service == nil
                        ? String(localized: "Connect to load repositories")
                        : String(localized: "No repositories found")
                    configuration.textProperties.color = .secondaryLabel
                    cell.selectionStyle = .none
                } else if indexPath.row < repositories.count {
                    let repository = repositories[indexPath.row]
                    configuration.text = URL(fileURLWithPath: repository).lastPathComponent
                    configuration.secondaryText = repository
                    cell.accessoryType = repository == selectedRepository ? .checkmark : .none
                } else {
                    configuration.text = String(localized: "New Pi Conversation")
                    configuration.textProperties.color = .tintColor
                    configuration.image = UIImage(systemName: "plus.bubble")
                }
            case .sessions:
                if sessions.isEmpty {
                    configuration.text = service == nil
                        ? String(localized: "Connect to load sessions")
                        : String(localized: "No recent sessions")
                    configuration.textProperties.color = .secondaryLabel
                    cell.selectionStyle = .none
                } else {
                    let session = sessions[indexPath.row]
                    configuration.text = session.name?.nilIfBlank
                        ?? session.firstMessage.nilIfBlank
                        ?? String(localized: "Untitled")
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
            case .connection where indexPath.row == 2:
                Task { await connect() }
            case .connection where indexPath.row == 3 && hasSavedToken:
                confirmRemoveSavedToken()
            case .repositories where !repositories.isEmpty && indexPath.row < repositories.count:
                selectedRepository = repositories[indexPath.row]
                Task { await reloadSessions() }
            case .repositories where selectedRepository != nil && indexPath.row == repositories.count:
                Task { await openSession(resumePath: nil) }
            case .sessions where !sessions.isEmpty:
                Task { await openSession(resumePath: sessions[indexPath.row].path) }
            default:
                break
            }
        }

        private func connect() async {
            guard !isLoading else { return }
            view.endEditing(true)
            do {
                guard let rawURL = serverField.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                      let url = URL(string: rawURL)
                else { throw PiServiceError.invalidServerURL }
                let enteredToken = tokenField.text?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
                let savedProfile = try profileStore.load()
                let token = enteredToken ?? (savedProfile?.baseURL == url ? savedProfile?.token : nil)
                let configuration = try PiServerConfiguration(baseURL: url, token: token)
                setLoading(true)
                defer { setLoading(false) }
                let service = PiService(configuration: configuration)
                try await service.health()
                let repositories = try await service.listRepositories()
                try profileStore.save(baseURL: url, token: enteredToken)
                hasSavedToken = try profileStore.hasSavedToken()
                self.service = service
                connectedBaseURL = configuration.baseURL
                self.repositories = repositories
                selectedRepository = repositories.first
                await reloadSessions()
            } catch {
                service = nil
                connectedBaseURL = nil
                repositories = []
                sessions = []
                selectedRepository = nil
                tableView.reloadData()
                presentError(error)
            }
        }

        private func confirmRemoveSavedToken() {
            let alert = AlertViewController(
                title: "Remove Saved Token?",
                message: "The saved token will be deleted from this device."
            ) { context in
                context.addAction(title: "Cancel") { context.dispose() }
                context.addAction(title: "Remove Token", attribute: .accent) { [weak self] in
                    context.dispose()
                    self?.removeSavedToken()
                }
            }
            present(alert, animated: true)
        }

        func removeSavedToken() {
            do {
                try profileStore.removeSavedToken()
                tokenField.text = nil
                hasSavedToken = false
                tableView.reloadSections(IndexSet(integer: Section.connection.rawValue), with: .none)
            } catch {
                presentError(error)
            }
        }

        private func reloadSessions() async {
            guard let service else { return }
            do {
                sessions = try await service.listSessions(repository: selectedRepository)
                tableView.reloadSections(
                    IndexSet([Section.repositories.rawValue, Section.sessions.rawValue]),
                    with: .automatic
                )
            } catch {
                presentError(error)
            }
        }

        private func openSession(resumePath: String?) async {
            guard let service, let repository = selectedRepository, let connectedBaseURL else { return }
            setLoading(true)
            defer { setLoading(false) }
            do {
                let createdSession = try await PiCreatedSession.create(
                    service: service,
                    repository: repository,
                    resumePath: resumePath,
                    clientID: clientID,
                    baseURL: connectedBaseURL
                )
                let summary = sessions.first { $0.path == resumePath }
                let conversation = ConversationManager.shared.createNewConversation({ conversation in
                    conversation.update(
                        \.title,
                        to: summary?.name?.nilIfBlank
                            ?? summary?.firstMessage.nilIfBlank
                            ?? String(localized: "New Pi Conversation")
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
                createdSession.bind(conversationID: conversation.id, coordinator: .shared)
                ChatSelection.shared.select(conversation.id, options: [.collapseSidebar, .focusEditor])
                dismiss(animated: true)
            } catch {
                presentError(error)
            }
        }

        private func setLoading(_ loading: Bool) {
            isLoading = loading
            tableView.reloadSections(IndexSet(integer: Section.connection.rawValue), with: .none)
        }

        private func configure(_ cell: UITableViewCell, with field: UITextField) {
            cell.selectionStyle = .none
            cell.contentView.addSubview(field)
            field.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
                field.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
                field.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 8),
                field.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -8),
            ])
        }

        private func makeField(
            placeholder: String,
            keyboardType: UIKeyboardType,
            contentType: UITextContentType,
            secure: Bool = false
        ) -> UITextField {
            let field = UITextField()
            field.placeholder = placeholder
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            field.keyboardType = keyboardType
            field.textContentType = contentType
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
            field.isSecureTextEntry = secure
            field.clearButtonMode = .whileEditing
            return field
        }

        private func presentError(_ error: Error) {
            let alert = AlertViewController(
                title: "Pi",
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
