import Combine
import Storage
import UIKit
import AuthenticationServices

/// Home1 reuses the native timeline. No Pi ID, writer lease or send operation is
/// manufactured for the read-only Home contract.
final class HomeConversationHistoryController: UITableViewController {
    private let client: HomeGatewayClient
    private let handshake: HomeGateway.Handshake
    private let domainCoordinator: PiServerDomainCoordinator
    private var sessions: [PiJSONValue] = []
    private var task: Task<Void, Never>?
    private var isActive = true

    init(client: HomeGatewayClient, handshake: HomeGateway.Handshake, domainCoordinator: PiServerDomainCoordinator? = nil) {
        self.client = client; self.handshake = handshake
        self.domainCoordinator = domainCoordinator ?? PiServerDomainCoordinator()
        super.init(style: .plain)
        title = "Jonwork"
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    deinit { task?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemBackground
        client.onIdentityInvalidated = { [weak self] in
            guard let self else { return }
            self.isActive = false
            self.task?.cancel()
            self.sessions = []
            self.tableView.reloadData()
            self.navigationController?.presentedViewController?.dismiss(animated: false)
            self.navigationController?.setViewControllers([self], animated: false)
        }
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "history")
        navigationItem.rightBarButtonItem = .init(image: UIImage(systemName: "gearshape"), menu: UIMenu(children: [
            UIAction(title: String(localized: "Settings")) { [weak self] _ in self?.present(SettingController(), animated: true) },
            UIAction(title: String(localized: "Sign Out"), attributes: .destructive) { [weak self] _ in self?.confirmSignOut() },
        ]))
        let refresh = UIRefreshControl()
        refresh.addAction(UIAction { [weak self] _ in self?.loadHistory() }, for: .valueChanged)
        refreshControl = refresh
        loadHistory()
    }

    private func loadHistory() {
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.refreshControl?.endRefreshing() }
            do {
                let value = try await self.client.history()
                try Task.checkCancellation()
                guard self.isActive, value.identity == self.handshake.identity else { return }
                self.sessions = value.sessions
                self.sortSessions()
                self.tableView.reloadData()
            } catch is CancellationError { return }
            catch { if self.isActive, !Task.isCancelled { self.showError(error) } }
        }
    }

    private func sortSessions() {
        sessions.sort {
            let left = (try? client.nativeFlags(sessionID: $0["session_id"]?.stringValue ?? "")) ?? .init()
            let right = (try? client.nativeFlags(sessionID: $1["session_id"]?.stringValue ?? "")) ?? .init()
            if left.pinned != right.pinned { return left.pinned }
            if left.favorite != right.favorite { return left.favorite }
            return false
        }
    }

    override func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard isActive, let id = sessions[indexPath.row]["session_id"]?.stringValue,
              let flags = try? client.nativeFlags(sessionID: id) else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self, self.isActive else { return nil }
            return UIMenu(children: [
                UIAction(title: String(localized: flags.favorite ? "Remove Favorite" : "Favorite"), image: UIImage(systemName: "star"), state: flags.favorite ? .on : .off) { [weak self] _ in
                    self?.toggleFlag(sessionID: id, favorite: true)
                },
                UIAction(title: String(localized: flags.pinned ? "Unpin" : "Pin"), image: UIImage(systemName: "pin"), state: flags.pinned ? .on : .off) { [weak self] _ in
                    self?.toggleFlag(sessionID: id, favorite: false)
                },
            ])
        }
    }

    private func toggleFlag(sessionID: String, favorite: Bool) {
        guard isActive, var flags = try? client.nativeFlags(sessionID: sessionID) else { return }
        if favorite { flags.favorite.toggle() } else { flags.pinned.toggle() }
        do { try client.saveNativeFlags(flags, sessionID: sessionID) } catch { showError(error); return }
        sortSessions()
        tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        String(localized: "Home history is available. Sending and editing require the next server capability update.")
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { sessions.count }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "history", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = sessions[indexPath.row]["title"]?.stringValue
        if let id = sessions[indexPath.row]["session_id"]?.stringValue, let flags = try? client.nativeFlags(sessionID: id) {
            content.image = flags.pinned ? UIImage(systemName: "pin.fill") : flags.favorite ? UIImage(systemName: "star.fill") : nil
        }
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.textProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityTraits = .button
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let id = sessions[indexPath.row]["session_id"]?.stringValue else { return }
        task?.cancel()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let projection = try await self.client.snapshot(sessionID: id)
                try Task.checkCancellation()
                guard self.isActive, projection.identity == self.handshake.identity else { return }
                let controller = HomeConversationController(projection: projection, authorization: { [weak self] in self?.isActive == true })
                self.navigationController?.pushViewController(controller, animated: true)
            } catch is CancellationError { return }
            catch { if self.isActive, !Task.isCancelled { self.showError(error) } }
        }
    }

    private func confirmSignOut() {
        let alert = UIAlertController(title: String(localized: "Sign Out?"), message: String(localized: "Your sign-in information will be removed from this device."), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Sign Out"), style: .destructive) { [weak self] _ in
            guard let self else { return }
            self.dismiss(animated: false) {
                Task { @MainActor in await self.signOutConfirmed() }
            }
        })
        present(alert, animated: true)
    }
    func signOutConfirmed() async {
        isActive = false
        task?.cancel()
        sessions = []
        tableView.reloadData()
        navigationController?.setViewControllers([self], animated: false)
        do {
            try await domainCoordinator.signOut(homeClient: client, anchor: { [weak self] in self?.view.window ?? ASPresentationAnchor() })
            dismiss(animated: true)
        } catch {
            // Local state stays cleared even when remote revocation is pending.
            let alert = UIAlertController(title: String(localized: "Unable to Complete Action"), message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak self] _ in self?.dismiss(animated: true) })
            present(alert, animated: true)
        }
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(title: String(localized: "Unable to Complete Action"), message: error.localizedDescription, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        present(alert, animated: true)
    }
}

final class HomeConversationController: UIViewController {
    private let projection: HomeConversationProjection
    private let authorization: () -> Bool
    private let listView = MessageListView()
    private let transientID = "home.presentation." + UUID().uuidString
    private var projectedSession: ConversationSession?
    private var subscriptions: Set<AnyCancellable> = []

    init(projection: HomeConversationProjection, authorization: @escaping () -> Bool) {
        self.projection = projection; self.authorization = authorization
        super.init(nibName: nil, bundle: nil)
        title = projection.title
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let session = ConversationSessionManager.shared.session(for: transientID)
        projectedSession = session
        for value in projection.visibleMessages {
            let role: Message.Role = value.role == "user" ? .user : value.role == "assistant" ? .assistant : .system
            let message = session.appendTransientMessage(role: role)
            message.update(\.document, to: value.presentationText)
        }
        listView.readOnlyContentAuthorization = authorization
        listView.session = session
        view.addSubview(listView)
        listView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            listView.leadingAnchor.constraint(equalTo: view.leadingAnchor), listView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            listView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), listView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        navigationItem.rightBarButtonItem = .init(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: [
            UIAction(title: String(localized: "Conversation Activity")) { [weak self] _ in self?.showActivity() },
            UIAction(title: String(localized: "Export Conversation")) { [weak self] _ in
                guard let self, self.authorization() else { return }
                let messages = self.projection.visibleMessages.map(\.exportMessage)
                self.present(UINavigationController(rootViewController: PiConversationExportController(title: self.projection.title, messages: messages, authorization: self.authorization)), animated: true)
            },
        ]))
        session.notifyMessagesDidChange(scrolling: false)
        NotificationCenter.default.publisher(for: .homeAuthorizationDidChange).sink { [weak self] _ in
            guard let self, !self.authorization() else { return }
            self.purge()
            self.presentedViewController?.dismiss(animated: false)
        }.store(in: &subscriptions)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent || navigationController?.isBeingDismissed == true || !authorization() { purge() }
    }
    private func purge() {
        listView.speechSynthesizer.stopSpeaking(at: .immediate)
        if let session = projectedSession {
            for message in session.messages where session.isTransientMessage(message.objectId) { session.discardTransientMessage(messageIdentifier: message.objectId) }
            session.notifyMessagesDidChange(scrolling: false)
        }
        ConversationSessionManager.shared.invalidateSession(for: transientID)
    }
    private func showActivity() {
        guard authorization() else { return }
        navigationController?.pushViewController(HomeConversationActivityController(projection: projection, authorization: authorization), animated: true)
    }
}
