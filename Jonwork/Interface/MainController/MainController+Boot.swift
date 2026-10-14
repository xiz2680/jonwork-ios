//
//  MainController+Boot.swift
//  Jonwork
//
//  Created by 秋星桥 on 7/3/25.
//

import AlertController
import Combine
import Foundation
import UIKit

extension MainController {
    func queueBootMessage(text: String.LocalizationValue) {
        bootAlertMessageQueue.append(String(localized: text))
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(presentNextBootMessage),
            object: nil,
        )
        perform(#selector(presentNextBootMessage), with: nil, afterDelay: 0.5)
    }

    @objc func presentNextBootMessage() {
        let text = bootAlertMessageQueue.joined(separator: "\n")
        bootAlertMessageQueue.removeAll()

        let alert = AlertViewController(
            title: "External Resources",
            message: "\(text)",
        ) { context in
            context.allowSimpleDispose()
            context.addAction(title: "OK", attribute: .accent) {
                context.dispose {}
            }
        }
        var viewController: UIViewController = self
        while let child = viewController.presentedViewController {
            viewController = child
        }
        viewController.present(alert, animated: true)
    }

    func queueNewConversation(text: String, shouldSend: Bool = false) {
        guard JonworkSurfacePolicy.allowsLegacyConversations else {
            load(nil)
            presentWorkspaceConnection()
            return
        }
        #if DEBUG
            Task { @MainActor in
                let conversation = ConversationManager.shared.createNewConversation(autoSelect: true)
                Logger.app.infoFile("created new conversation ID: \(conversation.id)")
                guard shouldSend else { return }
                try await Task.sleep(nanoseconds: 500_000_000)
                if self.chatView.conversationIdentifier == conversation.id {
                    self.sendMessageToCurrentConversation(text)
                }
            }
        #else
            _ = text
            _ = shouldSend
            load(nil)
        #endif
    }

    func scheduleWelcomeIfNeeded() {
        guard !hasScheduledWelcome else { return }
        guard presentedViewController == nil else { return }
        hasScheduledWelcome = true
        if WelcomeExperience.shouldPresent {
            let welcome = WelcomePageViewController()
            let navigation = UINavigationController(rootViewController: welcome)
            navigation.modalPresentationStyle = .fullScreen
            navigation.isModalInPresentation = true
            welcome.dismissesOnCompletion = false
            welcome.onComplete = { [weak navigation] in
                WelcomeExperience.markPresented()
                guard let navigation else { return }
                SettingController.configureJonworkWorkspace(in: navigation)
            }
            present(navigation, animated: false)
        } else {
            presentWorkspaceConnection(animated: false)
        }
    }

    func presentWorkspaceConnection(animated: Bool = true) {
        guard presentedViewController == nil else { return }
        present(SettingController.makeJonworkWorkspaceController(), animated: animated)
    }
}
