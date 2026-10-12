//
//  EvaluationSuiteHeaderView.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import GlyphixTextFx
import SnapKit
import UIKit

final class EvaluationSuiteHeaderView: UICollectionReusableView {
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
    private let titleLabel = UILabel()
    private let progressLabel: GlyphixTextLabel = .init().with {
        $0.font = UIFont.preferredFont(forTextStyle: .body)
        $0.textColor = .accent
        $0.textAlignment = .trailing
        $0.isBlurEffectEnabled = false
        $0.translatesAutoresizingMaskIntoConstraints = false
        $0.clipsToBounds = true
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear

        addSubview(blurView)
        blurView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.left.right.equalToSuperview().inset(-100)
        }

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1

        addSubview(titleLabel)
        addSubview(progressLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(8)
            make.leading.equalToSuperview().inset(16)
            make.trailing.lessThanOrEqualTo(progressLabel.snp.leading).offset(-12)
        }

        progressLabel.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.trailing.equalToSuperview().inset(16)
        }
    }

    func configure(title: String, total: Int, completed: Int, passed _: Int, failed: Int, awaitingJudging: Int) {
        titleLabel.text = title

        let progressPercent = total > 0 ? Int((Double(completed) / Double(total) * 100).rounded()) : 0

        if total > 0, completed == total {
            if awaitingJudging > 0 {
                progressLabel.text = String(localized: "Waiting for evaluation")
            } else if failed > 0 {
                progressLabel.text = String(localized: "Completed with \(failed) errors")
            } else {
                progressLabel.text = String(localized: "Completed")
            }
        } else {
            progressLabel.text = "\(progressPercent)%"
        }
    }
}
