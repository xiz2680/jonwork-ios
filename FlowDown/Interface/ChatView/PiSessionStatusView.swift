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
        $0.accessibilityLabel = String(localized: "Pi session actions")
    }

    init() {
        super.init(effect: UIBlurEffect(style: .systemThinMaterial))
        layer.cornerRadius = 22
        layer.cornerCurve = .continuous
        clipsToBounds = true

        let stack = UIStackView(arrangedSubviews: [symbolView, statusLabel, actionButton])
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
        ])
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func showConnecting() {
        isHidden = false
        actionButton.isHidden = true
        symbolView.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        symbolView.tintColor = .secondaryLabel
        statusLabel.text = String(localized: "Pi · Connecting")
        accessibilityLabel = statusLabel.text
    }

    func update(_ viewState: PiSessionCoordinator.ViewState) {
        isHidden = false
        actionButton.isHidden = false
        let state = viewState.conversation
        switch viewState.connection {
        case .connecting:
            showConnecting()
        case .offline:
            symbolView.image = UIImage(systemName: "wifi.slash")
            symbolView.tintColor = .systemOrange
            statusLabel.text = String(localized: "Pi · Offline")
        case .connected where state.isReleased:
            symbolView.image = UIImage(systemName: "terminal")
            symbolView.tintColor = .secondaryLabel
            statusLabel.text = String(localized: "Pi · Released to CLI")
        case .connected where state.role == .viewer:
            symbolView.image = UIImage(systemName: "eye")
            symbolView.tintColor = .systemIndigo
            statusLabel.text = state.isStreaming
                ? String(localized: "Pi · Viewer · Live")
                : String(localized: "Pi · Viewer")
        case .connected:
            symbolView.image = UIImage(systemName: state.isStreaming ? "waveform" : "checkmark.circle.fill")
            symbolView.tintColor = state.isStreaming ? .systemGreen : .tintColor
            statusLabel.text = state.isStreaming
                ? String(localized: "Pi · Working")
                : String(localized: "Pi · Ready")
        }
        accessibilityLabel = statusLabel.text
        if case let .offline(message) = viewState.connection {
            accessibilityValue = message
        } else {
            accessibilityValue = nil
        }
    }
}
