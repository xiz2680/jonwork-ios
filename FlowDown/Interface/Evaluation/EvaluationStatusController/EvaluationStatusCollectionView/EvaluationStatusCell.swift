//
//  EvaluationStatusCell.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import SnapKit
import UIKit

class EvaluationStatusCell: UICollectionViewCell {
    private let titleLabel: UILabel = .init()
    private let statusLabel: UILabel = .init()
    private let statusIcon = UIImageView()

    private let contentInsets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private func setupUI() {
        contentView.backgroundColor = .gray.withAlphaComponent(0.1)
        contentView.layer.cornerRadius = 16
        contentView.layer.cornerCurve = .continuous

        contentView.addSubview(statusIcon)
        contentView.addSubview(titleLabel)
        contentView.addSubview(statusLabel)

        titleLabel.font = .preferredFont(forTextStyle: .body).bold
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.snp.makeConstraints { make in
            make.top.leading.equalToSuperview().inset(contentInsets)
        }

        statusIcon.contentMode = .scaleAspectFit
        statusIcon.alpha = 1
        statusIcon.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(contentInsets)
            make.centerY.equalTo(titleLabel.snp.centerY)
            make.size.equalTo(titleLabel.font.lineHeight).priority(999)
        }

        titleLabel.snp.makeConstraints { make in
            make.trailing.lessThanOrEqualTo(statusIcon.snp.leading).offset(-8)
        }

        statusLabel.font = .preferredFont(forTextStyle: .caption2)
        statusLabel.numberOfLines = 1
        statusLabel.snp.makeConstraints { make in
            make.top.greaterThanOrEqualTo(titleLabel.snp.bottom).offset(8)
            make.bottom.leading.trailing.equalToSuperview().inset(contentInsets)
        }
    }

    func configure(with item: EvaluationManifest.Suite.Case) {
        titleLabel.text = item.title

        let result = item.results.last?.outcome ?? .notDetermined

        let targetColor: UIColor
        let iconName: String
        let statusText: String.LocalizationValue

        switch result {
        case .pass:
            targetColor = .systemGreen
            iconName = "checkmark.seal.fill"
            statusText = "Passed"
        case .fail:
            targetColor = .systemRed
            iconName = "xmark.seal.fill"
            statusText = "Failed"
        case .processing:
            targetColor = .systemBlue
            iconName = "gearshape.fill"
            statusText = "Running"
        case .awaitingJudging:
            targetColor = .systemOrange
            iconName = "eye.fill"
            statusText = "Judging"
        case .notDetermined:
            targetColor = .tertiaryLabel
            iconName = "circle.dotted"
            statusText = "Pending"
        }

        statusIcon.tintColor = targetColor
        statusLabel.textColor = targetColor
        if statusIcon.image != UIImage(systemName: iconName) {
            statusIcon.image = UIImage(systemName: iconName)
        }
        statusLabel.text = String(localized: statusText)
    }
}
