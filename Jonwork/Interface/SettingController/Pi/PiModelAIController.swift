import Combine
import Storage
import UIKit

/// This is the sole product destination for model and thinking configuration.
final class PiModelAIController: UITableViewController {
    private let coordinator: PiSessionCoordinator
    private let conversationID: Conversation.ID?
    private let authorization: PiPresentationAuthorization
    private let scopeControl = UISegmentedControl(items: [String(localized: "Default Settings"), String(localized: "Current Conversation")])
    private var subscriptions: Set<AnyCancellable> = []
    private var isSaving = false

    init(conversationID: Conversation.ID?, coordinator: PiSessionCoordinator? = nil) {
        self.conversationID = conversationID
        self.coordinator = coordinator ?? .shared
        authorization = PiPresentationAuthorization(conversationID: conversationID, coordinator: self.coordinator)
        super.init(style: .plain)
        title = String(localized: "Model & AI")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = .systemBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "setting")
        scopeControl.selectedSegmentIndex = 1
        scopeControl.addAction(UIAction { [weak self] _ in self?.tableView.reloadData() }, for: .valueChanged)
        let header = UIView(frame: .init(x: 0, y: 0, width: 320, height: 64))
        header.addSubview(scopeControl)
        scopeControl.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scopeControl.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            scopeControl.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            scopeControl.centerYAnchor.constraint(equalTo: header.centerYAnchor),
        ])
        tableView.tableHeaderView = header
        NotificationCenter.default.publisher(for: .piSessionDidChange).merge(with: NotificationCenter.default.publisher(for: .piAuthenticationEpochDidChange)).receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.tableView.reloadData()
        }.store(in: &subscriptions)
    }

    private var usableID: Conversation.ID? {
        guard let conversationID, authorization.isCurrent else { return nil }
        return conversationID
    }

    private var models: [PiGatewayWire.Model] { usableID.map { coordinator.models(conversationID: $0) } ?? [] }
    private var selectedModel: PiGatewayWire.Model? {
        guard let id = usableID else { return nil }
        if scopeControl.selectedSegmentIndex == 0, let value = coordinator.defaultConfiguration(for: id) {
            return models.first { $0.provider == value.provider && $0.id == value.modelID }
        }
        return coordinator.selectedModel(conversationID: id)
    }

    private var selectedThinking: String? {
        guard let id = usableID else { return nil }
        if scopeControl.selectedSegmentIndex == 0, let value = coordinator.defaultConfiguration(for: id) { return value.thinkingLevel.rawValue }
        return coordinator.viewState(for: id)?.conversation.thinkingLevel
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if usableID == nil || models.isEmpty { return section == 0 ? 1 : 0 }
        return section == 0 ? models.count : (selectedModel?.thinkingLevels.count ?? 0)
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        String(localized: section == 0 ? "Model" : "Thinking")
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        if usableID == nil { return String(localized: "Open an authenticated conversation to configure Model & AI.") }
        return scopeControl.selectedSegmentIndex == 0
            ? String(localized: "Defaults apply to new conversations in this authenticated workspace. Signing out removes them.")
            : String(localized: "Changes are confirmed by the server before the selection updates.")
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "setting", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        cell.accessoryType = .none
        guard let id = usableID, !models.isEmpty else {
            content.text = String(localized: "Conversations Unavailable")
            cell.contentConfiguration = content
            cell.selectionStyle = .none
            return cell
        }
        if indexPath.section == 0 {
            let model = models[indexPath.row]
            content.text = model.name
            content.secondaryText = model.provider
            cell.accessoryType = selectedModel?.provider == model.provider && selectedModel?.id == model.id ? .checkmark : .none
        } else if let levels = selectedModel?.thinkingLevels {
            let level = levels[indexPath.row]
            content.text = Self.title(for: level)
            cell.accessoryType = selectedThinking == level.rawValue ? .checkmark : .none
        }
        let state = coordinator.viewState(for: id)
        let canEdit = !isSaving && state?.connection == .connected && state?.pendingAction == nil
            && (scopeControl.selectedSegmentIndex == 0 || (state?.conversation.role == .controller && state?.conversation.isReleased == false && state?.conversation.isStreaming == false))
        cell.isUserInteractionEnabled = canEdit
        content.textProperties.color = canEdit ? .label : .secondaryLabel
        cell.accessibilityTraits = cell.accessoryType == .checkmark ? [.button, .selected] : .button
        if !canEdit { cell.accessibilityTraits.insert(.notEnabled) }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let id = usableID, !isSaving, !models.isEmpty else { return }
        let isDefault = scopeControl.selectedSegmentIndex == 0
        let model = indexPath.section == 0 ? models[indexPath.row] : selectedModel
        guard let model else { return }
        let level = indexPath.section == 1 ? model.thinkingLevels[indexPath.row]
            : (model.thinkingLevels.first { $0.rawValue == selectedThinking } ?? model.thinkingLevels.first ?? .off)
        isSaving = true
        scopeControl.isEnabled = false
        tableView.reloadData()
        Task { @MainActor [self] in
            defer { isSaving = false; scopeControl.isEnabled = true; tableView.reloadData() }
            do {
                guard authorization.isCurrent else { return }
                if isDefault {
                    try coordinator.saveDefaultConfiguration(.init(provider: model.provider, modelID: model.id, thinkingLevel: level), conversationID: id)
                } else if indexPath.section == 0 {
                    try await coordinator.setModel(provider: model.provider, modelID: model.id, conversationID: id)
                } else {
                    try await coordinator.setThinkingLevel(level, conversationID: id)
                }
            } catch is CancellationError { return }
            catch {
                guard usableID == id else { return }
                let alert = UIAlertController(title: String(localized: "Unable to Complete Action"), message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
                present(alert, animated: true)
            }
        }
    }

    static func title(for level: PiGatewayWire.ThinkingLevel) -> String {
        switch level {
        case .off: String(localized: "Off")
        case .minimal: String(localized: "Minimal")
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        case .xhigh: String(localized: "Very High")
        case .max: String(localized: "Maximum")
        }
    }
}
