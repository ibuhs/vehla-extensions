import Foundation

enum LinkLensError: LocalizedError, Equatable {
    case emptySelection
    case noURL
    case unknownAction(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Select a URL or text that contains a URL."
        case .noURL:
            return "No URL was found in the selection."
        case .unknownAction(let id):
            return "Unknown Link Lens action “\(id)”."
        }
    }
}

struct LinkMatch: Equatable, Sendable {
    let original: String
    let url: URL
}

enum LinkEngine {
    static let trackingKeys: Set<String> = [
        "fbclid", "fb_action_ids", "fb_action_types", "fb_source",
        "gclid", "gclsrc", "dclid", "gbraid", "wbraid",
        "gad_source", "gad_campaignid", "srsltid",
        "msclkid", "twclid", "ttclid", "yclid", "li_fat_id",
        "mc_cid", "mc_eid", "mkt_tok", "mc_tc",
        "_hsenc", "_hsmi", "igshid", "igsh",
        "ncid", "cmpid", "ocid", "icid",
        "_ga", "_gl", "_gid", "_openstat",
        "ref_src", "ref_url", "refsrc",
        "wickedid", "ysm", "s_kwcid",
        "vero_id", "oly_anon_id", "oly_enc_id",
    ]

    static let trackingPrefixes = [
        "utm_", "hsa_", "pk_", "mtm_", "spm", "scm", "oly_", "vero_", "ndclid",
    ]

    static func extract(_ text: String) -> [LinkMatch] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var seen = Set<String>()
        var matches: [LinkMatch] = []

        func append(_ raw: String) {
            guard let url = normalize(raw) else { return }
            let key = url.absoluteString
            guard seen.insert(key).inserted else { return }
            matches.append(LinkMatch(original: raw, url: url))
        }

        if looksLikeStandaloneURL(trimmed) {
            append(trimmed)
        }

        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let full = NSRange(trimmed.startIndex..., in: trimmed)
        detector?.enumerateMatches(in: trimmed, options: [], range: full) { result, _, _ in
            guard let result, let range = Range(result.range, in: trimmed) else { return }
            append(String(trimmed[range]))
        }

        let markdown = /\]\((https?:\/\/[^)\s]+)\)/
        for match in trimmed.matches(of: markdown) {
            append(String(match.1))
        }

        let explicit = /https?:\/\/[^\s<>"'`]+/
        for match in trimmed.matches(of: explicit) {
            append(String(trimmed[match.range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,);]")))
        }

        return matches
    }

    static func clean(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.host = components.host?.lowercased()
        if let items = components.queryItems, !items.isEmpty {
            let kept = items.filter { !isTracking($0.name) }
            components.queryItems = kept.isEmpty ? nil : kept
        }
        components.fragment = nil
        return components.url ?? url
    }

    static func unwrapLocally(_ url: URL) -> URL {
        var current = url
        for _ in 0..<6 {
            guard let next = wrapperTarget(current), next != current else {
                return current
            }
            current = next
        }
        return current
    }

    static func replaceEachURL(in text: String, transform: (URL) -> URL) throws -> String {
        let matches = extract(text)
        guard !matches.isEmpty else { throw LinkLensError.noURL }
        if looksLikeStandaloneURL(text) {
            return transform(matches[0].url).absoluteString
        }
        var output = text
        for match in matches.reversed() {
            let replacement = transform(match.url).absoluteString
            if let range = output.range(of: match.original) {
                output.replaceSubrange(range, with: replacement)
            }
        }
        return output
    }

    static func inspect(_ urls: [URL]) -> String {
        urls.map { url in
            var lines = [url.absoluteString]
            lines.append("Scheme: \(url.scheme ?? "—")")
            if let host = url.host {
                lines.append("Host: \(host)")
                if host.contains("xn--") {
                    lines.append("ASCII / punycode: \(host)")
                }
            }
            if let port = url.port { lines.append("Port: \(port)") }
            if !url.path.isEmpty { lines.append("Path: \(url.path)") }
            if let query = url.query, !query.isEmpty { lines.append("Query: \(query)") }
            if let fragment = url.fragment, !fragment.isEmpty {
                lines.append("Fragment: \(fragment)")
            }
            if let user = url.user, !user.isEmpty {
                lines.append("User: \(user)")
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    static func extractList(_ urls: [URL]) -> String {
        urls.map(\.absoluteString).joined(separator: "\n")
    }

    static func localFindings(for url: URL) -> [String] {
        var findings: [String] = []
        let scheme = url.scheme?.lowercased() ?? ""
        if ["javascript", "data", "file", "blob"].contains(scheme) {
            findings.append("Uses a dangerous scheme (\(scheme)).")
        } else if scheme == "http" {
            findings.append("Uses HTTP instead of HTTPS.")
        }
        if url.user != nil || url.password != nil {
            findings.append("Contains credentials in the URL.")
        }
        if let host = url.host {
            if host.contains("xn--") {
                findings.append("Hostname uses punycode, which can hide lookalike characters.")
            }
            if isIPAddress(host) {
                findings.append("Hostname is a raw IP address.")
            }
            if host.filter({ $0 == "." }).count >= 5 {
                findings.append("Hostname has an unusually deep subdomain chain.")
            }
        }
        if url.absoluteString.count > 400 {
            findings.append("URL is unusually long (\(url.absoluteString.count) characters).")
        }
        if let atRange = url.absoluteString.range(of: "@"),
           let schemeRange = url.absoluteString.range(of: "://"),
           atRange.lowerBound > schemeRange.upperBound,
           url.user == nil {
            findings.append("Contains @ after the scheme, which can disguise the real host.")
        }
        return findings
    }

    static func safetyReport(
        urls: [URL],
        redirectHops: [URL: [URL]]
    ) -> String {
        urls.map { url in
            let hops = redirectHops[url] ?? []
            let destination = hops.last ?? unwrapLocally(url)
            var findings = localFindings(for: url)
            if destination.host != nil, destination.host != url.host {
                findings.append(
                    "Redirects from \(url.host ?? "the original host") to \(destination.host ?? "another host")."
                )
            }
            findings.append(contentsOf: localFindings(for: destination).filter { extra in
                !findings.contains(extra)
            })
            let risk: String
            if findings.contains(where: { $0.contains("dangerous scheme") || $0.contains("credentials") }) {
                risk = "High"
            } else if findings.isEmpty {
                risk = "Low"
            } else {
                risk = "Medium"
            }
            var lines = [url.absoluteString, "Risk: \(risk)"]
            if destination != url {
                lines.append("Destination: \(destination.absoluteString)")
            }
            if hops.count > 1 {
                lines.append("Redirects: \(hops.map(\.absoluteString).joined(separator: " → "))")
            }
            if findings.isEmpty {
                lines.append("Findings: none from local checks.")
            } else {
                lines.append("Findings:")
                lines.append(contentsOf: findings.map { "- \($0)" })
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    static func normalize(_ raw: String) -> URL? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "<>.,);]\"'"))
        if value.hasPrefix("www.") {
            value = "https://\(value)"
        }
        guard let url = URL(string: value), url.scheme != nil, url.host != nil else {
            return nil
        }
        return url
    }

    static func looksLikeStandaloneURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = normalize(trimmed) else { return false }
        return url.absoluteString == normalize(trimmed)?.absoluteString
            && !trimmed.contains(" ")
            && !trimmed.contains("\n")
    }

    static func isTracking(_ name: String) -> Bool {
        let key = name.lowercased()
        if trackingKeys.contains(key) { return true }
        return trackingPrefixes.contains { key.hasPrefix($0) }
    }

    private static func wrapperTarget(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        let items = components.queryItems ?? []

        if host.contains("safelinks.protection.outlook.com"),
           let value = query(items, names: ["url"]) {
            return normalize(value)
        }
        if host.contains("urldefense.proofpoint.com"),
           let value = query(items, names: ["u"]) {
            return normalize(decodeProofpoint(value))
        }
        if host.contains("google.") || host == "googleadservices.com"
            || host.hasSuffix(".googleadservices.com") {
            if let value = query(items, names: ["q", "url", "adurl"]) {
                return normalize(value)
            }
        }
        if host == "l.facebook.com" || host == "lm.facebook.com"
            || host == "l.instagram.com" {
            if let value = query(items, names: ["u"]) {
                return normalize(value)
            }
        }
        if host.hasSuffix("linkedin.com"),
           let value = query(items, names: ["url"]) {
            return normalize(value)
        }
        if host.hasSuffix("youtube.com"),
           let value = query(items, names: ["q"]) {
            return normalize(value)
        }
        if host == "away.vk.com",
           let value = query(items, names: ["to"]) {
            return normalize(value)
        }
        if let value = query(
            items,
            names: [
                "redirect", "redirecturl", "redirect_url",
                "target", "dest", "destination", "return",
                "returnurl", "continue", "link",
            ]
        ) {
            return normalize(value)
        }
        return nil
    }

    private static func query(_ items: [URLQueryItem], names: [String]) -> String? {
        let wanted = Set(names.map { $0.lowercased() })
        return items.first { wanted.contains($0.name.lowercased()) }?.value
    }

    static func decodeProofpoint(_ value: String) -> String {
        var decoded = ""
        var index = value.startIndex
        while index < value.endIndex {
            if value[index] == "-",
               value.distance(from: index, to: value.endIndex) >= 3 {
                let hexStart = value.index(after: index)
                let hexEnd = value.index(hexStart, offsetBy: 2)
                if let code = UInt8(value[hexStart..<hexEnd], radix: 16),
                   let scalar = UnicodeScalar(Int(code)) {
                    decoded.append(Character(scalar))
                    index = hexEnd
                    continue
                }
            }
            decoded.append(value[index] == "_" ? "/" : value[index])
            index = value.index(after: index)
        }
        return decoded
    }

    private static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":"), host.contains(where: \.isHexDigit) {
            return true
        }
        let parts = host.split(separator: ".")
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }
}
