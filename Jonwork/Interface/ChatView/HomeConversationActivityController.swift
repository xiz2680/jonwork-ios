import Combine
import UIKit

/// Typed read-only presentation; original metadata remains a separate inspector.
final class HomeConversationActivityController: UITableViewController {
    private let activity: HomeConversationActivity
    private let originalMetadata: String
    private let authorization: () -> Bool
    private var subscriptions: Set<AnyCancellable> = []

    init(projection: HomeConversationProjection, authorization: @escaping () -> Bool) {
        activity = HomeConversationActivity(projection: projection)
        originalMetadata = HomeConversationActivity.jsonText(projection.rawSession)
        self.authorization = authorization
        super.init(style: .insetGrouped)
        title = String(localized: "Conversation Activity")
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "activity")
        navigationItem.rightBarButtonItem = .init(title: String(localized: "View Raw"), primaryAction: UIAction { [weak self] _ in
            guard let self, self.authorization() else { return }
            self.showDetail(title: String(localized: "View Raw"), text: self.originalMetadata)
        })
        NotificationCenter.default.publisher(for: .homeAuthorizationDidChange).sink { [weak self] _ in
            guard let self, !self.authorization() else { return }
            self.tableView.reloadData()
            self.navigationController?.popToRootViewController(animated: false)
        }.store(in: &subscriptions)
    }

    private var groups: [[HomeConversationActivity.Row]] { [activity.execution, activity.results, activity.outlines, activity.usage] }
    override func numberOfSections(in tableView: UITableView) -> Int { 5 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard authorization() else { return 0 }
        return section == 0 ? 1 : groups[section - 1].count
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section > 0, !groups[section - 1].isEmpty else { return nil }
        switch section {
        case 1: return String(localized: "Execution")
        case 2: return String(localized: "Results")
        case 3: return String(localized: "Research Outline")
        default: return String(localized: "Usage")
        }
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "activity", for: indexPath)
        var content = cell.defaultContentConfiguration()
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        if indexPath.section == 0 {
            content.text = Self.title(activity.phase)
            cell.accessoryType = .none
            cell.selectionStyle = .none
        } else {
            let row = groups[indexPath.section - 1][indexPath.row]
            content.text = row.title
            content.secondaryText = row.subtitle
            content.image = UIImage(systemName: row.kind == .error ? "exclamationmark.circle" : row.kind == .result ? "doc.text" : "list.bullet")
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityTraits = .button
            cell.selectionStyle = .default
        }
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard authorization(), indexPath.section > 0 else { return }
        let row = groups[indexPath.section - 1][indexPath.row]
        showDetail(title: row.title, text: row.detail)
    }
    private func showDetail(title: String, text: String) {
        let controller = TextViewerController(editable: false)
        controller.title = title; controller.text = text
        navigationController?.pushViewController(controller, animated: true)
    }
    private static func title(_ phase: HomeConversationProjection.Phase) -> String {
        switch phase {
        case .idle: String(localized: "Conversation")
        case .running: String(localized: "Working…")
        case .completed: String(localized: "Completed")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Cancelled")
        case .stopped: String(localized: "Stopped")
        case .awaitingOutlineConfirmation: String(localized: "Awaiting Confirmation")
        case .awaitingClarification: String(localized: "Awaiting Clarification")
        }
    }
}
