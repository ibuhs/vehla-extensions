import Darwin
import Foundation

actor WebTools {
    private let cli = CLIProcessRunner()
    private var serverPID: Int32?
    private var serverDir: URL?

    func run(_ request: ToolRequest) async throws -> ToolOutput {
        switch request.toolID {
        case "web.htmlPlayground":
            let html = previewDocument(body: request.primary, css: "", js: "")
            return ToolOutput(html, meta: "live preview", previewHTML: html)
        case "web.cssPlayground":
            let html = previewDocument(
                body: request.secondary.isEmpty ? "<div class=\"box\">Hello</div>" : request.secondary,
                css: request.primary,
                js: ""
            )
            return ToolOutput(html, meta: "live preview", previewHTML: html)
        case "web.jsPlayground":
            let html = previewDocument(
                body: request.secondary.isEmpty
                    ? "<button id=\"go\">Run</button><pre id=\"out\"></pre>"
                    : request.secondary,
                css: "",
                js: request.primary
            )
            return ToolOutput(html, meta: "live preview", previewHTML: html)
        case "web.liveServer":
            return try await liveServer(request, https: false)
        case "web.httpsServer":
            return try await liveServer(request, https: true)
        case "web.cors":
            return try await corsTest(request)
        case "web.cookieEditor":
            return ToolOutput(cookieEditor(request.primary))
        case "web.localStorage", "web.sessionStorage":
            return try storageTool(request, kind: request.toolID.contains("session") ? "sessionStorage" : "localStorage")
        case "web.indexedDB":
            return try indexedDBTool(request)
        case "web.serviceWorker":
            return serviceWorkerTool(request.primary)
        case "web.manifest":
            return try ToolOutput(manifestValidate(request.primary))
        case "web.robotsValidate":
            return ToolOutput(robotsValidate(request.primary))
        case "web.sitemapValidate":
            return ToolOutput(sitemapValidate(request.primary))
        case "web.lighthouse":
            return try await lighthouse(request)
        case "web.a11y":
            return try await a11y(request)
        case "web.contrast":
            return try ToolOutput(contrast(request.primary, request.secondary))
        case "web.specificity":
            return ToolOutput(specificity(request.primary))
        case "web.flexbox":
            return flexbox(request)
        case "web.grid":
            return grid(request)
        default:
            throw ToolError.unknownTool(request.toolID)
        }
    }

    private func previewDocument(body: String, css: String, js: String) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8" />
          <meta name="viewport" content="width=device-width, initial-scale=1" />
          <title>Toolbox Playground</title>
          <style>
            body { font-family: ui-sans-serif, system-ui, sans-serif; margin: 2rem; }
            \(css)
          </style>
        </head>
        <body>
          \(body)
          <script>
          \(js)
          </script>
        </body>
        </html>
        """
    }

    private func liveServer(_ request: ToolRequest, https: Bool) async throws -> ToolOutput {
        let action = (request.options["action"] ?? "start").lowercased()
        if action == "stop" {
            if let pid = serverPID {
                kill(pid, SIGTERM)
                serverPID = nil
            }
            if let dir = serverDir {
                try? FileManager.default.removeItem(at: dir)
                serverDir = nil
            }
            return ToolOutput("Local server stopped.")
        }
        guard let python = await cli.which("python3") else {
            throw ToolError.failed("python3 not found on PATH.")
        }
        let port = Int(request.options["port"] ?? (https ? "8443" : "8787")) ?? (https ? 8443 : 8787)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("toolbox-web-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let html = request.primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "<!doctype html><h1>Toolbox Live Server</h1>"
            : (request.primary.contains("<html") ? request.primary : previewDocument(body: request.primary, css: "", js: ""))
        try html.write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        if let old = serverPID { kill(old, SIGTERM) }
        serverDir = dir

        if https {
            guard let openssl = await cli.which("openssl") else {
                throw ToolError.failed("openssl not found on PATH (needed for local HTTPS certs).")
            }
            let keyURL = dir.appendingPathComponent("key.pem")
            let certURL = dir.appendingPathComponent("cert.pem")
            let certResult = try await cli.run(
                executable: openssl,
                arguments: [
                    "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                    "-keyout", keyURL.path,
                    "-out", certURL.path,
                    "-days", "1",
                    "-subj", "/CN=localhost",
                ],
                timeoutSeconds: 20
            )
            if certResult.exitCode != 0 {
                throw ToolError.failed(certResult.stderr.isEmpty ? certResult.stdout : certResult.stderr)
            }
            let serverPy = dir.appendingPathComponent("https_server.py")
            let script = """
            import http.server, ssl, sys
            port = int(sys.argv[1])
            handler = http.server.SimpleHTTPRequestHandler
            httpd = http.server.HTTPServer(("127.0.0.1", port), handler)
            ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
            ctx.load_cert_chain(certfile="cert.pem", keyfile="key.pem")
            httpd.socket = ctx.wrap_socket(httpd.socket, server_side=True)
            print(f"serving https://127.0.0.1:{port}/", flush=True)
            httpd.serve_forever()
            """
            try script.write(to: serverPy, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [serverPy.path, String(port)]
            process.currentDirectoryURL = dir
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            serverPID = process.processIdentifier
            return ToolOutput(
                [
                    "Serving \(dir.path) over HTTPS",
                    "URL: https://127.0.0.1:\(port)/",
                    "PID: \(process.processIdentifier)",
                    "Cert: \(certURL.path)",
                    "Trust warning: self-signed cert for localhost — accept in the browser.",
                    "Set action=stop to terminate.",
                ].joined(separator: "\n"),
                meta: "https server",
                previewHTML: html
            )
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = ["-m", "http.server", String(port), "--bind", "127.0.0.1"]
        process.currentDirectoryURL = dir
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        serverPID = process.processIdentifier
        return ToolOutput(
            [
                "Serving \(dir.path)",
                "URL: http://127.0.0.1:\(port)/",
                "PID: \(process.processIdentifier)",
                "Set action=stop to terminate.",
            ].joined(separator: "\n"),
            meta: "live server",
            previewHTML: html
        )
    }

    private func corsTest(_ request: ToolRequest) async throws -> ToolOutput {
        let urlString = request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: urlString), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            throw ToolError.invalidInput("Enter an http(s) URL.")
        }
        let origin = request.options["origin"] ?? "https://example.com"
        let method = (request.options["method"] ?? "GET").uppercased()
        var req = URLRequest(url: url)
        req.httpMethod = method == "GET" ? "OPTIONS" : "OPTIONS"
        req.setValue(origin, forHTTPHeaderField: "Origin")
        req.setValue(method, forHTTPHeaderField: "Access-Control-Request-Method")
        req.timeoutInterval = 12
        let (_, response) = try await URLSession.shared.data(for: req)
        let http = response as? HTTPURLResponse
        let headers = http?.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            if let key = pair.key as? String {
                result[key] = String(describing: pair.value)
            }
        } ?? [:]
        let interesting = headers.filter {
            $0.key.lowercased().contains("access-control") || $0.key.lowercased() == "vary"
        }
        var lines = [
            "URL: \(urlString)",
            "probe: OPTIONS",
            "status: \(http?.statusCode ?? 0)",
            "Origin: \(origin)",
        ]
        if interesting.isEmpty {
            lines.append("No CORS headers returned.")
        } else {
            lines.append("CORS headers:")
            for key in interesting.keys.sorted() {
                lines.append("  \(key): \(interesting[key] ?? "")")
            }
        }
        return ToolOutput(lines.joined(separator: "\n"))
    }

    private func cookieEditor(_ text: String) -> String {
        let pairs = text.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var map: [(String, String)] = []
        for pair in pairs {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 { map.append((parts[0], parts[1])) }
            else { map.append((parts[0], "")) }
        }
        var lines = ["Parsed \(map.count) cookie(s):"]
        for (name, value) in map { lines.append("• \(name) = \(value)") }
        lines.append("")
        lines.append("Rebuilt:")
        lines.append(map.map { "\($0.0)=\($0.1)" }.joined(separator: "; "))
        return lines.joined(separator: "\n")
    }

    private func storageTool(_ request: ToolRequest, kind: String) throws -> ToolOutput {
        let text = request.primary
        try ToolLimits.guardSize(text)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            guard let data = trimmed.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw ToolError.invalidInput("Provide a JSON object dump of \(kind), or HTML to probe live.")
            }
            let keys = object.keys.sorted()
            var lines = ["\(kind) export · \(keys.count) key(s)"]
            for key in keys {
                let value = String(describing: object[key] ?? "")
                let preview = value.count > 120 ? String(value.prefix(120)) + "…" : value
                lines.append("• \(key) = \(preview)")
            }
            return ToolOutput(lines.joined(separator: "\n"), meta: "json export")
        }
        let body = trimmed.isEmpty ? "<p>Storage probe page</p>" : trimmed
        let html = storageProbeDocument(body: body, kind: kind)
        return ToolOutput(
            "Live \(kind) probe loaded in Preview. Keys appear on the page for this origin.",
            meta: "live probe",
            previewHTML: html
        )
    }

    private func indexedDBTool(_ request: ToolRequest) throws -> ToolOutput {
        let text = request.primary
        try ToolLimits.guardSize(text)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            guard let data = trimmed.data(using: .utf8),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                throw ToolError.invalidInput("Provide IndexedDB export JSON, or HTML to probe live.")
            }
            var lines = ["IndexedDB export summary"]
            for key in object.keys.sorted() {
                let value = object[key]
                if let array = value as? [Any] {
                    lines.append("• \(key): array (\(array.count) records)")
                } else if let dict = value as? [String: Any] {
                    lines.append("• \(key): object (\(dict.count) keys)")
                } else {
                    lines.append("• \(key): \(type(of: value as Any))")
                }
            }
            return ToolOutput(lines.joined(separator: "\n"), meta: "json export")
        }
        let body = trimmed.isEmpty ? "<p>IndexedDB probe page</p>" : trimmed
        let html = indexedDBProbeDocument(body: body)
        return ToolOutput(
            "Live IndexedDB probe loaded in Preview. Database names/stores appear on the page.",
            meta: "live probe",
            previewHTML: html
        )
    }

    private func storageProbeDocument(body: String, kind: String) -> String {
        let api = kind == "sessionStorage" ? "sessionStorage" : "localStorage"
        return previewDocument(
            body: """
            \(body)
            <hr /><h3>\(api) dump</h3><pre id="toolbox-dump">Loading…</pre>
            """,
            css: "pre { white-space: pre-wrap; font: 12px ui-monospace, monospace; }",
            js: """
            (function() {
              const out = document.getElementById('toolbox-dump');
              try {
                const data = {};
                for (let i = 0; i < \(api).length; i++) {
                  const k = \(api).key(i);
                  data[k] = \(api).getItem(k);
                }
                out.textContent = JSON.stringify(data, null, 2);
              } catch (e) {
                out.textContent = String(e);
              }
            })();
            """
        )
    }

    private func indexedDBProbeDocument(body: String) -> String {
        previewDocument(
            body: """
            \(body)
            <hr /><h3>IndexedDB dump</h3><pre id="toolbox-dump">Loading…</pre>
            """,
            css: "pre { white-space: pre-wrap; font: 12px ui-monospace, monospace; }",
            js: """
            (async function() {
              const out = document.getElementById('toolbox-dump');
              try {
                if (!indexedDB.databases) {
                  out.textContent = 'indexedDB.databases() is unavailable in this WebKit build.';
                  return;
                }
                const dbs = await indexedDB.databases();
                const report = [];
                for (const info of dbs) {
                  const name = info.name;
                  if (!name) continue;
                  const entry = { name, version: info.version, stores: {} };
                  await new Promise((resolve, reject) => {
                    const req = indexedDB.open(name);
                    req.onerror = () => reject(req.error);
                    req.onsuccess = () => {
                      const db = req.result;
                      Promise.all([...db.objectStoreNames].map(storeName => new Promise((res) => {
                        const tx = db.transaction(storeName, 'readonly');
                        const store = tx.objectStore(storeName);
                        const getAll = store.getAll();
                        getAll.onsuccess = () => {
                          entry.stores[storeName] = getAll.result;
                          res();
                        };
                        getAll.onerror = () => {
                          entry.stores[storeName] = { error: String(getAll.error) };
                          res();
                        };
                      }))).then(() => { db.close(); resolve(); }).catch(reject);
                    };
                  });
                  report.push(entry);
                }
                out.textContent = JSON.stringify(report, null, 2);
              } catch (e) {
                out.textContent = String(e);
              }
            })();
            """
        )
    }

    private func serviceWorkerTool(_ text: String) -> ToolOutput {
        let analysis = serviceWorkerAnalyze(text)
        let html = """
        <!doctype html><html><head><meta charset="utf-8"/>
        <style>
          body { font: 14px/1.5 ui-sans-serif, system-ui, sans-serif; margin: 1.25rem; background: #0f172a; color: #e2e8f0; }
          pre { background: #111827; padding: 0.75rem; border-radius: 8px; overflow: auto; }
          .ok { color: #86efac; } .warn { color: #fbbf24; }
          code { color: #93c5fd; }
        </style></head><body>
        <h2>Service Worker analysis</h2>
        <pre>\(htmlEscape(analysis))</pre>
        <h3>Registration probe</h3>
        <pre id="out">Checking…</pre>
        <script>
        (async () => {
          const out = document.getElementById('out');
          if (!('serviceWorker' in navigator)) {
            out.textContent = 'This WebKit build does not expose navigator.serviceWorker.';
            return;
          }
          try {
            const regs = await navigator.serviceWorker.getRegistrations();
            out.textContent = 'Active registrations: ' + regs.length + '\\n' +
              regs.map(r => r.scope + ' → ' + (r.active && r.active.scriptURL)).join('\\n');
          } catch (e) {
            out.textContent = String(e);
          }
        })();
        </script>
        </body></html>
        """
        return ToolOutput(analysis, meta: "service worker", previewHTML: html)
    }

    private func serviceWorkerAnalyze(_ text: String) -> String {
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        let events = ["install", "activate", "fetch", "sync", "push", "message", "notificationclick"].compactMap { name -> String? in
            let patterns = [
                "addEventListener('\(name)'",
                "addEventListener(\"\(name)\"",
                "on\(name)",
                "self.addEventListener('\(name)'",
                "self.addEventListener(\"\(name)\"",
            ]
            return patterns.contains(where: text.contains) ? name : nil
        }
        var findings: [String] = [
            "lines: \(lines.count)",
            "chars: \(text.count)",
            "event listeners: \(events.isEmpty ? "none detected" : events.joined(separator: ", "))",
        ]
        let checks: [(String, String, String)] = [
            ("caches", "Cache Storage API", "uses caches.*"),
            ("cache.addAll", "precaching via cache.addAll", "precaching"),
            ("skipWaiting", "skipWaiting()", "skipWaiting"),
            ("clients.claim", "clients.claim()", "clients.claim"),
            ("respondWith", "fetch respondWith", "respondWith"),
            ("fetch(", "network fetch()", "fetch calls"),
            ("importScripts", "importScripts", "importScripts"),
            ("registration.showNotification", "notifications", "notifications"),
        ]
        for (needle, label, _) in checks {
            findings.append(text.contains(needle) ? "✓ \(label)" : "• \(label): not detected")
        }
        if text.contains("networkFirst") || text.contains("cacheFirst") || text.contains("staleWhileRevalidate") {
            findings.append("✓ workbox-style strategy names detected")
        }
        let urls = text.split(whereSeparator: { !"\"'".contains($0) })
            .map(String.init)
            .filter { $0.hasPrefix("http") || $0.hasSuffix(".js") || $0.hasSuffix(".css") || $0.hasSuffix(".png") }
        if !urls.isEmpty {
            findings.append("")
            findings.append("Referenced assets (heuristic):")
            findings.append(contentsOf: Array(Set(urls)).sorted().prefix(20).map { "  - \($0)" })
        }
        return findings.joined(separator: "\n")
    }

    private func htmlEscape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private func manifestValidate(_ text: String) throws -> String {
        try ToolLimits.guardSize(text)
        guard let data = text.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ToolError.invalidInput("manifest.json must be a JSON object.")
        }
        let required = ["name", "short_name", "start_url", "display", "icons"]
        var lines: [String] = []
        for key in required {
            lines.append(object[key] == nil ? "✗ missing \(key)" : "✓ \(key)")
        }
        if let display = object["display"] as? String {
            let allowed = ["fullscreen", "standalone", "minimal-ui", "browser"]
            lines.append(allowed.contains(display) ? "✓ display value" : "✗ invalid display")
        }
        return lines.joined(separator: "\n")
    }

    private func robotsValidate(_ text: String) -> String {
        var issues: [String] = []
        var hasUserAgent = false
        for (index, raw) in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let lower = line.lowercased()
            if lower.hasPrefix("user-agent:") { hasUserAgent = true; continue }
            if !(lower.hasPrefix("allow:") || lower.hasPrefix("disallow:") || lower.hasPrefix("sitemap:") || lower.hasPrefix("crawl-delay:")) {
                issues.append("line \(index + 1): unrecognized directive")
            }
        }
        if !hasUserAgent { issues.append("missing User-agent directive") }
        return issues.isEmpty ? "Valid robots.txt (basic checks passed)." : issues.joined(separator: "\n")
    }

    private func sitemapValidate(_ text: String) -> String {
        var issues: [String] = []
        if !text.contains("<urlset") { issues.append("missing <urlset>") }
        if !text.contains("<url>") { issues.append("missing <url> entries") }
        if !text.contains("<loc>") { issues.append("missing <loc>") }
        let locs = text.components(separatedBy: "<loc>").count - 1
        if issues.isEmpty {
            return "Valid sitemap shape. loc entries: \(max(locs, 0))"
        }
        return issues.joined(separator: "\n")
    }

    private func lighthouse(_ request: ToolRequest) async throws -> ToolOutput {
        guard let bin = await cli.which("lighthouse") else {
            throw ToolError.failed("lighthouse not found on PATH. Install with npm i -g lighthouse.")
        }
        let url = request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { throw ToolError.invalidInput("Enter a URL.") }
        let preset = request.options["preset"] ?? "desktop"
        let result = try await cli.run(
            executable: bin,
            arguments: [url, "--quiet", "--chrome-flags=--headless", "--preset=\(preset)", "--output=json"],
            timeoutSeconds: 90
        )
        let body = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        if result.exitCode != 0 { throw ToolError.failed(body) }
        return ToolOutput(summarizeLighthouseJSON(body), meta: "lighthouse \(preset)")
    }

    private func summarizeLighthouseJSON(_ json: String) -> String {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let categories = root["categories"] as? [String: Any]
        else {
            return ToolLimits.truncate(json)
        }
        var lines = ["Lighthouse scores"]
        for key in ["performance", "accessibility", "best-practices", "seo", "pwa"] {
            guard let cat = categories[key] as? [String: Any] else { continue }
            let title = (cat["title"] as? String) ?? key
            let score = cat["score"] as? Double
            if let score {
                lines.append(String(format: "• %@: %.0f", title, score * 100))
            } else {
                lines.append("• \(title): n/a")
            }
        }
        if let audits = root["audits"] as? [String: Any] {
            var failed: [String] = []
            for (id, value) in audits {
                guard let audit = value as? [String: Any],
                      let score = audit["score"] as? Double,
                      score < 1,
                      let title = audit["title"] as? String
                else { continue }
                failed.append("• \(title) (\(id))")
                if failed.count >= 12 { break }
            }
            if !failed.isEmpty {
                lines.append("")
                lines.append("Top failing audits:")
                lines.append(contentsOf: failed)
            }
        }
        lines.append("")
        lines.append("--- raw JSON (truncated) ---")
        lines.append(ToolLimits.truncate(json))
        return lines.joined(separator: "\n")
    }

    private func a11y(_ request: ToolRequest) async throws -> ToolOutput {
        let html = request.primary
        try ToolLimits.guardSize(html)
        if let axe = await cli.which("axe") {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("toolbox-a11y-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("page.html")
            let document = html.lowercased().contains("<html") ? html : previewDocument(body: html, css: "", js: "")
            try document.write(to: file, atomically: true, encoding: .utf8)
            let result = try await cli.run(
                executable: axe,
                arguments: [file.path, "--stdout"],
                timeoutSeconds: 45
            )
            let body = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
            if result.exitCode == 0 || !result.stdout.isEmpty {
                return ToolOutput(ToolLimits.truncate(body), meta: "axe-core")
            }
        }
        return ToolOutput(staticA11y(html), meta: "static heuristics")
    }

    private func staticA11y(_ html: String) -> String {
        var issues: [String] = []
        if html.range(of: #"<img(?![^>]*alt=)"#, options: .regularExpression) != nil {
            issues.append("Image without alt attribute")
        }
        if html.range(of: #"<html(?![^>]*lang=)"#, options: .regularExpression) != nil {
            issues.append("html missing lang")
        }
        if !html.lowercased().contains("<title") { issues.append("missing <title>") }
        if html.range(of: #"<input(?![^>]*(aria-label|id|name)=)"#, options: .regularExpression) != nil {
            issues.append("input may be missing label/aria-label/name")
        }
        if html.range(of: #"<a(?![^>]*href=)"#, options: .regularExpression) != nil {
            issues.append("anchor without href")
        }
        if html.range(of: #"<button[^>]*>\s*</button>"#, options: .regularExpression) != nil {
            issues.append("empty button")
        }
        if html.lowercased().contains("onclick=") && !html.lowercased().contains("<button") {
            issues.append("click handlers on non-button elements detected")
        }
        let h1 = html.components(separatedBy: "<h1").count - 1
        if h1 == 0 { issues.append("no h1 heading") }
        if h1 > 1 { issues.append("multiple h1 headings (\(h1))") }
        let header = issues.isEmpty
            ? "No basic accessibility issues detected."
            : issues.map { "• \($0)" }.joined(separator: "\n")
        return header + "\n\n(Install axe-core CLI for fuller checks: npm i -g @axe-core/cli)"
    }

    private func contrast(_ fgText: String, _ bgText: String) throws -> String {
        guard let fg = parseHex(fgText), let bg = parseHex(bgText) else {
            throw ToolError.invalidInput("Provide foreground and background hex colors.")
        }
        let ratio = contrastRatio(fg, bg)
        let aa = ratio >= 4.5 ? "pass" : "fail"
        let aaa = ratio >= 7.0 ? "pass" : "fail"
        let aaLarge = ratio >= 3.0 ? "pass" : "fail"
        return String(
            format: "contrast: %.2f:1\nWCAG AA normal: %@\nWCAG AA large: %@\nWCAG AAA normal: %@",
            ratio, aa, aaLarge, aaa
        )
    }

    private func specificity(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).map { raw -> String in
            let selector = raw.trimmingCharacters(in: .whitespaces)
            guard !selector.isEmpty else { return "" }
            let ids = countMatches(selector, pattern: "#[A-Za-z0-9_-]+")
            let classes = countMatches(selector, pattern: "\\.[A-Za-z0-9_-]+")
                + countMatches(selector, pattern: "\\[[^\\]]+\\]")
                + countMatches(selector, pattern: ":[A-Za-z0-9_-]+")
            let elements = countMatches(selector, pattern: "(^|[\\s>+~])[A-Za-z][A-Za-z0-9_-]*")
            return "\(selector) → (\(ids),\(classes),\(elements))"
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private func countMatches(_ text: String, pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, range: range)
    }

    private func flexbox(_ request: ToolRequest) -> ToolOutput {
        let direction = request.options["direction"] ?? "row"
        let justify = request.options["justify"] ?? "space-between"
        let align = request.options["align"] ?? "center"
        let items = max(1, min(8, Int(request.options["items"] ?? "3") ?? 3))
        let css = """
        .row {
          display: flex;
          flex-direction: \(direction);
          justify-content: \(justify);
          align-items: \(align);
          gap: 12px;
          min-height: 180px;
          padding: 16px;
          border: 1px dashed #94a3b8;
          border-radius: 12px;
          background: #f8fafc;
        }
        .row > div {
          flex: 0 0 auto;
          min-width: 64px;
          padding: 18px 14px;
          border-radius: 10px;
          background: #0ea5e9;
          color: white;
          font: 600 13px/1.2 ui-sans-serif, system-ui, sans-serif;
          text-align: center;
          box-shadow: 0 8px 18px rgba(14,165,233,0.25);
        }
        """
        let body = """
        <div class="row">
        \((1...items).map { "<div>Item \($0)</div>" }.joined(separator: "\n"))
        </div>
        """
        let html = previewDocument(body: body, css: css, js: "")
        let text = """
        CSS:
        \(css)

        Items: \(items)
        flex-direction: \(direction)
        justify-content: \(justify)
        align-items: \(align)
        """
        return ToolOutput(text, meta: "live flex preview", previewHTML: html)
    }

    private func grid(_ request: ToolRequest) -> ToolOutput {
        let cols = max(1, min(8, Int(request.options["cols"] ?? "3") ?? 3))
        let rows = max(1, min(8, Int(request.options["rows"] ?? "2") ?? 2))
        let gap = request.options["gap"] ?? "12px"
        let cellCount = cols * rows
        let css = """
        .grid {
          display: grid;
          grid-template-columns: repeat(\(cols), 1fr);
          grid-template-rows: repeat(\(rows), minmax(72px, auto));
          gap: \(gap);
          padding: 16px;
          border: 1px dashed #94a3b8;
          border-radius: 12px;
          background: #f8fafc;
        }
        .grid > div {
          display: grid;
          place-items: center;
          border-radius: 10px;
          background: #6366f1;
          color: white;
          font: 600 13px/1.2 ui-sans-serif, system-ui, sans-serif;
          box-shadow: 0 8px 18px rgba(99,102,241,0.25);
        }
        """
        let body = """
        <div class="grid">
        \((1...cellCount).map { "<div>Cell \($0)</div>" }.joined(separator: "\n"))
        </div>
        """
        let html = previewDocument(body: body, css: css, js: "")
        let text = """
        CSS:
        \(css)

        columns: \(cols)
        rows: \(rows)
        gap: \(gap)
        """
        return ToolOutput(text, meta: "live grid preview", previewHTML: html)
    }

    private func parseHex(_ text: String) -> (Double, Double, Double)? {
        var hex = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return (
            Double((value >> 16) & 0xff) / 255,
            Double((value >> 8) & 0xff) / 255,
            Double(value & 0xff) / 255
        )
    }

    private func relativeLuminance(_ c: (Double, Double, Double)) -> Double {
        func chan(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * chan(c.0) + 0.7152 * chan(c.1) + 0.0722 * chan(c.2)
    }

    private func contrastRatio(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        let l1 = relativeLuminance(a)
        let l2 = relativeLuminance(b)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
}
