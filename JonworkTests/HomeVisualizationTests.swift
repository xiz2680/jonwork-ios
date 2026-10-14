@testable import Jonwork
import Foundation
import Testing
import UIKit
import WebKit
import Network

@Suite(.serialized) @MainActor
struct HomeVisualizationTests {
    @Test(arguments: [HomeVisualization.Kind.svg, .mermaid, .chartjs, .html])
    func actualOfflineRendererProducesSVGCanvasOrInteractiveHTML(_ kind: HomeVisualization.Kind) async throws {
        let source: String
        switch kind {
        case .svg: source = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 120 80'><circle cx='40' cy='40' r='20'/></svg>"
        case .mermaid: source = "graph TD\nA[First]-->B[Second]"
        case .chartjs: source = #"{"type":"bar","data":{"labels":["First","Second"],"datasets":[{"label":"Actual supplied values","data":[2,5]}]}}"#
        case .html: source = "<button id='increment' onclick=\"document.getElementById('value').textContent=Number(document.getElementById('value').textContent)+1\">Increment</button><p id='value'>0</p>"
        }
        let result = try #require(HomeVisualization(metadata: .object([
            "render_type": .string(kind.rawValue), "code": .object(["content": .string(source), "language": .string(kind.rawValue)]),
        ])))
        let controller = HomeVisualizationController(result: result, authorization: { true })
        let window = try mount(controller)
        defer { controller.invalidate(); window.isHidden = true }
        try await waitUntil { controller.renderReady }
        let web = try #require(controller.webView)
        #expect(!web.configuration.websiteDataStore.isPersistent)
        #expect(web.configuration.userContentController.userScripts.isEmpty)
        #expect(controller.navigationItem.rightBarButtonItem?.accessibilityLabel == String(localized: "Actions"))
        #expect(String(data: try #require(controller.sourceData()), encoding: .utf8) == source)
        if kind == .svg || kind == .mermaid {
            #expect(try await web.evaluateJavaScript("document.querySelectorAll('svg').length") as? Int == 1)
            if kind == .mermaid { #expect(try await web.evaluateJavaScript("document.querySelectorAll('.node').length") as? Int == 2) }
        } else if kind == .chartjs {
            #expect(try await web.evaluateJavaScript("document.querySelector('canvas').width > 0") as? Bool == true)
            #expect(try await web.evaluateJavaScript("Chart.getChart(document.querySelector('canvas')).data.datasets[0].data[1]") as? Int == 5)
        } else {
            _ = try await web.evaluateJavaScript("document.getElementById('increment').click()")
            #expect(try await web.evaluateJavaScript("document.getElementById('value').textContent") as? String == "1")
        }
    }

    @Test
    func retainedPreviewAndRawInspectorClearWhenAuthorizationChanges() async throws {
        let result = try #require(HomeVisualization(metadata: .object([
            "render_type": .string("svg"), "code": .object(["content": .string("<svg xmlns='http://www.w3.org/2000/svg'><text>OLD_PRIVATE_FIXTURE</text></svg>")]),
        ])))
        var current = true
        let controller = HomeVisualizationController(result: result, authorization: { current })
        let raw = HomeAuthorizedTextViewer(authorization: { current })
        raw.text = result.source
        let rawWindow = try mount(raw)
        try await waitUntil(stage: "raw-inspector-visible") { raw.view.window != nil && raw.textView.text == result.source }
        #expect(raw.textView.text == result.source)
        let window = try mount(controller)
        defer { window.isHidden = true; rawWindow.isHidden = true }
        try await waitUntil { controller.renderReady }
        #expect(controller.sourceData() != nil)
        current = false
        NotificationCenter.default.post(name: .homeAuthorizationDidChange, object: nil)
        #expect(controller.sourceData() == nil)
        #expect(controller.webView == nil)
        #expect(!controller.renderReady)
        #expect(raw.text.isEmpty)
        #expect(raw.textView.text.isEmpty)
        #expect(raw.navigationItem.rightBarButtonItem == nil)
        #expect(controller.navigationItem.rightBarButtonItem == nil)
    }

    @Test
    func typedResultsPreserveRawMetadataAndDoNotInventUnsupportedRenderers() throws {
        let raw: PiJSONValue = .object(["render_type": .string("mermaid"), "code": .object(["content": .string("graph TD; A-->B")]), "analysis": .object(["actual_field": .string("supplied")])])
        let result = try #require(HomeVisualization(metadata: raw))
        #expect(result.metadata == raw)
        #expect(HomeVisualization(metadata: .object(["render_type": .string("unknown"), "code": .object(["content": .string("real source")])])) == nil)
        #expect(HomeVisualization(metadata: .object(["render_type": .string("svg"), "code": .object(["content": .string("")])])) == nil)
        let document = try result.document(reduceMotion: false)
        #expect(document.contains("connect-src 'none'"))
        #expect(document.contains("frame-src 'none'"))
        #expect(document.contains("form-action 'none'"))
        #expect(!document.contains("webkit.messageHandlers"))
    }

    @Test
    func dataAndBlobImagesActuallyDecodeUnderOfflinePolicy() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        #expect(image.cgImage?.width == 2)
        #expect(image.cgImage?.height == 2)
        let base64 = try #require(image.pngData()).base64EncodedString()
        let html = "<img id='data' src='data:image/png;base64," + base64 + "'><img id='blob'><script>const bytes=Uint8Array.from(atob('" + base64 + "'),c=>c.charCodeAt(0));document.getElementById('blob').src=URL.createObjectURL(new Blob([bytes],{type:'image/png'}));</script>"
        let result = try #require(HomeVisualization(metadata: .object(["render_type": .string("html"), "code": .object(["content": .string(html)])])))
        let controller = HomeVisualizationController(result: result, authorization: { true })
        let window = try mount(controller)
        defer { controller.invalidate(); window.isHidden = true }
        try await waitUntil { controller.renderReady }
        let web = try #require(controller.webView)
        try await waitForJavaScript(web, script: "['data','blob'].every(id=>document.getElementById(id).naturalWidth===2)")
    }

    @Test
    func ordinaryOutboundResourcesAndNavigationMakeZeroLoopbackRequests() async throws {
        let server = try VisualizationLoopbackServer()
        defer { server.stop() }
        try await waitUntil(stage: "loopback-ready") { server.port != nil }
        let port = try #require(server.port)
        let target = "http://127.0.0.1:" + String(port) + "/ordinary-resource"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        let probe = URLSession(configuration: configuration)
        defer { probe.invalidateAndCancel() }
        let (_, response) = try await probe.data(from: #require(URL(string: target)))
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        #expect(server.requests == 1)
        #expect(server.receivedBytes > 0)
        server.resetCounters()
        let html = "<p>Local result</p><a id='outside' href='" + target + "'>External resource</a><script>fetch('" + target + "').catch(()=>document.documentElement.dataset.fetchBlocked='yes');const image=new Image();image.src='" + target + "';</script>"
        let result = try #require(HomeVisualization(metadata: .object(["render_type": .string("html"), "code": .object(["content": .string(html)])])))
        let controller = HomeVisualizationController(result: result, authorization: { true })
        let window = try mount(controller)
        defer { controller.invalidate(); window.isHidden = true }
        try await waitUntil { controller.renderReady }
        let web = try #require(controller.webView)
        try await waitForJavaScript(web, script: "document.documentElement.dataset.fetchBlocked==='yes'")
        _ = try await web.evaluateJavaScript("document.getElementById('outside').click()")
        try await waitUntil(stage: "external-navigation-rejected") { controller.rejectedNavigations > 0 }
        try await Task.sleep(for: .milliseconds(100))
        #expect(server.requests == 0)
        #expect(server.receivedBytes == 0)
        #expect(web.configuration.userContentController.userScripts.isEmpty)
    }

    @Test(arguments: ["{type:'bar',data:{labels:[]}}", #"{"type":"bar"}"#])
    func chartRequiresActualJSONTypeAndDataAndRetainsFailedOriginal(_ source: String) async throws {
        let result = try #require(HomeVisualization(metadata: .object([
            "render_type": .string("chartjs"), "code": .object(["content": .string(source)]),
        ])))
        let controller = HomeVisualizationController(result: result, authorization: { true })
        let window = try mount(controller)
        defer { controller.invalidate(); window.isHidden = true }
        try await waitUntil(stage: "invalid-chart-failed") { controller.renderFailed }
        #expect(!controller.renderReady)
        #expect(controller.webView == nil)
        #expect(String(data: try #require(controller.sourceData()), encoding: .utf8) == source)
    }

    @Test
    func independentDeadlineDropsPageAndFencesLateStatusCompletion() async throws {
        let result = try #require(HomeVisualization(metadata: .object(["render_type": .string("svg"), "code": .object(["content": .string("<svg xmlns='http://www.w3.org/2000/svg'/>")])])))
        var suspended: ((String?) -> Void)?
        let controller = HomeVisualizationController(result: result, authorization: { true }, renderTimeout: .seconds(5), statusEvaluator: { _, completion in suspended = completion })
        let window = try mount(controller)
        defer { controller.invalidate(); window.isHidden = true }
        try await waitUntil { suspended != nil }
        try await waitUntil { controller.webView == nil }
        #expect(!controller.renderReady)
        suspended?("ready")
        #expect(!controller.renderReady)
        #expect(controller.webView == nil)
        #expect(controller.sourceData() != nil)
    }

    @Test
    func lateRuleCompilationCannotEraseTerminalTimeoutOrValidRawSource() async throws {
        let result = try #require(HomeVisualization(metadata: .object(["render_type": .string("svg"), "code": .object(["content": .string("<svg xmlns='http://www.w3.org/2000/svg'/>")])])))
        var pending: CheckedContinuation<WKContentRuleList?, Error>?
        let controller = HomeVisualizationController(result: result, authorization: { true }, renderTimeout: .milliseconds(200), ruleCompiler: { _ in
            try await withCheckedThrowingContinuation { pending = $0 }
        })
        let window = try mount(controller)
        defer { controller.invalidate(); window.isHidden = true }
        try await waitUntil { pending != nil }
        try await waitUntil { controller.renderFailed }
        #expect(controller.sourceData() != nil)
        pending?.resume(returning: nil)
        pending = nil
        try await Task.sleep(for: .milliseconds(50))
        #expect(controller.renderFailed)
        #expect(controller.sourceData() != nil)
        #expect(controller.webView == nil)
        #expect(!controller.renderReady)
    }

    @Test
    func initialReducedHTMLRestoresActualCSSDurationsAcrossLiveNotifications() async throws {
        try #require(!UIAccessibility.isReduceMotionEnabled, "This fixture requires available system motion and never changes global settings.")
        let source = "<style>@keyframes movement{to{transform:translateX(20px)}}#animated{animation:movement 2s infinite;transition:opacity 3s}</style><div id='animated'>Actual animated result</div>"
        let result = try #require(HomeVisualization(metadata: .object([
            "render_type": .string("html"), "code": .object(["content": .string(source)]),
        ])))
        var reduced = true
        let controller = HomeVisualizationController(result: result, authorization: { true }, motionPolicy: { reduced })
        let window = try mount(controller)
        defer { controller.invalidate(); window.isHidden = true }
        try await waitUntil { controller.renderReady }
        let web = try #require(controller.webView)
        let durations = "(()=>{const style=getComputedStyle(document.getElementById('animated'));return style.animationDuration+','+style.transitionDuration;})()"
        #expect(try await web.evaluateJavaScript(durations) as? String == "0s,0s")
        for value in [false, true, false] {
            reduced = value
            NotificationCenter.default.post(name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
            try await waitForJavaScript(web, script: durations + "===" + (value ? "'0s,0s'" : "'2s,3s'"))
            #expect(try await web.evaluateJavaScript(durations) as? String == (value ? "0s,0s" : "2s,3s"))
        }
    }

    @Test
    func liveMotionPolicyStopsChartAndRestoresActualConfiguredAnimation() async throws {
        let source = #"{"type":"bar","data":{"labels":["Value"],"datasets":[{"data":[3]}]},"options":{"animation":{"duration":10000}}}"#
        let result = try #require(HomeVisualization(metadata: .object(["render_type": .string("chartjs"), "code": .object(["content": .string(source)])])))
        let controller = HomeVisualizationController(result: result, authorization: { true }, motionPolicy: { true })
        let window = try mount(controller)
        defer { controller.invalidate(); window.isHidden = true }
        try await waitUntil { controller.renderReady }
        let web = try #require(controller.webView)
        #expect(try await web.evaluateJavaScript("Chart.getChart(document.querySelector('canvas')).options.animation === false") as? Bool == true)
        controller.applyMotionPolicy(reduced: false)
        #expect(try await web.evaluateJavaScript("Chart.getChart(document.querySelector('canvas')).options.animation.duration") as? Int == 10000)
        controller.applyMotionPolicy(reduced: true)
        #expect(try await web.evaluateJavaScript("Chart.getChart(document.querySelector('canvas')).options.animation === false") as? Bool == true)
        controller.applyMotionPolicy(reduced: false)
        #expect(try await web.evaluateJavaScript("Chart.getChart(document.querySelector('canvas')).options.animation.duration") as? Int == 10000)
        #expect(try await web.evaluateJavaScript("Chart.getChart(document.querySelector('canvas')).data.datasets[0].data[0]") as? Int == 3)
    }

    private func waitForJavaScript(_ web: WKWebView, script: String) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while try await web.evaluateJavaScript(script) as? Bool != true {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "HomeVisualizationTests", code: 2) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func mount(_ controller: UIViewController) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = UINavigationController(rootViewController: controller)
        window.makeKeyAndVisible()
        controller.loadViewIfNeeded()
        return window
    }

    private func waitUntil(stage: String = "render-state", _ predicate: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while !predicate() {
            guard ContinuousClock.now < deadline else { throw NSError(domain: "HomeVisualizationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: stage]) }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}


private final class VisualizationLoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "HomeVisualizationTests.loopback")
    private let lock = NSLock()
    private var requestCount = 0
    private var byteCount = 0
    private var connections: [NWConnection] = []
    private var readyPort: UInt16?

    var port: UInt16? { lock.withLock { readyPort } }
    var requests: Int { lock.withLock { requestCount } }
    var receivedBytes: Int { lock.withLock { byteCount } }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state else { return }
            self.lock.withLock { self.readyPort = self.listener.port?.rawValue }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            self.lock.withLock { self.connections.append(connection) }
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
                guard let self, let data, !data.isEmpty else { return }
                self.lock.withLock { self.requestCount += 1; self.byteCount += data.count }
                connection.send(content: Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: queue)
    }

    func resetCounters() {
        lock.withLock { requestCount = 0; byteCount = 0 }
    }

    func stop() {
        listener.cancel()
        lock.withLock { connections.forEach { $0.cancel() }; connections.removeAll() }
    }
}
