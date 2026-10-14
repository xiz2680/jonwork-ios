//
//  ConversationSelectionView.swift
//  Jonwork
//
//  Created by 秋星桥 on 2/3/25.
//

import Combine
import Foundation
import Storage
import UIKit

private class GroundedTableView: UITableView {
    @objc var allowsHeaderViewsToFloat: Bool {
        false
    }

    @objc var allowsFooterViewsToFloat: Bool {
        false
    }
}

class ConversationSelectionView: UIView {
    let allowsLegacyConversations: Bool
    let tableView: UITableView
    let dataSource: DataSource

    var cancellables: Set<AnyCancellable> = []

    typealias DataIdentifier = Conversation.ID
    typealias SectionIdentifier = Date

    typealias DataSource = UITableViewDiffableDataSource<SectionIdentifier, DataIdentifier>
    typealias Snapshot = NSDiffableDataSourceSnapshot<SectionIdentifier, DataIdentifier>

    init(allowsLegacyConversations: Bool = JonworkSurfacePolicy.allowsLegacyConversations) {
        self.allowsLegacyConversations = allowsLegacyConversations
        tableView = GroundedTableView(frame: .zero, style: .plain)
        tableView.register(Cell.self, forCellReuseIdentifier: "Cell")

        dataSource = .init(tableView: tableView) { tableView, indexPath, itemIdentifier in
            tableView.separatorColor = .clear
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! Cell
            let conv = ConversationManager.shared.conversation(identifier: itemIdentifier)
            cell.use(conv, allowsLegacyConversations: allowsLegacyConversations)
            return cell
        }
        dataSource.defaultRowAnimation = .fade

        super.init(frame: .zero)

        isUserInteractionEnabled = true

        addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.separatorInset = .zero
        tableView.separatorColor = .clear
        tableView.contentInset = .zero
        tableView.allowsMultipleSelection = false
        tableView.selectionFollowsFocus = true
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.sectionHeaderTopPadding = 0
        tableView.sectionHeaderHeight = UITableView.automaticDimension

        updateDataSource()
        NotificationCenter.default.publisher(for: .piSessionDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateDataSource() }
            .store(in: &cancellables)

        Publishers.CombineLatest(
            ConversationManager.shared.conversations,
            ChatSelection.shared.selection,
        )
        .debounce(for: .milliseconds(16), scheduler: DispatchQueue.main)
        .ensureMainThread()
        .sink { [weak self] _, selection in
            guard let self else { return }
            updateDataSource()
            let identifier = selection.identifier
            let optionDescription: String = {
                switch selection {
                case .none:
                    return "none"
                case let .conversation(_, options):
                    var components: [String] = []
                    if options.contains(.collapseSidebar) { components.append("collapseSidebar") }
                    if options.contains(.focusEditor) { components.append("focusEditor") }
                    return components.isEmpty ? "none" : components.joined(separator: ",")
                }
            }()
            Logger.ui.debugFile("ConversationSelectionView received global selection: \(identifier ?? "nil") options: \(optionDescription)")
            let selectedIndexPath = Set(tableView.indexPathsForSelectedRows ?? [])
            for index in selectedIndexPath {
                tableView.deselectRow(at: index, animated: false)
            }
            if let identifier,
               let indexPath = dataSource.indexPath(for: identifier)
            {
                let visible = tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false
                tableView.selectRow(
                    at: indexPath,
                    animated: false,
                    scrollPosition: visible ? .none : .middle,
                )
            } else if dataSource.numberOfSections(in: tableView) > 0,
                      dataSource.tableView(tableView, numberOfRowsInSection: 0) > 0
            {
                let indexPath = IndexPath(row: 0, section: 0)
                let visible = tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false
                tableView.selectRow(
                    at: indexPath,
                    animated: false,
                    scrollPosition: visible ? .none : .middle,
                )
            }
        }
        .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func updateDataSource() {
        let list = ConversationManager.shared.conversations.value.values.filter {
            allowsLegacyConversations || PiSessionCoordinator.shared.binding(for: $0.id) != nil
        }.sorted {
            let lhs = PiSessionCoordinator.shared.nativeFlags(for: $0.id)
            let rhs = PiSessionCoordinator.shared.nativeFlags(for: $1.id)
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return $0.creation > $1.creation
        }
        guard !list.isEmpty else {
            if JonworkSurfacePolicy.shouldCreateInitialConversation(
                isConversationListEmpty: true,
                allowsLegacyConversations: allowsLegacyConversations
            ) {
                _ = ConversationManager.shared.initialConversation()
            } else {
                dataSource.apply(Snapshot(), animatingDifferences: true)
            }
            return
        }

        var snapshot = Snapshot()

        let favorited = list.filter { $0.isFavorite || PiSessionCoordinator.shared.nativeFlags(for: $0.id).favorite || PiSessionCoordinator.shared.nativeFlags(for: $0.id).pinned }
        if !favorited.isEmpty {
            let favoriteSection = Date(timeIntervalSince1970: -1)
            snapshot.appendSections([favoriteSection])
            snapshot.appendItems(favorited.map(\.id), toSection: favoriteSection)
        }

        let calendar = Calendar.current

        var conversationsByDate: [Date: [Conversation.ID]] = [:]
        for item in list where !favorited.contains(where: { $0.id == item.id }) {
            let dateOnly = calendar.startOfDay(for: item.creation)
            if conversationsByDate[dateOnly] == nil {
                conversationsByDate[dateOnly] = []
            }
            conversationsByDate[dateOnly]?.append(item.id)
        }

        let sortedDates = conversationsByDate.keys.sorted(by: >)

        for date in sortedDates {
            snapshot.appendSections([date])
            if let conversations = conversationsByDate[date] {
                snapshot.appendItems(conversations, toSection: date)
            }
        }
        let previousSections = dataSource.snapshot().sectionIdentifiers
        if previousSections.count == 1, sortedDates.count > 1 {
            // reload all!
            snapshot.reloadSections(sortedDates)
        }

        dataSource.apply(snapshot, animatingDifferences: true)

        Task { @MainActor [self] in
            var snapshot = dataSource.snapshot()
            let visibleRows = tableView.indexPathsForVisibleRows ?? []
            let visibleItemIdentifiers = visibleRows
                .map { dataSource.itemIdentifier(for: $0) }
                .compactMap(\.self)
            snapshot.reconfigureItems(visibleItemIdentifiers)
            dataSource.apply(snapshot, animatingDifferences: true)
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // detect command + 1/2/3/4 ... 9 to select conversation
        var resolved = false
        for press in presses {
            guard let key = press.key else { continue }
            let keyCode = key.charactersIgnoringModifiers
            guard keyCode.count == 1,
                  key.modifierFlags.contains(.command),
                  var digit = Int(keyCode)
            else { continue }
            digit -= 1
            guard digit >= 0, digit < dataSource.snapshot().numberOfItems else {
                continue
            }

            // now check which section we are in
            let snapshot = dataSource.snapshot()
            var sectionIndex: Int? = nil
            var sectionItemIndex: Int? = nil
            var currentCount = 0
            for (index, section) in snapshot.sectionIdentifiers.enumerated() {
                let count = snapshot.numberOfItems(inSection: section)
                if currentCount + count > digit {
                    sectionIndex = index
                    sectionItemIndex = digit - currentCount
                    break
                }
                currentCount += count
            }
            guard let sectionIndex, let sectionItemIndex else {
                assertionFailure()
                continue
            }
            let indexPath = IndexPath(item: sectionItemIndex, section: sectionIndex)
            let identifier = dataSource.itemIdentifier(for: indexPath)
            ChatSelection.shared.select(identifier)
            resolved = true
        }
        if !resolved {
            super.pressesBegan(presses, with: event)
        }
    }
}
