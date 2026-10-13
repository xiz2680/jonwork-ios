//
//  SettingContent+Support.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/24/25.
//

import ConfigurableKit
import Storage
import UIKit

extension SettingController.SettingContent {
    class SupportController: StackScrollController {
        init() {
            super.init(nibName: nil, bundle: nil)
            title = String(localized: "Contact Us")
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .background
        }

        override func setupContentViews() {
            super.setupContentViews()

            stackView.addArrangedSubview(SeparatorView())

            for section in settingSections {
                if !String(localized: section.title).isEmpty {
                    stackView.addArrangedSubviewWithMargin(
                        ConfigurableSectionHeaderView().with(header: section.title),
                    ) { $0.bottom /= 2 }
                    stackView.addArrangedSubview(SeparatorView())
                }
                for object in section.objects {
                    stackView.addArrangedSubviewWithMargin(object.createView())
                    stackView.addArrangedSubview(SeparatorView())
                }
            }
        }
    }
}

extension SettingController.SettingContent.SupportController {
    typealias SettingSection = (
        title: String.LocalizationValue,
        objects: [ConfigurableObject],
    )
    var versionObject: SettingSection {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        return (
            title: "App Information",
            objects: [
                ConfigurableObject(
                    icon: "info.circle",
                    title: "Version",
                    explain: "\(version) (\(build))",
                    ephemeralAnnotation: .action { _ in },
                ),
            ],
        )
    }

    var openSourceObject: SettingSection {
        (
            title: "Software Resources",
            objects: [
                ConfigurableObject(
                    icon: "flag.filled.and.flag.crossed",
                    title: "Open Source Licenses",
                    explain: "These are the open-source licenses for the frameworks used in this app.",
                    ephemeralAnnotation: .action { controller in
                        controller.navigationController?.pushViewController(OpenSourceLicenseController(), animated: true)
                    },
                ),
            ],
        )
    }

    var agreementsObject: SettingSection {
        (
            title: "Agreements",
            objects: [
                ConfigurableObject(
                    icon: "lock",
                    title: "Privacy Policy",
                    explain: "Tells you how we handle your data.",
                    ephemeralAnnotation: .action { controller in
                        controller.navigationController?.pushViewController(PrivacyPolicyController(), animated: true)
                    },
                ),
            ],
        )
    }

    var settingSections: [SettingSection] {
        [
            agreementsObject,
            openSourceObject,
            versionObject,
        ]
    }
}
