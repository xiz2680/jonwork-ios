import SnapKit
import UIKit

final class PiSignInViewController: UIViewController {
    var allowsBackNavigation = true
    var onSubmit: (() -> Void)?
    var onCancelAuthentication: (() -> Void)?

    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let backgroundView = JonworkPastelBackgroundView(intensity: 0.32)
    private let errorLabel = PiSignInInsetLabel(insets: .init(top: 11, left: 12, bottom: 11, right: 12))
    private let signInButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private var isLoading = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = JonworkPastelBackgroundView.surface
        title = nil
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.hidesBackButton = true
        configureHierarchy()
        configureActions()
        backButton.isHidden = !allowsBackNavigation
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        authenticationPresentationDidDisappear(
            isLeaving: isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true
        )
    }

    func authenticationPresentationDidDisappear(isLeaving: Bool) {
        guard isLeaving, let onCancelAuthentication else { return }
        self.onCancelAuthentication = nil
        onCancelAuthentication()
    }

    func setLoading(_ loading: Bool) {
        isLoading = loading
        var configuration = signInButton.configuration ?? .filled()
        configuration.showsActivityIndicator = loading
        configuration.title = loading ? String(localized: "Signing In…") : String(localized: "Sign In with Jonwork")
        signInButton.configuration = configuration
        signInButton.isEnabled = !loading
        backButton.isEnabled = !loading
        navigationItem.hidesBackButton = true
    }

    func showError(_ error: Error) {
        errorLabel.text = Self.presentedMessage(for: error)
        errorLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: errorLabel.text)

    }

    static func presentedMessage(for error: Error) -> String {
        switch error as? PiServiceError {
        case .invalidResponse:
            String(localized: "This Jonwork server does not support iOS conversations yet. Please update the gateway and try again.")
        default:
            error.localizedDescription
        }
    }

    private func configureHierarchy() {
        view.addSubview(backgroundView)
        backgroundView.snp.makeConstraints { $0.edges.equalToSuperview() }

        view.addSubview(scrollView)
        scrollView.keyboardDismissMode = .interactive
        scrollView.alwaysBounceVertical = true
        scrollView.snp.makeConstraints { make in
            make.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
        }
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView.snp.width)
            make.height.greaterThanOrEqualTo(scrollView.snp.height)
        }

        var backConfiguration = UIButton.Configuration.plain()
        backConfiguration.image = UIImage(systemName: "chevron.left")
        backConfiguration.baseForegroundColor = .label
        backConfiguration.background.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.94)
        backConfiguration.cornerStyle = .capsule
        backButton.configuration = backConfiguration
        backButton.accessibilityLabel = String(localized: "Back")
        backButton.accessibilityIdentifier = "PiSignInBackButton"
        backButton.layer.shadowColor = UIColor.black.cgColor
        backButton.layer.shadowOpacity = 0.06
        backButton.layer.shadowRadius = 14
        backButton.layer.shadowOffset = CGSize(width: 0, height: 8)
        view.addSubview(backButton)
        backButton.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(18)
            make.leading.equalTo(view.safeAreaLayoutGuide).offset(20)
            make.width.height.equalTo(48)
        }

        let symbol = UIImageView(image: UIImage(named: "JonworkHeroJ"))
        symbol.contentMode = .scaleAspectFit
        symbol.accessibilityLabel = "Jonwork"
        let symbolRow = UIView()
        symbolRow.addSubview(symbol)
        symbol.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.height.equalTo(72)
        }
        symbolRow.snp.makeConstraints { $0.height.equalTo(72) }

        let titleLabel = UILabel()
        titleLabel.text = String(localized: "Sign In to Jonwork")
        titleLabel.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: .systemFont(ofSize: 36, weight: .bold)
        )
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0

        let subtitleLabel = UILabel()
        subtitleLabel.text = String(localized: "Continue your work and conversations.")
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0


        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.adjustsFontForContentSizeCategory = true
        errorLabel.textColor = .systemRed
        errorLabel.backgroundColor = UIColor.systemRed.withAlphaComponent(0.08)
        errorLabel.layer.cornerRadius = 12
        errorLabel.layer.cornerCurve = .continuous
        errorLabel.clipsToBounds = true
        errorLabel.accessibilityIdentifier = "PiSignInError"
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        let privacyLabel = UILabel()
        privacyLabel.text = String(localized: "Sign in securely on jonwork.com. Then return here to continue your conversations.")
        privacyLabel.font = .preferredFont(forTextStyle: .footnote)
        privacyLabel.adjustsFontForContentSizeCategory = true
        privacyLabel.textColor = .secondaryLabel
        privacyLabel.numberOfLines = 0
        privacyLabel.textAlignment = .center

        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.title = String(localized: "Sign In with Jonwork")
        buttonConfiguration.cornerStyle = .large
        buttonConfiguration.baseBackgroundColor = JonworkPastelBackgroundView.accent
        buttonConfiguration.baseForegroundColor = .white
        buttonConfiguration.contentInsets = .init(top: 14, leading: 20, bottom: 14, trailing: 20)
        signInButton.configuration = buttonConfiguration
        signInButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        signInButton.accessibilityIdentifier = "PiNativeSignInButton"
        signInButton.snp.makeConstraints { $0.height.equalTo(56) }

        let stack = UIStackView(arrangedSubviews: [
            symbolRow, titleLabel, subtitleLabel, errorLabel, signInButton, privacyLabel,
        ])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 16
        stack.setCustomSpacing(18, after: symbolRow)
        stack.setCustomSpacing(8, after: titleLabel)
        stack.setCustomSpacing(30, after: subtitleLabel)
        stack.setCustomSpacing(10, after: errorLabel)
        stack.setCustomSpacing(14, after: signInButton)
        contentView.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(94).priority(.high)
            make.top.greaterThanOrEqualToSuperview().offset(94)
            make.centerX.equalToSuperview()
            make.width.equalToSuperview().offset(-56).priority(.high)
            make.width.lessThanOrEqualTo(480)
            make.leading.greaterThanOrEqualToSuperview().offset(28)
            make.trailing.lessThanOrEqualToSuperview().offset(-28)
            make.bottom.lessThanOrEqualToSuperview().inset(24)
        }
    }

    private func configureActions() {
        signInButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)
        backButton.addAction(UIAction { [weak self] _ in self?.navigateBack() }, for: .touchUpInside)
    }

    private func navigateBack() {
        if let navigationController, navigationController.viewControllers.count > 1 {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }

    private func submit() {
        guard !isLoading else { return }
        view.endEditing(true)
        errorLabel.isHidden = true
        onSubmit?()
    }


}

private final class PiSignInInsetLabel: UILabel {
    private let insets: UIEdgeInsets

    init(insets: UIEdgeInsets) {
        self.insets = insets
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override func textRect(forBounds bounds: CGRect, limitedToNumberOfLines numberOfLines: Int) -> CGRect {
        let insetBounds = bounds.inset(by: insets)
        let rect = super.textRect(forBounds: insetBounds, limitedToNumberOfLines: numberOfLines)
        return CGRect(
            x: rect.origin.x - insets.left,
            y: rect.origin.y - insets.top,
            width: rect.width + insets.left + insets.right,
            height: rect.height + insets.top + insets.bottom
        )
    }
}
