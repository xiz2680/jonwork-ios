//
//  Sidebar.swift
//  Jonwork
//
//  Created by 秋星桥 on 1/21/25.
//

import Combine
import Storage
import UIKit

class Sidebar: UIView {
    let brandingLabel = SidebarBrandingLabel()
    let newChatButton = NewChatButton()
    let searchButton = SearchControllerOpenButton()
    let settingButton = SettingButton()
    let conversationSelectionView = ConversationSelectionView()
    let syncIndicator = SidebarSyncLabel()

    private var cancellables = Set<AnyCancellable>()

    init() {
        super.init(frame: .zero)

        backgroundColor = .systemBackground
        layer.cornerRadius = 0
        let spacing: CGFloat = 12
        let sections: [UIView] = [brandingLabel, searchButton, newChatButton, settingButton, conversationSelectionView]
        sections.forEach { addSubview($0) }
        brandingLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(16)
            make.trailing.equalToSuperview().inset(16)
        }
        configureRow(searchButton, title: String(localized: "Search Conversations"), symbol: "magnifyingglass")
        configureRow(newChatButton, title: String(localized: "New Conversation"), symbol: "square.and.pencil")
        configureRow(settingButton, title: String(localized: "Settings"), symbol: "person.crop.circle")
        searchButton.accessibilityIdentifier = "JonworkSidebarSearch"
        newChatButton.accessibilityIdentifier = "JonworkSidebarNewConversation"
        settingButton.accessibilityIdentifier = "JonworkSidebarAccountSettings"
        settingButton.showsMenuAsPrimaryAction = true
        settingButton.removeTarget(nil, action: nil, for: .touchUpInside)
        settingButton.menu = UIMenu(children: [
            UIAction(title: String(localized: "Settings"), image: UIImage(systemName: "gearshape")) { [weak self] _ in
                guard let self, let presenter = self.parentViewController, presenter.presentedViewController == nil, !presenter.isBeingDismissed else { return }
                self.settingButton.buttonAction()
            },
            UIAction(title: String(localized: "Sign Out"), image: UIImage(systemName: "rectangle.portrait.and.arrow.right"), attributes: .destructive) { [weak self] _ in
                guard let self, let presenter = self.parentViewController, presenter.presentedViewController == nil, !presenter.isBeingDismissed else { return }
                let workspace = SettingController.SettingContent.PiServerController(autoConnect: false)
                let navigation = UINavigationController()
                SettingController.configureJonworkWorkspace(in: navigation, workspace: workspace)
                presenter.present(navigation, animated: true) {
                    if workspace.hasSavedToken {
                        workspace.confirmRemoveSavedToken(onCancel: { navigation.dismiss(animated: true) })
                    } else {
                        workspace.prepareForEntry()
                    }
                }
            },
        ])
        searchButton.delegate = self
        newChatButton.delegate = self
        searchButton.snp.makeConstraints { make in
            make.top.equalTo(brandingLabel.snp.bottom).offset(20)
            make.leading.trailing.equalToSuperview().inset(12)
            make.height.greaterThanOrEqualTo(48)
        }
        newChatButton.snp.makeConstraints { make in
            make.top.equalTo(searchButton.snp.bottom).offset(8)
            make.leading.trailing.equalTo(searchButton)
            make.height.greaterThanOrEqualTo(48)
        }
        settingButton.snp.makeConstraints { make in
            make.leading.trailing.equalTo(searchButton)
            make.bottom.equalToSuperview().inset(12)
            make.height.greaterThanOrEqualTo(48)
        }
        conversationSelectionView.snp.makeConstraints { make in
            make.top.equalTo(newChatButton.snp.bottom).offset(spacing)
            make.bottom.equalTo(settingButton.snp.top).offset(-spacing)
            make.leading.trailing.equalToSuperview()
        }

    }

    private func configureRow(_ button: UIButton, title: String, symbol: String) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 12
        configuration.contentInsets = .init(top: 12, leading: 14, bottom: 12, trailing: 14)
        configuration.baseForegroundColor = .label
        configuration.background.backgroundColor = .clear
        configuration.background.cornerRadius = 0
        button.configuration = configuration
        button.contentHorizontalAlignment = .leading
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontForContentSizeCategory = true
        button.titleLabel?.numberOfLines = 0
        button.accessibilityLabel = title
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }
}
