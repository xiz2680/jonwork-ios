import Combine
import UIKit
import WebKit

/// A result-only page. It receives no Home origin, headers, tokens or cookies.
final class HomeVisualizationController: UIViewController, WKNavigationDelegate {
    private var result: HomeVisualization?
    private let authorization: () -> Bool
    private var subscriptions: Set<AnyCancellable> = []
    private var renderTask: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var pendingStatuses: [UUID: CheckedContinuation<String, Error>] = [:]
    private let renderTimeout: Duration
    private let statusEvaluator: ((WKWebView, @escaping (String?) -> Void) -> Void)?
    private let motionPolicy: () -> Bool
    private let ruleCompiler: ((String) async throws -> WKContentRuleList?)?
    private(set) var webView: WKWebView?
    private(set) var renderReady = false
    private(set) var renderFailed = false
    private(set) var rejectedNavigations = 0
    private(set) var provisionalFailureCode: Int?
    private let indicator = UIActivityIndicatorView(style: .medium)
    private let failure = UILabel()

    init(result: HomeVisualization, authorization: @escaping () -> Bool, renderTimeout: Duration = .seconds(12), statusEvaluator: ((WKWebView, @escaping (String?) -> Void) -> Void)? = nil, ruleCompiler: ((String) async throws -> WKContentRuleList?)? = nil, motionPolicy: @escaping () -> Bool = { UIAccessibility.isReduceMotionEnabled }) {
        self.result = result
        self.authorization = authorization
        self.renderTimeout = renderTimeout
        self.statusEvaluator = statusEvaluator
        self.ruleCompiler = ruleCompiler
        self.motionPolicy = motionPolicy
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Visualization Preview")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    deinit { renderTask?.cancel(); watchdog?.cancel() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        failure.text = String(localized: "Unable to Render Preview")
        failure.font = .preferredFont(forTextStyle: .body)
        failure.adjustsFontForContentSizeCategory = true
        failure.numberOfLines = 0
        failure.textAlignment = .center
        failure.isHidden = true
        for child in [indicator, failure] {
            view.addSubview(child)
            child.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                child.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                child.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                child.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
                child.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            ])
        }
        updateMenu()
        NotificationCenter.default.publisher(for: .homeAuthorizationDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .piAuthenticationEpochDidChange))
            .sink { [weak self] _ in
                guard let self, !self.authorization() else { return }
                self.invalidate()
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIContentSizeCategory.didChangeNotification)
            .sink { [weak self] _ in
                guard let self, self.authorization() else { return }
                self.webView?.pageZoom = Double(UIFont.preferredFont(forTextStyle: .body).pointSize / 17)
            }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)
            .sink { [weak self] _ in
                guard let self, self.authorization() else { return }
                self.applyMotionPolicy(reduced: self.motionPolicy())
            }.store(in: &subscriptions)
        watchdog = Task { @MainActor [weak self, renderTimeout] in
            do { try await Task.sleep(for: renderTimeout) } catch { return }
            guard let self, !self.renderReady else { return }
            self.showFailure()
        }
        renderTask = Task { @MainActor [weak self] in await self?.loadPreview() }
    }

    private func loadPreview() async {
        guard authorization(), result != nil else { invalidate(); return }
        indicator.startAnimating()
        do {
            let rules = """
            [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},
             {"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}},
             {"trigger":{"url-filter":"^blob:"},"action":{"type":"ignore-previous-rules"}},
             {"trigger":{"url-filter":"^about:"},"action":{"type":"ignore-previous-rules"}}]
            """
            let list: WKContentRuleList?
            if let ruleCompiler { list = try await ruleCompiler(rules) }
            else {
                list = try await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "JonworkHomeOfflinePreview-v1", encodedContentRuleList: rules
                )
            }
            try Task.checkCancellation()
            guard authorization() else { throw CancellationError() }
            guard let list, let result else { throw PiServiceError.invalidResponse }
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
            configuration.userContentController.add(list)
            let web = WKWebView(frame: .zero, configuration: configuration)
            web.pageZoom = Double(UIFont.preferredFont(forTextStyle: .body).pointSize / 17)
            web.navigationDelegate = self
            web.allowsBackForwardNavigationGestures = false
            webView = web
            view.insertSubview(web, at: 0)
            web.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                web.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            ])
            let asset: String?
            switch result.kind {
            case .mermaid: asset = "home-mermaid.min"
            case .chartjs: asset = "home-chart.umd"
            default: asset = nil
            }
            let renderer: String
            if let asset {
                guard let url = Bundle.main.url(forResource: asset, withExtension: "js") else { throw PiServiceError.invalidResponse }
                renderer = try String(contentsOf: url, encoding: .utf8)
            } else { renderer = "" }
            let document = try result.document(renderer: renderer, reduceMotion: motionPolicy())
            guard authorization() else { throw CancellationError() }
            web.loadHTMLString(document, baseURL: nil)
        } catch is CancellationError {
            // A timeout keeps valid original content and its truthful failure UI.
            if !authorization() { invalidate() }
        }
        catch { showFailure() }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard authorization() else { invalidate(); return .cancel }
        // Only the initial opaque document and local fragment navigation.
        guard let url = navigationAction.request.url,
              url.absoluteString == "about:blank" || url.absoluteString.hasPrefix("about:blank#"),
              navigationAction.targetFrame?.isMainFrame == true else { rejectedNavigations += 1; return .cancel }
        return .allow
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView, authorization() else { return }
        applyMotionPolicy(reduced: motionPolicy())
        renderTask?.cancel()
        renderTask = Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            do {
                for _ in 0 ..< 100 {
                    try Task.checkCancellation()
                    guard self.authorization(), self.webView === webView else { throw CancellationError() }
                    let status = try await self.renderingStatus(on: webView)
                    guard self.authorization() else { throw CancellationError() }
                    if status == "failed" { self.showFailure(); return }
                    if self.result?.kind == .html || status == "ready" {
                        self.renderReady = true
                        self.watchdog?.cancel()
                        self.indicator.stopAnimating()
                        self.updateMenu()
                        return
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
                self.showFailure()
            } catch is CancellationError { return }
            catch { if self.authorization() { self.showFailure() } }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showFailure() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard self.webView === webView else { return }
        provisionalFailureCode = (error as NSError).code
        showFailure()
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { showFailure() }

    private func showFailure() {
        guard authorization() else { invalidate(); return }
        renderFailed = true
        dropPage()
        renderReady = false
        indicator.stopAnimating()
        failure.isHidden = false
        updateMenu()
    }

    func invalidate() {
        dropPage()
        result = nil
        renderReady = false
        renderFailed = false
        indicator.stopAnimating()
        failure.isHidden = true
        navigationItem.rightBarButtonItem = nil
        dismiss(animated: false)
    }

    private func dropPage() {
        watchdog?.cancel()
        renderTask?.cancel()
        let pending = pendingStatuses.values
        pendingStatuses.removeAll()
        for continuation in pending { continuation.resume(throwing: CancellationError()) }
        if let webView {
            webView.navigationDelegate = nil
            webView.stopLoading()
            webView.evaluateJavaScript("document.documentElement.replaceChildren()")
            webView.loadHTMLString("", baseURL: nil)
            webView.removeFromSuperview()
        }
        webView = nil
    }

    private func renderingStatus(on web: WKWebView) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            pendingStatuses[id] = continuation
            let completion: (String?) -> Void = { [weak self, weak web] value in
                guard let self, let pending = self.pendingStatuses.removeValue(forKey: id) else { return }
                guard self.authorization(), self.webView === web else { pending.resume(throwing: CancellationError()); return }
                pending.resume(returning: value ?? "failed")
            }
            if let statusEvaluator { statusEvaluator(web, completion) }
            else {
                web.evaluateJavaScript("document.documentElement.dataset.homeRender || ''") { value, error in
                    completion(error == nil ? value as? String : nil)
                }
            }
        }
    }

    private func updateMenu() {
        guard authorization(), result != nil else { navigationItem.rightBarButtonItem = nil; return }
        var actions = [
            UIAction(title: String(localized: "View Raw")) { [weak self] _ in self?.showOriginal(metadata: false) },
            UIAction(title: String(localized: "Original Metadata")) { [weak self] _ in self?.showOriginal(metadata: true) },
            UIAction(title: String(localized: "Share")) { [weak self] _ in self?.shareSource() },
        ]
        if renderReady {
            actions.append(UIAction(title: String(localized: "Share Image")) { [weak self] _ in self?.shareImage() })
        }
        navigationItem.rightBarButtonItem = .init(image: UIImage(systemName: "ellipsis"), menu: UIMenu(children: actions))
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "Actions")
    }

    func applyMotionPolicy(reduced: Bool) {
        guard authorization(), let webView else { return }
        let value = reduced ? "true" : "false"
        guard let css = try? HomeVisualization.scriptLiteral(reduced ? HomeVisualization.reducedMotionCSS : "") else { showFailure(); return }
        webView.evaluateJavaScript("(()=>{const motion=document.getElementById('home-native-motion-policy');if(motion)motion.textContent=\(css);document.querySelectorAll('canvas').forEach(c=>{const chart=globalThis.Chart?.getChart(c);if(chart){chart.stop();chart.options.animation=\(value)?false:globalThis.__homeOriginalAnimation;if(\(value))chart.update('none');else chart.update();}});})()")
    }

    private func showOriginal(metadata: Bool) {
        guard authorization(), let result else { return }
        let controller = HomeAuthorizedTextViewer(authorization: authorization)
        controller.title = String(localized: metadata ? "Original Metadata" : "Raw Content")
        controller.text = metadata ? HomeConversationActivity.jsonText(result.metadata) : result.source
        navigationController?.pushViewController(controller, animated: true)
    }

    func sourceData() -> Data? {
        guard authorization(), let result else { invalidate(); return nil }
        return Data(result.source.utf8)
    }

    private func shareSource() {
        guard let data = sourceData(), let result else { return }
        let suffix: String
        switch result.kind {
        case .svg: suffix = "svg"
        case .html: suffix = "html"
        case .chartjs: suffix = "json"
        case .mermaid: suffix = "mmd"
        }
        DisposableExporter(data: data, pathExtension: suffix).run(anchor: view, authorization: authorization)
    }

    private func shareImage() {
        guard authorization(), renderReady, let webView else { return }
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView, self.authorization() else { return }
            do {
                let image = try await webView.takeSnapshot(configuration: nil)
                guard self.authorization(), self.webView === webView, let data = image.pngData() else { return }
                DisposableExporter(data: data, pathExtension: "png").run(anchor: self.view, authorization: self.authorization)
            } catch { if self.authorization() { self.showFailure() } }
        }
    }
}

/// Retained original/code inspectors clear their text with the same authority.
final class HomeAuthorizedTextViewer: TextViewerController {
    private let authorization: () -> Bool
    private var subscriptions: Set<AnyCancellable> = []

    init(authorization: @escaping () -> Bool) {
        self.authorization = authorization
        super.init(editable: false)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        if !authorization() { clearContent(); return }
        NotificationCenter.default.publisher(for: .homeAuthorizationDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .piAuthenticationEpochDidChange))
            .sink { [weak self] _ in
                guard let self, !self.authorization() else { return }
                self.clearContent()
                self.dismiss(animated: false)
            }.store(in: &subscriptions)
    }

    private func clearContent() {
        text = ""
        textView.text = ""
        callback = { _ in }
        title = nil
        navigationItem.rightBarButtonItem = nil
    }
}
