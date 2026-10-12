//
//  HTMLPreviewController.swift
//  FlowDown
//
//  Created by 秋星桥 on 6/28/25.
//

import UIKit
import WebKit

class HTMLPreviewController: UIViewController, WKNavigationDelegate {
    let contnt: String
    init(content: String) {
        contnt = content
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Preview")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    let indicator = UIActivityIndicatorView(style: .medium)
    var webView: WKWebView?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        view.addSubview(indicator)
        indicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        indicator.startAnimating()

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        view.addSubview(webView)
        webView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        webView.loadHTMLString(contnt, baseURL: nil)
        webView.alpha = 0
        webView.navigationDelegate = self
        self.webView = webView

        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(
                barButtonSystemItem: .done,
                target: self,
                action: #selector(done),
            ),
        ]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        UIView.animate(withDuration: 0.3) {
            self.webView?.alpha = 1
            self.indicator.alpha = 0
        } completion: { _ in
            self.indicator.removeFromSuperview()
        }
    }

    @objc func done() {
        dispose()
    }

    @objc func dispose() {
        if navigationController?.viewControllers.count == 1 {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
}
