import UIKit
import Combine

/// Picker rows come from the editor's actual discovery/model capability policy.
final class PiAddReferenceController: UITableViewController {
    private weak var editor: RichEditorView?
    private let authorization: PiPresentationAuthorization
    private let conversationID: String?
    private var rows: [(String, String, () -> Void)] = []
    private var subscriptions: Set<AnyCancellable> = []

    init(editor: RichEditorView) {
        self.editor = editor
        conversationID = ChatSelection.shared.currentSelection.identifier
        authorization = PiPresentationAuthorization(conversationID: conversationID)
        super.init(style: .plain)
        title = String(localized: "Add & Reference")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "reference")
        navigationItem.leftBarButtonItem = .init(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        NotificationCenter.default.publisher(for: .piSessionDidChange).merge(with: NotificationCenter.default.publisher(for: .piAuthenticationEpochDidChange)).receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self else { return }
            if !self.authorization.isCurrent { self.rows = []; self.tableView.reloadData(); self.dismiss(animated: true) }
        }.store(in: &subscriptions)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rows = []
        guard let editor, authorization.isCurrent else {
            dismiss(animated: animated)
            return
        }
        if editor.jonworkAllowsImageAttachments && editor.jonworkAllowsPhotoLibrary {
            rows.append((String(localized: "Photo"), "photo", { [weak editor] in editor?.openPhotoPicker() }))
        }
        if editor.jonworkAllowsImageAttachments && editor.jonworkAllowsCamera {
            rows.append((String(localized: "Camera"), "camera", { [weak editor] in editor?.openCamera() }))
        }
        if editor.jonworkAllowsFileAttachments && editor.jonworkAllowsFilePicker {
            rows.append((String(localized: "File"), "doc", { [weak editor] in editor?.openFilePicker() }))
        }
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard authorization.isCurrent else { return 0 }
        return section == 0 ? rows.count : (editor?.attachmentsBar.attachmetns.count ?? 0)
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        String(localized: section == 0 ? "Files" : "Selected Attachments")
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? String(localized: "Available sources follow this workspace and model's attachment permissions.") : nil
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "reference", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            content.text = rows[indexPath.row].0
            content.image = UIImage(systemName: rows[indexPath.row].1)
        } else if let items = editor?.attachmentsBar.attachmetns.values {
            let item = Array(items)[indexPath.row]
            content.text = item.name
            content.image = UIImage(data: item.previewImage) ?? UIImage(systemName: "doc")
        }
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.textProperties.numberOfLines = 0
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityTraits = .button
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard authorization.isCurrent else { dismiss(animated: true); return }
        if indexPath.section == 0 {
            let action = rows[indexPath.row].2
            let authorization = authorization
            dismiss(animated: true) { if authorization.isCurrent { action() } }
        } else if let editor {
            let item = Array(editor.attachmentsBar.attachmetns.values)[indexPath.row]
            let authorization = authorization
            dismiss(animated: true) { [weak editor] in
                guard authorization.isCurrent else { return }
                editor?.attachmentsBar.presentPreview(for: item)
            }
        }
    }
    override func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard indexPath.section == 1, let editor else { return nil }
        let item = Array(editor.attachmentsBar.attachmetns.values)[indexPath.row]
        let remove = UIContextualAction(style: .destructive, title: String(localized: "Remove")) { [weak self, weak editor] _, _, completion in
            guard let self, self.authorization.isCurrent else { completion(false); return }
            editor?.attachmentsBar.delete(itemIdentifier: item.id)
            self.tableView.reloadData()
            completion(true)
        }
        return UISwipeActionsConfiguration(actions: [remove])
    }
}
