import AlertController
import SnapKit
import UIKit

final class WelcomePageViewController: UIViewController, UIScrollViewDelegate {
    var onComplete: (() -> Void)?
    var dismissesOnCompletion = true

    let config: Configuration
    private let pagingScrollView = UIScrollView()
    private let pageStack = UIStackView()
    private let pageControl = UIPageControl()
    private let actionContainer = UIView()
    private let actionButton = UIButton(type: .system)
    private var pageViews: [WelcomeHeroPageView] = []
    private var currentPage = 0

    private let backgroundView = JonworkPastelBackgroundView()

    init(config: Configuration = .default, onComplete: (() -> Void)? = nil) {
        self.config = config
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
        modalTransitionStyle = .crossDissolve
        isModalInPresentation = true
        preferredContentSize = .init(width: 560, height: 720)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = JonworkPastelBackgroundView.surface
        configureHierarchy()
        configurePages()
        updatePage(animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        pageViews.first?.animateIn()
    }

    private func configureHierarchy() {
        view.addSubview(backgroundView)
        backgroundView.snp.makeConstraints { $0.edges.equalToSuperview() }

        view.addSubview(actionContainer)
        actionContainer.backgroundColor = JonworkPastelBackgroundView.surface.withAlphaComponent(0.96)
        actionContainer.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }

        pagingScrollView.isPagingEnabled = true
        pagingScrollView.showsHorizontalScrollIndicator = false
        pagingScrollView.alwaysBounceHorizontal = true
        pagingScrollView.delegate = self
        pagingScrollView.accessibilityIdentifier = "JonworkOnboardingPages"
        pagingScrollView.accessibilityLabel = String(localized: "Welcome to Jonwork")
        view.addSubview(pagingScrollView)
        pagingScrollView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(actionContainer.snp.top)
        }

        pageStack.axis = .horizontal
        pageStack.alignment = .fill
        pageStack.distribution = .fillEqually
        pagingScrollView.addSubview(pageStack)
        pageStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalTo(pagingScrollView.snp.height)
        }

        pageControl.numberOfPages = config.pages.count
        pageControl.currentPage = 0
        pageControl.currentPageIndicatorTintColor = JonworkPastelBackgroundView.accent
        pageControl.pageIndicatorTintColor = UIColor.secondaryLabel.withAlphaComponent(0.18)
        pageControl.allowsContinuousInteraction = true
        pageControl.addTarget(self, action: #selector(pageControlChanged), for: .valueChanged)
        actionContainer.addSubview(pageControl)
        actionContainer.addSubview(actionButton)
        pageControl.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(18)
            make.centerY.equalTo(actionButton)
        }
        actionButton.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(14)
            make.leading.greaterThanOrEqualTo(pageControl.snp.trailing).offset(16)
            make.trailing.equalToSuperview().inset(24)
            make.bottom.equalTo(view.safeAreaLayoutGuide).inset(16)
            make.width.greaterThanOrEqualTo(158)
            make.width.lessThanOrEqualTo(236)
            make.height.equalTo(56)
        }
        var buttonConfiguration = UIButton.Configuration.filled()
        buttonConfiguration.cornerStyle = .large
        buttonConfiguration.contentInsets = .init(top: 14, leading: 22, bottom: 14, trailing: 22)
        actionButton.accessibilityIdentifier = "JonworkOnboardingContinue"
        actionButton.configuration = buttonConfiguration
        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        actionButton.titleLabel?.adjustsFontForContentSizeCategory = true
        actionButton.addTarget(self, action: #selector(handlePrimaryAction), for: .touchUpInside)
    }

    private func configurePages() {
        for page in config.pages {
            let pageView = WelcomeHeroPageView(page: page)
            pageViews.append(pageView)
            pageStack.addArrangedSubview(pageView)
            pageView.snp.makeConstraints { $0.width.equalTo(view.snp.width) }
        }
    }

    @objc private func handlePrimaryAction() {
        if currentPage < config.pages.count - 1 {
            setPage(currentPage + 1, animated: true)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return
        }
        let completion = onComplete
        onComplete = nil
        if dismissesOnCompletion {
            dismiss(animated: true) { completion?() }
        } else {
            completion?()
        }
    }

    @objc private func pageControlChanged() {
        setPage(pageControl.currentPage, animated: true)
    }

    private func setPage(_ page: Int, animated: Bool) {
        guard config.pages.indices.contains(page) else { return }
        pagingScrollView.setContentOffset(
            CGPoint(x: CGFloat(page) * pagingScrollView.bounds.width, y: 0),
            animated: animated && !UIAccessibility.isReduceMotionEnabled
        )
        currentPage = page
        updatePage(animated: animated)
    }

    private func updatePage(animated: Bool) {
        guard config.pages.indices.contains(currentPage) else { return }
        pageControl.currentPage = currentPage
        let isLast = currentPage == config.pages.count - 1
        var buttonConfiguration = actionButton.configuration ?? .filled()
        buttonConfiguration.title = String(localized: isLast ? config.finalButtonTitle : config.nextButtonTitle)
        buttonConfiguration.image = UIImage(systemName: isLast ? "arrow.right.circle.fill" : "arrow.right")
        buttonConfiguration.imagePlacement = .trailing
        buttonConfiguration.imagePadding = 8
        buttonConfiguration.baseBackgroundColor = JonworkPastelBackgroundView.accent
        buttonConfiguration.baseForegroundColor = .white
        actionButton.accessibilityIdentifier = "JonworkOnboardingContinue"
        actionButton.configuration = buttonConfiguration
        pageViews[currentPage].animateIn()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === pagingScrollView, scrollView.bounds.width > 0 else { return }
        currentPage = min(
            max(Int(round(scrollView.contentOffset.x / scrollView.bounds.width)), 0),
            config.pages.count - 1
        )
        updatePage(animated: true)
    }
}

private final class WelcomeHeroPageView: UIView {
    private let page: WelcomePageViewController.Page
    private let hero = UIView()
    private let copyStack = UIStackView()
    private var hasAnimated = false

    init(page: WelcomePageViewController.Page) {
        self.page = page
        super.init(frame: .zero)
        configure()
        registerForTraitChanges([
            UITraitUserInterfaceStyle.self,
            UITraitAccessibilityContrast.self,
        ]) { (view: WelcomeHeroPageView, _) in
            view.refreshLayerColors()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { nil }

    func animateIn() {
        guard !hasAnimated else { return }
        hasAnimated = true
        guard !UIAccessibility.isReduceMotionEnabled else {
            hero.alpha = 1
            copyStack.alpha = 1
            return
        }
        hero.alpha = 0
        hero.transform = CGAffineTransform(scaleX: 0.82, y: 0.82).translatedBy(x: 0, y: 18)
        copyStack.alpha = 0
        copyStack.transform = CGAffineTransform(translationX: 0, y: 22)
        UIView.animate(
            withDuration: 0.72,
            delay: 0.05,
            usingSpringWithDamping: 0.78,
            initialSpringVelocity: 0.25,
            options: [.curveEaseOut]
        ) {
            self.hero.alpha = 1
            self.hero.transform = .identity
        }
        UIView.animate(withDuration: 0.55, delay: 0.18, options: [.curveEaseOut]) {
            self.copyStack.alpha = 1
            self.copyStack.transform = .identity
        }
    }

    private func configure() {
        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        addSubview(scroll)
        scroll.snp.makeConstraints { $0.edges.equalTo(safeAreaLayoutGuide) }
        let content = UIView()
        scroll.addSubview(content)
        content.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scroll.snp.width)
            make.height.greaterThanOrEqualTo(scroll.snp.height)
        }

        let isBrandHero = page.symbol == "JonworkHeroJ"
        hero.backgroundColor = isBrandHero ? .clear : UIColor.systemBackground.withAlphaComponent(0.88)
        hero.layer.cornerRadius = isBrandHero ? 0 : 42
        hero.layer.cornerCurve = .continuous
        hero.layer.shadowColor = page.accentColor.cgColor
        hero.layer.shadowOpacity = isBrandHero ? 0 : 0.08
        hero.layer.shadowRadius = 28
        hero.layer.shadowOffset = CGSize(width: 0, height: 14)
        let symbolImage = isBrandHero ? UIImage(named: page.symbol) : UIImage(systemName: page.symbol)
        let symbol = UIImageView(image: symbolImage)
        symbol.tintColor = isBrandHero ? nil : page.accentColor
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 62, weight: .medium)
        symbol.contentMode = .scaleAspectFit
        hero.addSubview(symbol)
        symbol.snp.makeConstraints { make in
            make.center.equalToSuperview()
            if isBrandHero {
                make.edges.equalToSuperview()
            } else {
                make.width.height.lessThanOrEqualTo(80)
            }
        }
        hero.snp.makeConstraints { make in
            make.width.height.equalTo(isBrandHero ? 248 : 152)
        }

        let title = UILabel()
        title.numberOfLines = 0
        title.textAlignment = .center
        title.adjustsFontForContentSizeCategory = true
        title.text = String(localized: page.title)
        title.textColor = .label
        title.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: .systemFont(ofSize: 40, weight: .bold)
        )

        let subtitle = UILabel()
        subtitle.text = String(localized: page.subtitle)
        subtitle.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 18, weight: .regular)
        )
        subtitle.adjustsFontForContentSizeCategory = true
        subtitle.textColor = .secondaryLabel
        subtitle.numberOfLines = 0
        subtitle.textAlignment = .center

        copyStack.axis = .vertical
        copyStack.alignment = .fill
        copyStack.spacing = 14
        copyStack.addArrangedSubview(title)
        copyStack.addArrangedSubview(subtitle)

        let stack = UIStackView(arrangedSubviews: [hero, copyStack])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 28
        content.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.centerY.equalToSuperview().offset(-4).priority(.high)
            make.top.greaterThanOrEqualToSuperview().offset(24)
            make.bottom.lessThanOrEqualToSuperview().offset(-24)
            make.leading.trailing.equalToSuperview().inset(28)
        }
        copyStack.snp.makeConstraints {
            $0.width.equalToSuperview().priority(.high)
            $0.width.lessThanOrEqualTo(380)
        }
        refreshLayerColors()
    }

    private func refreshLayerColors() {
        hero.layer.shadowColor = page.accentColor.cgColor
    }
}

extension WelcomePageViewController {
    static func makePresentedController(
        config: Configuration = .default,
        onComplete: (() -> Void)? = nil
    ) -> UIViewController {
        let controller = WelcomePageViewController(config: config, onComplete: onComplete)
        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.setNavigationBarHidden(true, animated: false)
        navigationController.isModalInPresentation = true
        navigationController.preferredContentSize = controller.preferredContentSize
        #if targetEnvironment(macCatalyst)
            return AlertBaseController(
                rootViewController: navigationController,
                preferredWidth: controller.preferredContentSize.width,
                preferredHeight: controller.preferredContentSize.height
            )
        #else
            navigationController.modalPresentationStyle = .fullScreen
            navigationController.modalTransitionStyle = .crossDissolve
            return navigationController
        #endif
    }
}
