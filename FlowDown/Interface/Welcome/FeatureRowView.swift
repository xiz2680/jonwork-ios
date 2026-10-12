//
//  FeatureRowView.swift
//  FlowDown
//
//  Created by qaq on 8/12/2025.
//

import SnapKit
import SwifterSwift
import UIKit

class FeatureRowView: UIView {
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let hStack = UIStackView()
    private let contentStack = UIStackView()

    init() {
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    private func setupViews() {
        hStack.axis = .horizontal
        hStack.spacing = 14
        hStack.alignment = .center

        contentStack.axis = .vertical
        contentStack.spacing = 2
        contentStack.alignment = .leading

        addSubview(hStack)
        hStack.addArrangedSubviews([iconView, contentStack])
        contentStack.addArrangedSubviews([titleLabel, detailLabel])

        hStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .label
        iconView.snp.makeConstraints { make in
            make.width.height.equalTo(28)
        }

        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline).bold
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1

        detailLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0
    }

    func configure(feature: WelcomePageViewController.Feature, accentColor: UIColor) {
        iconView.image = feature.icon.applyingSymbolConfiguration(.init(pointSize: 16, weight: .medium))
        iconView.tintColor = accentColor
        titleLabel.text = String(localized: feature.title)
        detailLabel.text = String(localized: feature.detail)
        accessibilityElements = [titleLabel, detailLabel]
    }
}
