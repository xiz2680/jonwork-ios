import Combine
import QuickLook
import Storage
import UIKit

final class PiConversationActivityController: UITableViewController {
    private let conversationID: Conversation.ID
    private let presentationAuthorization: PiPresentationAuthorization
    private var subscriptions: Set<AnyCancellable> = []
    private var previewSource: SingleItemDataSource?
    private var previewTask: Task<Void, Never>?

    init(conversationID: Conversation.ID) {
        self.conversationID = conversationID
        presentationAuthorization = PiPresentationAuthorization(conversationID: conversationID)
        super.init(style: .plain)
        title = String(localized: "Conversation Activity")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "activity")
        tableView.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = .init(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        NotificationCenter.default.publisher(for: .piSessionDidChange).merge(with: NotificationCenter.default.publisher(for: .piAuthenticationEpochDidChange)).receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            guard self.isCurrent else { self.previewTask?.cancel(); self.previewSource = nil;
                self.navigationController?.viewControllers.compactMap { $0 as? TextViewerController }.forEach { $0.text = "" }
                self.tableView.reloadData(); self.dismiss(animated: true); return }
            self.tableView.reloadData()
        }.store(in: &subscriptions)
    }

    deinit { previewTask?.cancel() }
    private var isCurrent: Bool { presentationAuthorization.isCurrent }
    private var state: PiConversationState? { isCurrent ? PiSessionCoordinator.shared.viewState(for: conversationID)?.conversation : nil }
    private var tools: [PiToolPresentation] { state?.messages.compactMap(\.tool) ?? [] }
    private var images: [URL] { Array(Set((state?.messages ?? []).flatMap { MarkdownOutputImages.urls(in: $0.text) })).sorted { $0.absoluteString < $1.absoluteString } }

    override func numberOfSections(in tableView: UITableView) -> Int { 4 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard state != nil else { return 0 }
        switch section {
        case 0: return 1
        case 1: return state?.attachmentIDs.count ?? 0
        case 2: return images.count
        default: return tools.count
        }
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 1: String(localized: "Attachments")
        case 2: String(localized: "Results")
        case 3: String(localized: "Execution")
        default: nil
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "activity", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        cell.accessoryType = .none
        cell.selectionStyle = .none
        switch indexPath.section {
        case 0:
            content.text = String(localized: state?.isStreaming == true ? "Working…" : "Conversation")
            content.secondaryText = state?.title
            content.image = UIImage(systemName: state?.isStreaming == true ? "hourglass" : "bubble.left.and.bubble.right")
        case 1:
            let id = state?.attachmentIDs[indexPath.row] ?? ""
            content.text = state?.messages.first(where: { $0.id == "attachment-\(id)" })?.text ?? id
            content.image = UIImage(systemName: "paperclip")
        case 2:
            content.text = images[indexPath.row].lastPathComponent
            content.image = UIImage(systemName: "photo")
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
        default:
            let tool = tools[indexPath.row]
            content.text = tool.name
            content.secondaryText = String(localized: tool.state == .running ? "Working…" : tool.state == .succeeded ? "Completed" : "Failed")
            content.image = UIImage(systemName: tool.state == .running ? "hourglass" : tool.state == .succeeded ? "checkmark.circle" : "exclamationmark.circle")
            if !tool.detail.isEmpty { cell.accessoryType = .disclosureIndicator; cell.selectionStyle = .default }
        }
        cell.contentConfiguration = content
        if cell.selectionStyle != .none { cell.accessibilityTraits = .button }
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard isCurrent else { return }
        if indexPath.section == 3 {
            let tool = tools[indexPath.row]
            guard !tool.detail.isEmpty else { return }
            let detail = TextViewerController(editable: false)
            detail.title = tool.name
            detail.text = tool.detail
            navigationController?.pushViewController(detail, animated: true)
        } else if indexPath.section == 2 {
            let url = images[indexPath.row]
            previewTask?.cancel()
            previewTask = Task { @MainActor [weak self] in
                do {
                    let data = try await MarkdownOutputImages.load(url)
                    try Task.checkCancellation()
                    guard let self, self.isCurrent, let suffix = MarkdownOutputImages.filenameExtension(data) else { return }
                    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
                    try data.write(to: file, options: .atomic)
                    let source = SingleItemDataSource(item: file, name: url.lastPathComponent, cleanup: { try? FileManager.default.removeItem(at: file) })
                    self.previewSource = source
                    let preview = QLPreviewController()
                    preview.dataSource = source
                    preview.delegate = source
                    self.present(preview, animated: true)
                } catch is CancellationError { return }
                catch {
                    guard let self, self.isCurrent else { return }
                    let alert = UIAlertController(title: String(localized: "Unable to Complete Action"), message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }
}

final class PiConversationExportController: UITableViewController {
    private let conversationID: Conversation.ID?
    private let binding: PiSessionCoordinator.Binding?
    private var messages: [PiPresentationMessage]
    private var conversationTitle: String
    private let authorization: () -> Bool
    private var subscriptions: Set<AnyCancellable> = []

    init(conversationID: Conversation.ID, coordinator: PiSessionCoordinator? = nil) {
        let coordinator = coordinator ?? .shared
        self.conversationID = conversationID
        binding = coordinator.binding(for: conversationID)
        let context = PiPresentationAuthorization(conversationID: conversationID, coordinator: coordinator)
        authorization = { context.isCurrent }
        let state = coordinator.viewState(for: conversationID)?.conversation
        messages = state?.messages ?? []
        conversationTitle = state?.title ?? String(localized: "Conversation")
        super.init(style: .plain)
        title = String(localized: "Export Conversation")
    }

    init(title: String, messages: [PiPresentationMessage], authorization: @escaping () -> Bool) {
        conversationID = nil
        binding = nil
        self.messages = messages
        conversationTitle = title
        self.authorization = authorization
        super.init(style: .plain)
        self.title = String(localized: "Export Conversation")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "message")
        tableView.allowsMultipleSelection = true
        tableView.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = .init(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItem = .init(title: String(localized: "Export"), image: UIImage(systemName: "square.and.arrow.up"), menu: UIMenu(children: [
            UIAction(title: String(localized: "Markdown")) { [weak self] _ in self?.export(pdf: false) },
            UIAction(title: "PDF") { [weak self] _ in self?.export(pdf: true) },
        ]))
        NotificationCenter.default.publisher(for: .piSessionDidChange).merge(with: NotificationCenter.default.publisher(for: .piAuthenticationEpochDidChange)).merge(with: NotificationCenter.default.publisher(for: .homeAuthorizationDidChange)).receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            if !self.authorization() { self.clearCapturedContent(); self.dismiss(animated: true) }
        }.store(in: &subscriptions)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        String(localized: "Select messages, or export the whole conversation.")
    }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { authorization() ? messages.count : 0 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "message", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.text = messages[indexPath.row].text.isEmpty ? messages[indexPath.row].tool?.name : messages[indexPath.row].text
        content.textProperties.numberOfLines = 3
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        cell.contentConfiguration = content
        cell.accessoryType = tableView.indexPathsForSelectedRows?.contains(indexPath) == true ? .checkmark : .none
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) { tableView.cellForRow(at: indexPath)?.accessoryType = .checkmark }
    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) { tableView.cellForRow(at: indexPath)?.accessoryType = .none }

    func exportData(pdf: Bool) -> Data? {
        guard authorization() else { clearCapturedContent(); return nil }
        let indices = tableView.indexPathsForSelectedRows?.map(\.row).sorted() ?? []
        let selected = indices.isEmpty ? messages : indices.map { messages[$0] }
        return pdf ? PiConversationExport.pdf(title: conversationTitle, messages: selected)
            : Data(PiConversationExport.markdown(title: conversationTitle, messages: selected).utf8)
    }

    private func clearCapturedContent() {
        messages = []
        conversationTitle = ""
        if isViewLoaded { tableView.reloadData() }
    }

    private func export(pdf: Bool) {
        guard let data = exportData(pdf: pdf) else { return }
        DisposableExporter(data: data, pathExtension: pdf ? "pdf" : "md").run(anchor: view, authorization: authorization)
    }
}
