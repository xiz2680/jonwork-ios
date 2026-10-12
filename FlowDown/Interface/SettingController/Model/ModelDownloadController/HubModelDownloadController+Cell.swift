//
//  HubModelDownloadController+Cell.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import BetterCodable
import ConfigurableKit
import Foundation
import UIKit

extension HubModelDownloadController {
    class Cell: UITableViewCell {
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

        func use(model: HubModelDownloadController.RemoteModel) {
            var name = model.id
            if name.lowercased().hasPrefix(model.author.lowercased() + "/") {
                name = String(name.dropFirst(model.author.count + 1))
            }
            content.configure(title: "\(name)")
            let desc = [
                model.author,
                model.pipeline_tag.capitalized,
            ]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
            content.configure(description: "\(desc)")
        }
    }
}
