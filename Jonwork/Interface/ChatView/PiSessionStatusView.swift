import UIKit

/// Session actions live in the conversation header, leaving the transcript unobstructed.
final class PiSessionStatusView: UIView {
    let actionButton = UIButton(type: .system).with {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "square.and.pencil")
        configuration.contentInsets = .zero
        $0.configuration = configuration
        $0.showsMenuAsPrimaryAction = false
        $0.accessibilityLabel = String(localized: "New Conversation")
        $0.accessibilityIdentifier = "JonworkNewConversation"
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
    var onNewConversation: (() -> Void)?

    init() {
        super.init(frame: .zero)
        isAccessibilityElement = false
        actionButton.isAccessibilityElement = true
        stopButton.isAccessibilityElement = true
        let stack = UIStackView(arrangedSubviews: [actionButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 0
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            actionButton.widthAnchor.constraint(equalToConstant: 44),
            actionButton.heightAnchor.constraint(equalToConstant: 44),
        ])
        stopButton.addAction(UIAction { [weak self] _ in self?.onStop?() }, for: .touchUpInside)
        actionButton.addAction(UIAction { [weak self] _ in self?.onNewConversation?() }, for: .touchUpInside)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    func showConnecting() {
        isHidden = false
        actionButton.isEnabled = false
        stopButton.isHidden = true
        actionButton.accessibilityHint = nil
    }

    func update(_ viewState: PiSessionCoordinator.ViewState) {
        isHidden = false
        actionButton.isEnabled = true
        let state = viewState.conversation
        stopButton.isHidden = viewState.connection != .connected
            || state.role != .controller || !state.isStreaming || state.isReleased
        if case let .offline(message) = viewState.connection {
            actionButton.accessibilityHint = message
        } else {
            actionButton.accessibilityHint = nil
        }
    }
}
