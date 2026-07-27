import Foundation
import Security

actor GeneratorTools {
    func run(_ request: ToolRequest) throws -> ToolOutput {
        switch request.toolID {
        case "gen.uuid":
            return ToolOutput(uuids(request))
        case "gen.fake":
            return ToolOutput(fakeData(request))
        case "gen.mockApi":
            return ToolOutput(mockAPI(request))
        case "gen.sqlData":
            return ToolOutput(sqlData(request))
        case "gen.testData":
            return ToolOutput(testData(request))
        case "gen.password":
            return ToolOutput(passwords(request))
        case "gen.palette":
            return ToolOutput(palette(request))
        case "gen.cssShadow":
            return ToolOutput(cssShadow(request))
        case "gen.cssGradient":
            return ToolOutput(cssGradient(request))
        case "gen.cssAnimation":
            return ToolOutput(cssAnimation(request))
        case "gen.tailwindClass":
            return ToolOutput(tailwindClass(request))
        case "gen.tailwindColor":
            return ToolOutput(tailwindColor(request))
        case "gen.htmlEmail":
            return ToolOutput(htmlEmail(request))
        case "gen.sitemap":
            return ToolOutput(sitemap(request.primary))
        case "gen.robots":
            return ToolOutput(robots(request))
        case "gen.robotsTest":
            return ToolOutput(robotsTest(request))
        default:
            throw ToolError.unknownTool(request.toolID)
        }
    }

    private func uuids(_ request: ToolRequest) -> String {
        let count = min(100, max(1, Int(request.options["count"] ?? "5") ?? 5))
        let version = (request.options["version"] ?? "4").lowercased()
        return (0..<count).map { _ in
            version == "7" ? uuidV7() : UUID().uuidString.lowercased()
        }.joined(separator: "\n")
    }

    private func uuidV7() -> String {
        let millis = UInt64(Date().timeIntervalSince1970 * 1000)
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        bytes[0] = UInt8((millis >> 40) & 0xff)
        bytes[1] = UInt8((millis >> 32) & 0xff)
        bytes[2] = UInt8((millis >> 24) & 0xff)
        bytes[3] = UInt8((millis >> 16) & 0xff)
        bytes[4] = UInt8((millis >> 8) & 0xff)
        bytes[5] = UInt8(millis & 0xff)
        bytes[6] = (bytes[6] & 0x0f) | 0x70
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20))"
    }

    private func fakeData(_ request: ToolRequest) -> String {
        let count = min(50, max(1, Int(request.options["count"] ?? "5") ?? 5))
        let first = [
            "Ada", "Grace", "Alan", "Barbara", "Linus", "Margaret", "Tim", "Radia",
            "Katherine", "Dennis", "Ken", "Bjarne", "Guido", "Brendan", "Leslie", "Donald",
        ]
        let last = [
            "Lovelace", "Hopper", "Turing", "Liskov", "Torvalds", "Hamilton", "Berners-Lee", "Perlman",
            "Johnson", "Ritchie", "Thompson", "Stroustrup", "van Rossum", "Eich", "Lamport", "Knuth",
        ]
        let companies = [
            "Northwind Labs", "Acme Systems", "Blue Harbor", "Cedar Stack", "Orbit Desk",
            "Pinnacle Soft", "Riverbyte", "Summit Grid", "Velvet Logic", "Willow Cloud",
        ]
        let roles = [
            "Engineer", "Designer", "Product Manager", "SRE", "Analyst", "Founder", "Support Lead",
        ]
        let streets = ["Oak", "Maple", "Cedar", "Pine", "Harbor", "Market", "King", "Union"]
        let cities: [(String, String, String)] = [
            ("Berlin", "DE", "10115"), ("Tokyo", "JP", "100-0001"), ("Lisbon", "PT", "1100-148"),
            ("Toronto", "CA", "M5V 2T6"), ("Nairobi", "KE", "00100"), ("Austin", "US", "78701"),
            ("Seoul", "KR", "04524"), ("Oslo", "NO", "0150"), ("Sydney", "AU", "2000"),
            ("São Paulo", "BR", "01310-100"),
        ]
        let domains = ["example.com", "mail.test", "dev.local", "corp.example"]
        var rows: [[String: Any]] = []
        for i in 0..<count {
            let f = first.randomElement()!
            let l = last.randomElement()!
            let place = cities.randomElement()!
            let company = companies.randomElement()!
            let role = roles.randomElement()!
            let streetNo = Int.random(in: 10...999)
            let phone = String(format: "+%d %03d-%03d-%04d",
                               Int.random(in: 1...99),
                               Int.random(in: 200...999),
                               Int.random(in: 200...999),
                               Int.random(in: 1000...9999))
            let username = "\(f.lowercased())\(l.prefix(1).lowercased())\(i + 1)"
            rows.append([
                "id": UUID().uuidString.lowercased(),
                "index": i + 1,
                "name": "\(f) \(l)",
                "firstName": f,
                "lastName": l,
                "username": username,
                "email": "\(f.lowercased()).\(l.lowercased().replacingOccurrences(of: " ", with: "")).\(i + 1)@\(domains.randomElement()!)",
                "phone": phone,
                "company": company,
                "jobTitle": role,
                "address": [
                    "line1": "\(streetNo) \(streets.randomElement()!) St",
                    "city": place.0,
                    "country": place.1,
                    "postalCode": place.2,
                ],
                "active": Bool.random(),
                "score": Double.random(in: 0...100).rounded() / 1,
                "createdAt": ISO8601DateFormatter().string(
                    from: Date().addingTimeInterval(TimeInterval(-Int.random(in: 0...86_400 * 365)))
                ),
            ])
        }
        let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        return String(data: data ?? Data("[]".utf8), encoding: .utf8) ?? "[]"
    }

    private func mockAPI(_ request: ToolRequest) -> String {
        let resource = (request.primary.isEmpty ? "items" : request.primary)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let count = min(20, max(1, Int(request.options["count"] ?? "3") ?? 3))
        let sample = (1...count).map { "{ \"id\": \($0), \"name\": \"\(resource)-\($0)\" }" }.joined(separator: ",\n  ")
        return """
        // Mock API for /\(resource)
        const \(resource) = [
          \(sample)
        ];

        app.get('/\(resource)', (req, res) => res.json(\(resource)));
        app.get('/\(resource)/:id', (req, res) => {
          const row = \(resource).find(x => String(x.id) === req.params.id);
          if (!row) return res.status(404).json({ error: 'Not found' });
          res.json(row);
        });
        app.post('/\(resource)', (req, res) => res.status(201).json({ id: Date.now(), ...req.body }));
        """
    }

    private func sqlData(_ request: ToolRequest) -> String {
        let table = request.primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "users"
            : request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = min(100, max(1, Int(request.options["count"] ?? "10") ?? 10))
        let columns = (request.options["columns"] ?? "name,email")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let cols = columns.isEmpty ? ["name", "email"] : columns
        return (1...count).map { i in
            let values = cols.map { col -> String in
                switch col.lowercased() {
                case "email": return "'user\(i)@example.com'"
                case "name": return "'User \(i)'"
                case "id": return String(i)
                default: return "'\(col)-\(i)'"
                }
            }.joined(separator: ", ")
            return "INSERT INTO \(table) (\(cols.joined(separator: ", "))) VALUES (\(values));"
        }.joined(separator: "\n")
    }

    private func testData(_ request: ToolRequest) -> String {
        let entity = request.primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "User"
            : request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = min(50, max(1, Int(request.options["count"] ?? "3") ?? 3))
        let fixtures = (1...count).map { i in
            [
                "id": "\(entity.lowercased())-\(i)",
                "type": entity,
                "attributes": [
                    "name": "\(entity) \(i)",
                    "createdAt": ISO8601DateFormatter().string(from: Date()),
                ],
            ] as [String: Any]
        }
        let payload: [String: Any] = ["data": fixtures]
        let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        return String(data: data ?? Data("{}".utf8), encoding: .utf8) ?? "{}"
    }

    private func passwords(_ request: ToolRequest) -> String {
        let length = min(128, max(8, Int(request.options["length"] ?? "20") ?? 20))
        let count = min(50, max(1, Int(request.options["count"] ?? "5") ?? 5))
        let charsetName = (request.options["charset"] ?? "all").lowercased()
        var charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        if charsetName == "all" { charset += "!@#$%^&*()-_=+[]{}" }
        if charsetName == "alnum" { /* base charset already alphanumeric */ }
        if charsetName == "alpha" { charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ" }
        let chars = Array(charset)
        return (0..<count).map { _ in
            var bytes = [UInt8](repeating: 0, count: length)
            _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
            return String(bytes.map { chars[Int($0) % chars.count] })
        }.joined(separator: "\n")
    }

    private func palette(_ request: ToolRequest) -> String {
        let count = min(12, max(3, Int(request.options["count"] ?? "5") ?? 5))
        let seed = parseHex(request.primary) ?? (0.55, 0.45, 0.85)
        var lines: [String] = []
        for i in 0..<count {
            let t = Double(i) / Double(max(count - 1, 1))
            let r = min(1, max(0, seed.0 * (1 - t) + (1 - seed.0) * t * 0.35 + t * 0.2))
            let g = min(1, max(0, seed.1 * (1 - t * 0.5) + 0.15 * t))
            let b = min(1, max(0, seed.2 * (0.85 + 0.15 * (1 - t))))
            lines.append(hex(r, g, b))
        }
        return lines.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    private func cssShadow(_ request: ToolRequest) -> String {
        let x = request.options["x"] ?? "0"
        let y = request.options["y"] ?? "8"
        let blur = request.options["blur"] ?? "24"
        let spread = request.options["spread"] ?? "-4"
        let color = request.options["color"] ?? "rgba(0,0,0,0.18)"
        return "box-shadow: \(x)px \(y)px \(blur)px \(spread)px \(color);"
    }

    private func cssGradient(_ request: ToolRequest) -> String {
        let type = (request.options["type"] ?? "linear").lowercased()
        let angle = request.options["angle"] ?? "135"
        let from = request.options["from"] ?? "#0ea5e9"
        let to = request.options["to"] ?? "#a855f7"
        if type == "radial" {
            return "background: radial-gradient(circle at center, \(from), \(to));"
        }
        return "background: linear-gradient(\(angle)deg, \(from), \(to));"
    }

    private func cssAnimation(_ request: ToolRequest) -> String {
        let name = request.primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "fadeUp"
            : request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = request.options["duration"] ?? "0.45s"
        let easing = request.options["easing"] ?? "ease-out"
        return """
        @keyframes \(name) {
          from { opacity: 0; transform: translateY(8px); }
          to { opacity: 1; transform: translateY(0); }
        }
        .\(name) {
          animation: \(name) \(duration) \(easing) both;
        }
        """
    }

    private func tailwindClass(_ request: ToolRequest) -> String {
        let parts = [
            request.options["layout"] ?? "flex items-center",
            request.options["spacing"] ?? "gap-3 px-4 py-2",
            request.options["color"] ?? "bg-slate-900 text-white",
            request.options["text"] ?? "text-sm font-medium",
        ]
        return parts.joined(separator: " ")
    }

    private func tailwindColor(_ request: ToolRequest) -> String {
        let base = parseHex(request.primary) ?? (0.14, 0.64, 0.92)
        let name = request.options["name"] ?? "brand"
        let shades = [50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 950]
        var lines = ["\(name): {"]
        for (index, shade) in shades.enumerated() {
            let t = Double(index) / Double(shades.count - 1)
            let factor = 1.15 - t * 1.05
            let r = min(1, max(0, base.0 * factor + (1 - t) * 0.35))
            let g = min(1, max(0, base.1 * factor + (1 - t) * 0.25))
            let b = min(1, max(0, base.2 * factor + (1 - t) * 0.15))
            lines.append("  \(shade): '\(hex(r, g, b))',")
        }
        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private func htmlEmail(_ request: ToolRequest) -> String {
        let title = request.primary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Hello from Toolbox"
            : request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let preheader = request.options["preheader"] ?? "A simple transactional email"
        return """
        <!doctype html>
        <html>
        <body style="margin:0;background:#f4f4f5;font-family:Helvetica,Arial,sans-serif;">
          <span style="display:none;">\(preheader)</span>
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
            <tr><td align="center" style="padding:32px 16px;">
              <table role="presentation" width="560" style="background:#ffffff;border-radius:12px;padding:28px;">
                <tr><td style="font-size:22px;font-weight:700;color:#111827;">\(title)</td></tr>
                <tr><td style="padding-top:12px;font-size:15px;line-height:1.6;color:#374151;">
                  Replace this body with your message. This template uses table layout for broad client support.
                </td></tr>
                <tr><td style="padding-top:24px;">
                  <a href="https://example.com" style="background:#111827;color:#fff;text-decoration:none;padding:12px 18px;border-radius:8px;display:inline-block;">Call to action</a>
                </td></tr>
              </table>
            </td></tr>
          </table>
        </body>
        </html>
        """
    }

    private func sitemap(_ text: String) -> String {
        let urls = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let body = urls.map { url in
            """
              <url>
                <loc>\(xmlEscape(url))</loc>
                <changefreq>weekly</changefreq>
                <priority>0.8</priority>
              </url>
            """
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        \(body)
        </urlset>
        """
    }

    private func robots(_ request: ToolRequest) -> String {
        let agent = request.options["userAgent"] ?? "*"
        let disallow = request.options["disallow"] ?? "/"
        let sitemap = request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        var lines = [
            "User-agent: \(agent)",
            "Disallow: \(disallow)",
        ]
        if !sitemap.isEmpty { lines.append("Sitemap: \(sitemap)") }
        return lines.joined(separator: "\n")
    }

    private func robotsTest(_ request: ToolRequest) -> String {
        let path = request.secondary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "Provide a path to test in the secondary input." }
        var disallows: [String] = []
        var allows: [String] = []
        for raw in request.primary.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if lower.hasPrefix("disallow:") {
                disallows.append(line.dropFirst(9).trimmingCharacters(in: .whitespaces))
            } else if lower.hasPrefix("allow:") {
                allows.append(line.dropFirst(6).trimmingCharacters(in: .whitespaces))
            }
        }
        let allowHit = allows.filter { !$0.isEmpty && path.hasPrefix($0) }.max(by: { $0.count < $1.count })
        let disallowHit = disallows.filter { !$0.isEmpty && path.hasPrefix($0) }.max(by: { $0.count < $1.count })
        if let allowHit, (disallowHit == nil || allowHit.count >= (disallowHit?.count ?? 0)) {
            return "ALLOWED — matched Allow: \(allowHit)"
        }
        if let disallowHit {
            return "BLOCKED — matched Disallow: \(disallowHit)"
        }
        return "ALLOWED — no matching Disallow rule"
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

    private func hex(_ r: Double, _ g: Double, _ b: Double) -> String {
        String(
            format: "#%02X%02X%02X",
            Int(r * 255),
            Int(g * 255),
            Int(b * 255)
        )
    }

    private func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
