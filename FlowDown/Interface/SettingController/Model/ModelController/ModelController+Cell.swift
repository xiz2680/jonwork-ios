//
//  ModelController+Cell.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import ConfigurableKit
import UIKit

extension SettingController.SettingContent.ModelController {
    class ModelCell: UITableViewCell {
        let content = ConfigurablePageView { fatalError() }

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            backgroundColor = .clear
            selectionStyle = .none
            clipsToBounds = true
            let wrappingView = AutoLayoutMarginView(content)
            contentView.addSubview(wrappingView)
            wrappingView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            content.configure(icon: .modelLocal)
            content.isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        enum ModelType {
            case local
            case cloud

            var image: UIImage {
                switch self {
                case .local: .modelLocal
                case .cloud: .modelCloud
                }
            }
        }

        func update(type: ModelType, name: String, descriptions: [String]) {
            content.configure(icon: type.image)
            content.configure(title: name)
            let desc = descriptions.joined(separator: ", ")
            content.configure(description: desc)
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            preservesSuperviewLayoutMargins = false
            separatorInset = UIEdgeInsets.zero
            layoutMargins = UIEdgeInsets.zero
        }
    }
}

extension SettingController.SettingContent.ModelController {
    class HeaderCell: UITableViewCell {
        let vfx = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        let titleLabel = UILabel()
        init() {
            super.init(style: .default, reuseIdentifier: nil)
            backgroundColor = .clear
            selectionStyle = .none
            vfx.contentView.addSubview(titleLabel)
            contentView.addSubview(vfx)
            vfx.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
            titleLabel.snp.makeConstraints { make in
                make.center.equalToSuperview()
            }
            titleLabel.font = .footnote
            titleLabel.textColor = .secondaryLabel
            titleLabel.numberOfLines = 1
            titleLabel.textAlignment = .left
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }
    }
}
