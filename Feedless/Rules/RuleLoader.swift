import Foundation
import WebKit

/// Reads Rules/<platform>/ from the bundle and turns it into WKUserScripts.
struct RuleLoader {
    let bundle: Bundle
    let platform: String

    init(platform: String, bundle: Bundle = .main) {
        self.platform = platform
        self.bundle = bundle
    }

    private var subdirectory: String { "Rules/\(platform)" }

    func loadRules() throws -> PlatformRules {
        let data = try Data(contentsOf: fileURL("manifest.json"))
        return try JSONDecoder().decode(PlatformRules.self, from: data)
    }

    func fileURL(_ name: String) throws -> URL {
        guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: subdirectory) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(subdirectory)/\(name)"])
        }
        return url
    }

    func text(_ name: String) throws -> String {
        try String(contentsOf: fileURL(name), encoding: .utf8)
    }

    /// Scripts in injection order: config prelude, CSS, then the platform JS.
    func userScripts(rules: PlatformRules, config: InjectedConfig) throws -> [WKUserScript] {
        var scripts = [WKUserScript(source: config.preludeSource(), injectionTime: .atDocumentStart, forMainFrameOnly: false)]
        if let css = rules.css {
            scripts.append(WKUserScript(source: Self.styleSource(css: try text(css)), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        if let js = rules.js {
            scripts.append(WKUserScript(source: try text(js), injectionTime: .atDocumentStart, forMainFrameOnly: false))
        }
        return scripts
    }

    static func styleSource(css: String) -> String {
        """
        (function () {
          var style = document.createElement('style');
          style.id = 'feedless-style';
          style.textContent = \(jsLiteral(css));
          (document.head || document.documentElement).appendChild(style);
        })();
        """
    }

    static func jsLiteral<T: Encodable>(_ value: T) -> String {
        let data = try! JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

/// What the page-side scripts need to know. Serialised into window.__feedless.
struct InjectedConfig: Codable, Equatable {
    var platform: String
    var feed: String
    var categories: [String: Bool]

    var attributeFlips: String {
        categories.map { id, enabled in
            enabled
                ? "document.documentElement.setAttribute('data-fl-\(id)', '');"
                : "document.documentElement.removeAttribute('data-fl-\(id)');"
        }.joined(separator: "\n")
    }

    func preludeSource() -> String {
        """
        window.__feedless = \(RuleLoader.jsLiteral(self));
        \(attributeFlips)
        """
    }

    /// Evaluated in an already loaded page when a setting changes.
    func updateSource() -> String {
        """
        \(preludeSource())
        if (typeof window.__feedlessApply === 'function') { window.__feedlessApply(window.__feedless); }
        """
    }
}
