//
//  SettingButton 2.swift
//  Jonwork
//
//  Created by 秋星桥 on 1/22/25.
//

import AlertController
import Combine
import Storage
import UIKit

class NewChatButton: UIButton {
    private var cancellables: Set<AnyCancellable> = []

    init() {
        super.init(frame: .zero)
        setImage(UIImage(systemName: "plus"), for: .normal)
        tintColor = .label
        imageView?.contentMode = .scaleAspectFit
        updateMenu()

        ChatTemplateManager.shared.$templates
            // it's a object will change
            .delay(for: .seconds(0.1), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenu()
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    weak var delegate: Delegate?
    var makeJonworkController: () -> UIViewController = {
        SettingController.makeJonworkWorkspaceController(startsNewConversation: true)
    }

    private func updateMenu() {
        if !JonworkSurfacePolicy.allowsLegacyConversations {
            showsMenuAsPrimaryAction = false
            removeTarget(nil, action: nil, for: .touchUpInside)
            addTarget(self, action: #selector(createJonworkConversation), for: .touchUpInside)
            menu = nil
            return
        }

        #if DEBUG
            let templates = ChatTemplateManager.shared.templates

            if templates.isEmpty {
                // No templates, use direct tap action
                showsMenuAsPrimaryAction = false
                removeTarget(nil, action: nil, for: .touchUpInside)
                addTarget(self, action: #selector(createNewConversation), for: .touchUpInside)
                menu = nil
            } else {
                // Has templates, show menu
                showsMenuAsPrimaryAction = true
                removeTarget(nil, action: nil, for: .touchUpInside)
                menu = UIMenu(children: buildMenu())
            }
        #else
            showsMenuAsPrimaryAction = false
            removeTarget(nil, action: nil, for: .touchUpInside)
            addTarget(self, action: #selector(showUnavailable), for: .touchUpInside)
            menu = nil
        #endif
    }

    @objc private func createJonworkConversation() {
        guard let presenter = parentViewController, presenter.presentedViewController == nil, !presenter.isBeingDismissed else { return }
        presenter.present(makeJonworkController(), animated: true)
    }

    @objc private func createNewConversation() {
        let conv = ConversationManager.shared.createNewConversation()
        delegate?.newChatDidCreated(conv.id)
    }

    @objc private func showUnavailable() {
        let alert = AlertViewController(
            title: "Conversations Unavailable",
            message: "Jonwork sign-in is not available in this build. No local conversation was created.",
        ) { context in
            context.allowSimpleDispose()
            context.addAction(title: "OK", attribute: .accent) { context.dispose() }
        }
        parentViewController?.present(alert, animated: true)
    }

    private func buildMenu() -> [UIMenuElement] {
        let templates = ChatTemplateManager.shared.templates

        let newEmpty = UIAction(
            title: String(localized: "New Conversation"),
            image: UIImage(systemName: "plus"),
        ) { [weak self] _ in
            let conv = ConversationManager.shared.createNewConversation()
            self?.delegate?.newChatDidCreated(conv.id)
        }

        if templates.isEmpty {
            return [newEmpty]
        }

        var actions: [UIAction] = []
        for template in templates.values {
            // Scale template avatar to standard menu icon size using aspect fit
            let scaledImage: UIImage? = {
                guard let originalImage = UIImage(data: template.avatar) else { return nil }
                let iconSize = UIFont.preferredFont(forTextStyle: .body).pointSize
                let targetSize = CGSize(width: iconSize, height: iconSize)

                // Calculate aspect fit size
                let aspectRatio = originalImage.size.width / originalImage.size.height
                var drawSize = targetSize
                if aspectRatio > 1 {
                    drawSize.height = targetSize.width / aspectRatio
                } else {
                    drawSize.width = targetSize.height * aspectRatio
                }

                let renderer = UIGraphicsImageRenderer(size: targetSize)
                return renderer.image { _ in
                    let origin = CGPoint(
                        x: (targetSize.width - drawSize.width) / 2,
                        y: (targetSize.height - drawSize.height) / 2,
                    )
                    originalImage.draw(in: CGRect(origin: origin, size: drawSize))
                }
            }()

            let action = UIAction(
                title: template.name,
                image: scaledImage,
            ) { [weak self] _ in
                let convId = ChatTemplateManager.shared.createConversationFromTemplate(template)
                self?.delegate?.newChatDidCreated(convId)
            }
            actions.append(action)
        }

        let templateMenu = UIMenu(
            title: String(localized: "Choose Template"),
            image: UIImage(systemName: "folder"),
            options: [.displayInline],
            children: actions,
        )

        return [newEmpty, templateMenu]
    }
}

extension NewChatButton {
    protocol Delegate: AnyObject {
        func newChatDidCreated(_ identifier: Conversation.ID)
    }
}
