//
//  RichEditorView+Progress.swift
//  RichEditor
//
//  Created by 秋星桥 on 3/19/25.
//

import AlertController
import Foundation
import UIKit

private class ActionButton: UIView {
    var action: (() -> Void) = {}

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = true
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc func tapped() {
        action()
        action = {}
    }
}

extension RichEditorView {
    typealias ProgressCompleteHandler = () -> Void
    func withProgress(onUserRequestCancellation: @escaping () -> Void) -> ProgressCompleteHandler {
        var disposableViews = [UIView]()

        let vfx = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
        disposableViews.append(vfx)

        addSubview(vfx)
        vfx.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            vfx.leadingAnchor.constraint(equalTo: leadingAnchor),
            vfx.topAnchor.constraint(equalTo: topAnchor),
            vfx.bottomAnchor.constraint(equalTo: bottomAnchor),
            vfx.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        vfx.contentView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: vfx.contentView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: vfx.contentView.centerYAnchor),
        ])

        let activityIndicator = UIActivityIndicatorView(style: .medium)
        activityIndicator.startAnimating()
        stackView.addArrangedSubview(activityIndicator)

        let label = UILabel()
        label.text = String(localized: "Processing Request")
        label.textColor = .label
        label.font = .preferredFont(forTextStyle: .footnote)
        stackView.addArrangedSubview(label)

        let cancelButton = ActionButton()
        cancelButton.action = {
            let alert = AlertViewController(
                title: NSLocalizedString("Terminate", comment: ""),
                message: NSLocalizedString("Are you sure you want to terminate this request?", comment: ""),
            ) { context in
                context.addAction(title: NSLocalizedString("Cancel", comment: "")) {
                    context.dispose()
                }
                context.addAction(title: NSLocalizedString("Terminate", comment: ""), attribute: .accent) {
                    onUserRequestCancellation()
                    context.dispose()
                }
            }
            self.parentViewController?.present(alert, animated: true)
        }
        addSubview(cancelButton)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor),
            cancelButton.topAnchor.constraint(equalTo: topAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: bottomAnchor),
            cancelButton.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        disposableViews.append(cancelButton)

        for view in disposableViews {
            view.alpha = 0
        }
        UIView.animate(withDuration: 0.25) {
            for view in disposableViews {
                view.alpha = 1
            }
        }

        return {
            for view in disposableViews {
                view.isUserInteractionEnabled = false
            }
            UIView.animate(withDuration: 0.25) {
                for view in disposableViews {
                    view.alpha = 0
                }
            } completion: { _ in
                for view in disposableViews {
                    view.removeFromSuperview()
                }
            }
        }
    }
}
