//
//  WelcomePageViewController+Configuration.swift
//  Jonwork
//
//  Created by qaq on 8/12/2025.
//

import SnapKit
import SwifterSwift
import UIKit

extension WelcomePageViewController {
    struct Configuration {
        var title: String.LocalizationValue
        var highlightedTitle: String.LocalizationValue
        var subtitle: String.LocalizationValue
        var buttonTitle: String.LocalizationValue
        var accentColor: UIColor
        var icon: UIImage
        var features: [Feature]
    }

    struct Feature {
        var icon: UIImage
        var title: String.LocalizationValue
        var detail: String.LocalizationValue
    }
}

extension WelcomePageViewController.Configuration {
    static var `default`: Self {
        return .init(
            title: "Welcome to",
            highlightedTitle: "Jonwork",
            subtitle: "Keep your workspace conversations in sync with the work already running on your desktop.",
            buttonTitle: "Continue",
            accentColor: .accent,
            icon: .avatar,
            features: [
                .init(
                    icon: UIImage(systemName: "rectangle.connected.to.line.below")!,
                    title: "Connect Your Workspace",
                    detail: "Sign in to the Jonwork workspace your team already uses.",
                ),
                .init(
                    icon: UIImage(systemName: "folder.fill")!,
                    title: "Choose a Project",
                    detail: "Open the project and active work available to your account.",
                ),
                .init(
                    icon: UIImage(systemName: "arrow.trianglehead.2.clockwise.rotate.90")!,
                    title: "Resume Conversations",
                    detail: "Follow live progress, review tool activity, and continue from your phone.",
                ),
                .init(
                    icon: UIImage(systemName: "lock.shield.fill")!,
                    title: "Workspace Access",
                    detail: "Jonwork only shows projects and conversations authorized for your account.",
                ),
            ],
        )
    }
}
