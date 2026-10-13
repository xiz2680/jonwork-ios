import UIKit

final class PiSessionStatusView: UIVisualEffectView {
    let statusLabel = UILabel().with {
        $0.font = .preferredFont(forTextStyle: .caption1).bold
        $0.adjustsFontForContentSizeCategory = true
        $0.textColor = .secondaryLabel
        $0.numberOfLines = 0
    }

    let symbolView = UIImageView().with {
        $0.contentMode = .scaleAspectFit
        $0.tintColor = .secondaryLabel
        $0.setContentHuggingPriority(.required, for: .horizontal)
    }

    let actionButton = UIButton(type: .system).with {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "ellipsis")
        configuration.contentInsets = .zero
        $0.configuration = configuration
        $0.showsMenuAsPrimaryAction = true
        $0.accessibilityLabel = String(localized: "Conversation actions")
    }

    let stopButton = UIButton(type: .system).with {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "stop.circle.fill")
        configuration.contentInsets = .zero
        $0.configuration = configuration
        $0.tintColor = .systemRed
        $0.accessibilityLabel = String(localized: "Stop Response")
        $0.isHidden = true
    }

    var onStop: (() -> Void)?

    init() {
        super.init(effect: UIBlurEffect(style: .systemThinMaterial))
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        clipsToBounds = true
        isAccessibilityElement = false
        statusLabel.isAccessibilityElement = true
        actionButton.isAccessibilityElement = true
        stopButton.isAccessibilityElement = true

        let stack = UIStackView(arrangedSubviews: [symbolView, statusLabel, stopButton, actionButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 7
        contentView.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -5),
            symbolView.widthAnchor.constraint(equalToConstant: 13),
            symbolView.heightAnchor.constraint(equalToConstant: 13),
            actionButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            actionButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            stopButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44),
            stopButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        stopButton.addAction(UIAction { [weak self] _ in self?.onStop?() }, for: .touchUpInside)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func showConnecting() {
        isHidden = false
        actionButton.isHidden = true
        stopButton.isHidden = true
        symbolView.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        symbolView.tintColor = .secondaryLabel
        statusLabel.text = String(localized: "Jonwork · Connecting")
        statusLabel.accessibilityLabel = statusLabel.text
        statusLabel.accessibilityValue = nil
    }

    func update(_ viewState: PiSessionCoordinator.ViewState) {
        isHidden = false
        actionButton.isHidden = false
        let state = viewState.conversation
        stopButton.isHidden = viewState.connection != .connected
            || state.role != .controller
            || !state.isStreaming
            || state.isReleased
        switch viewState.connection {
        case .connecting:
            showConnecting()
        case .offline:
            symbolView.image = UIImage(systemName: "wifi.slash")
            symbolView.tintColor = .systemOrange
            statusLabel.text = String(localized: "Jonwork · Offline")
        case .connected where state.isReleased:
            symbolView.image = UIImage(systemName: "terminal")
            symbolView.tintColor = .secondaryLabel
            statusLabel.text = String(localized: "Jonwork · Available on desktop")
        case .connected where state.role == .viewer:
            symbolView.image = UIImage(systemName: "eye")
            symbolView.tintColor = .systemIndigo
            statusLabel.text = state.isStreaming
                ? String(localized: "Jonwork · Read-only · Live")
                : String(localized: "Jonwork · Read-only")
        case .connected:
            symbolView.image = UIImage(systemName: state.isStreaming ? "waveform" : "checkmark.circle.fill")
            symbolView.tintColor = state.isStreaming ? .systemGreen : .tintColor
            statusLabel.text = state.isStreaming
                ? String(localized: "Jonwork · Working")
                : String(localized: "Jonwork · Ready")
        }
        statusLabel.accessibilityLabel = statusLabel.text
        if case let .offline(message) = viewState.connection {
            statusLabel.accessibilityValue = message
        } else {
            statusLabel.accessibilityValue = nil
        }
    }
}
