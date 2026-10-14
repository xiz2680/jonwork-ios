import Foundation

/// Original Home result metadata remains available separately from its preview.
struct HomeVisualization: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable { case svg, chartjs, mermaid, html }
    let kind: Kind
    let source: String
    let language: String
    let metadata: PiJSONValue

    init?(metadata: PiJSONValue?) {
        guard let metadata, let render = metadata["render_type"]?.stringValue,
              let kind = Kind(rawValue: render),
              let source = metadata["code"]?["content"]?.stringValue, !source.isEmpty else { return nil }
        self.kind = kind
        self.source = source
        language = metadata["code"]?["language"]?.stringValue ?? ""
        self.metadata = metadata
    }

    static let maximumPreviewBytes = 1_048_576
    static let reducedMotionCSS = "*{animation-duration:0s!important;transition-duration:0s!important;scroll-behavior:auto!important}"

    static func scriptLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let text = String(data: data, encoding: .utf8) else { throw PiServiceError.invalidResponse }
        return text.replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "&", with: "\\u0026")
    }

    /// No remote resources, forms, workers, files, cookies or native bridge.
    /// HTML may run its own local interaction scripts inside this isolated page.
    func document(renderer: String = "", reduceMotion: Bool) throws -> String {
        guard source.utf8.count <= Self.maximumPreviewBytes else { throw PiServiceError.invalidResponse }
        let policy = "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; font-src data:; media-src data: blob:; connect-src 'none'; frame-src 'none'; child-src 'none'; worker-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'"
        let css = "html,body{margin:0;padding:12px;background:transparent;color:CanvasText;color-scheme:light dark;font:17px -apple-system}svg{max-width:100%;height:auto}canvas{max-width:100%}a[href]:not([href^='#']){pointer-events:none}button,input,select{font:inherit}"
            + "@media(prefers-reduced-motion:reduce){" + Self.reducedMotionCSS + "}"
        let motion = reduceMotion ? Self.reducedMotionCSS : ""
        let header = "<!doctype html><html><head><meta charset='utf-8'><meta http-equiv='Content-Security-Policy' content=\"" + policy + "\"><meta name='viewport' content='width=device-width,initial-scale=1'><style>" + css + "</style><style id='home-native-motion-policy'>" + motion + "</style></head><body>"
        let errors = "<script>window.addEventListener('error',()=>{document.documentElement.dataset.homeRender='failed';},true);</script>"
        if kind == .html { return header + errors + source + "</body></html>" }
        let literal = try Self.scriptLiteral(source)
        let action: String
        switch kind {
        case .svg:
            action = "document.getElementById('result').innerHTML=source;if(!document.querySelector('#result svg'))throw Error();"
        case .mermaid:
            action = """
            const module=globalThis.mermaid || globalThis.__esbuild_esm_mermaid_nm?.mermaid;
            const engine=module?.default || module;
            engine.initialize({startOnLoad:false,securityLevel:'strict',suppressErrorRendering:true,theme:matchMedia('(prefers-color-scheme: dark)').matches?'dark':'default'});
            const rendered=await engine.render('home-diagram',source);
            document.getElementById('result').innerHTML=rendered.svg;
            """
        case .chartjs:
            // Parse data, never evaluate model-generated JavaScript expressions.
            action = """
            const config=JSON.parse(source);
            if(!config || Array.isArray(config) || typeof config.type!=='string' || !config.data || typeof config.data!=='object' || Array.isArray(config.data))throw Error();
            globalThis.__homeOriginalAnimation=config.options?.animation;
            config.options={...(config.options||{}),responsive:true,maintainAspectRatio:false};
            if(\(reduceMotion ? "true" : "false"))config.options.animation=false;
            const canvas=document.createElement('canvas');canvas.style.height='400px';
            document.getElementById('result').appendChild(canvas);
            new Chart(canvas,config);
            """
        case .html: action = ""
        }
        return header + errors + "<div id='result'></div><script>" + renderer + "</script><script>"
            + "(async()=>{const source=" + literal + ";try{" + action
            + "document.documentElement.dataset.homeRender='ready';}catch{document.getElementById('result').replaceChildren();document.documentElement.dataset.homeRender='failed';}})();"
            + "</script></body></html>"
    }
}
