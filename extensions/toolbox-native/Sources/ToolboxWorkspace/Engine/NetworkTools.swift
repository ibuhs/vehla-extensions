import Darwin
import Foundation
import Network

actor NetworkTools {
    private let cli = CLIProcessRunner()

    func run(_ request: ToolRequest) async throws -> ToolOutput {
        switch request.toolID {
        case "net.ipLookup":
            return try await ToolOutput(ipLookup(request.primary))
        case "net.localIP":
            return ToolOutput(localIPs())
        case "net.publicIP":
            return try await publicIP()
        case "net.cidr":
            return try ToolOutput(cidr(request.primary))
        case "net.subnet":
            return try ToolOutput(subnet(request))
        case "net.dns":
            return try await dns(request)
        case "net.whois":
            return try await whois(request.primary)
        case "net.reverseDns":
            return try await reverseDNS(request.primary)
        case "net.portScan":
            return try await portScan(request)
        case "net.tcp":
            return try await tcpClient(request)
        case "net.udp":
            return try await udpClient(request)
        case "net.ping":
            return try await ping(request)
        case "net.traceroute":
            return try await traceroute(request.primary)
        case "net.sslInspect", "net.sslChain", "net.tlsHandshake":
            return try await ssl(request)
        case "net.httpHeaders":
            return try await httpHeaders(request.primary)
        case "net.cookieInspect":
            return ToolOutput(cookieInspect(request.primary))
        case "net.userAgent":
            return ToolOutput(userAgent(request.primary))
        case "net.mime":
            return ToolOutput(mime(request.primary))
        default:
            throw ToolError.unknownTool(request.toolID)
        }
    }

    private func ipLookup(_ host: String) async throws -> String {
        let cleaned = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ToolError.invalidInput("Enter a hostname or IP.") }
        return try await withCheckedThrowingContinuation { continuation in
            var hints = addrinfo(
                ai_flags: AI_ADDRCONFIG,
                ai_family: AF_UNSPEC,
                ai_socktype: SOCK_STREAM,
                ai_protocol: 0,
                ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil,
                ai_next: nil
            )
            var result: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(cleaned, nil, &hints, &result)
            guard status == 0, let first = result else {
                continuation.resume(throwing: ToolError.failed("Lookup failed for \(cleaned)."))
                return
            }
            defer { freeaddrinfo(first) }
            var lines: [String] = ["host: \(cleaned)"]
            var pointer: UnsafeMutablePointer<addrinfo>? = first
            while let info = pointer {
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(
                    info.pointee.ai_addr,
                    info.pointee.ai_addrlen,
                    &hostBuffer,
                    socklen_t(hostBuffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                ) == 0 {
                    let ip = String(cString: hostBuffer)
                    let family = info.pointee.ai_family == AF_INET6 ? "AAAA" : "A"
                    lines.append("\(family): \(ip)")
                }
                pointer = info.pointee.ai_next
            }
            continuation.resume(returning: lines.joined(separator: "\n"))
        }
    }

    private func localIPs() -> String {
        var addresses: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return "Could not read interfaces."
        }
        defer { freeifaddrs(first) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let iface = pointer {
            let family = iface.pointee.ifa_addr.pointee.sa_family
            if family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(
                    iface.pointee.ifa_addr,
                    socklen_t(family == UInt8(AF_INET) ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                let name = String(cString: iface.pointee.ifa_name)
                let ip = String(cString: host)
                if !ip.hasPrefix("fe80") {
                    addresses.append("\(name): \(ip)")
                }
            }
            pointer = iface.pointee.ifa_next
        }
        return addresses.sorted().joined(separator: "\n")
    }

    private func publicIP() async throws -> ToolOutput {
        let url = URL(string: "https://api.ipify.org")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard code == 200, !text.isEmpty else {
            throw ToolError.failed("Could not fetch public IP (HTTP \(code)).")
        }
        return ToolOutput(text, meta: "ipify")
    }

    private func cidr(_ text: String) throws -> String {
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              prefix >= 0, prefix <= 32,
              let ip = ipv4(String(parts[0]))
        else {
            throw ToolError.invalidInput("Expected IPv4 CIDR like 10.0.0.0/24.")
        }
        let mask = prefix == 0 ? UInt32(0) : UInt32.max << (32 - prefix)
        let network = ip & mask
        let broadcast = network | ~mask
        let hosts = prefix >= 31 ? max(0, Int(broadcast &- network)) : Int(broadcast &- network &- 1)
        return [
            "network: \(dotted(network))",
            "broadcast: \(dotted(broadcast))",
            "netmask: \(dotted(mask))",
            "hostMin: \(dotted(network &+ (prefix >= 31 ? 0 : 1)))",
            "hostMax: \(dotted(broadcast &- (prefix >= 31 ? 0 : 1)))",
            "hosts: \(hosts)",
            "prefix: /\(prefix)",
        ].joined(separator: "\n")
    }

    private func subnet(_ request: ToolRequest) throws -> String {
        let prefix = Int(request.options["prefix"] ?? "24") ?? 24
        return try cidr("\(request.primary.trimmingCharacters(in: .whitespacesAndNewlines))/\(prefix)")
    }

    private func dns(_ request: ToolRequest) async throws -> ToolOutput {
        let host = request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = (request.options["type"] ?? "A").uppercased()
        if let dig = await cli.which("dig") {
            let result = try await cli.run(executable: dig, arguments: [host, type, "+short"])
            if result.exitCode == 0 { return ToolOutput(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), meta: "dig") }
        }
        if let hostBin = await cli.which("host") {
            let result = try await cli.run(executable: hostBin, arguments: ["-t", type, host])
            return ToolOutput([result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n"), meta: "host")
        }
        return ToolOutput(try await ipLookup(host), meta: "getaddrinfo fallback")
    }

    private func whois(_ query: String) async throws -> ToolOutput {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ToolError.invalidInput("Enter a domain or IP.") }
        guard let whois = await cli.which("whois") else {
            throw ToolError.failed("whois not found on PATH.")
        }
        let result = try await cli.run(executable: whois, arguments: [value], timeoutSeconds: 20)
        let body = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return ToolOutput(ToolLimits.truncate(body), meta: "whois")
    }

    private func reverseDNS(_ ip: String) async throws -> ToolOutput {
        let value = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dig = await cli.which("dig") {
            let result = try await cli.run(executable: dig, arguments: ["-x", value, "+short"])
            if result.exitCode == 0, !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ToolOutput(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), meta: "dig -x")
            }
        }
        return try await withCheckedThrowingContinuation { continuation in
            var hints = addrinfo(
                ai_flags: AI_NUMERICHOST,
                ai_family: AF_UNSPEC,
                ai_socktype: SOCK_STREAM,
                ai_protocol: 0,
                ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil,
                ai_next: nil
            )
            var result: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo(value, nil, &hints, &result) == 0, let info = result else {
                continuation.resume(throwing: ToolError.failed("Reverse lookup failed."))
                return
            }
            defer { freeaddrinfo(info) }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                info.pointee.ai_addr,
                info.pointee.ai_addrlen,
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NAMEREQD
            )
            if status == 0 {
                continuation.resume(returning: ToolOutput(String(cString: host), meta: "getnameinfo"))
            } else {
                continuation.resume(throwing: ToolError.failed("No PTR record found."))
            }
        }
    }

    private func portScan(_ request: ToolRequest) async throws -> ToolOutput {
        let host = request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw ToolError.invalidInput("Enter a host.") }
        let ports = parsePorts(request.options["ports"] ?? "80,443,22,8080")
        let timeoutMs = min(3_000, max(100, Int(request.options["timeoutMs"] ?? "400") ?? 400))
        var lines: [String] = ["host: \(host)"]
        for port in ports.prefix(64) {
            let open = await tcpConnect(host: host, port: port, timeoutMs: timeoutMs)
            lines.append("\(port)/tcp: \(open ? "open" : "closed/filtered")")
        }
        return ToolOutput(lines.joined(separator: "\n"), meta: "tcp connect")
    }

    private func tcpClient(_ request: ToolRequest) async throws -> ToolOutput {
        let host = request.options["host"] ?? "127.0.0.1"
        let port = UInt16(request.options["port"] ?? "80") ?? 80
        let payload = request.primary.isEmpty ? "\n" : request.primary
        return try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            connection.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    continuation.resume(throwing: ToolError.failed(error.localizedDescription))
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
            connection.send(
                content: Data(payload.utf8),
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: ToolError.failed(error.localizedDescription))
                        return
                    }
                    connection.receive(minimumIncompleteLength: 1, maximumLength: 64_000) { data, _, _, error in
                        defer { connection.cancel() }
                        if let error {
                            continuation.resume(throwing: ToolError.failed(error.localizedDescription))
                            return
                        }
                        let text = String(data: data ?? Data(), encoding: .utf8)
                            ?? (data ?? Data()).map { String(format: "%02x", $0) }.joined()
                        continuation.resume(returning: ToolOutput(text, meta: "tcp \(host):\(port)"))
                    }
                }
            )
        }
    }

    private func udpClient(_ request: ToolRequest) async throws -> ToolOutput {
        let host = request.options["host"] ?? "127.0.0.1"
        let port = UInt16(request.options["port"] ?? "53") ?? 53
        let payload = request.primary.isEmpty ? "toolbox" : request.primary
        return try await withCheckedThrowingContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .udp
            )
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
            connection.send(
                content: Data(payload.utf8),
                completion: .contentProcessed { error in
                    defer { connection.cancel() }
                    if let error {
                        continuation.resume(throwing: ToolError.failed(error.localizedDescription))
                    } else {
                        continuation.resume(
                            returning: ToolOutput(
                                "Sent \(payload.utf8.count) bytes to \(host):\(port)/udp",
                                meta: "udp"
                            )
                        )
                    }
                }
            )
        }
    }

    private func ping(_ request: ToolRequest) async throws -> ToolOutput {
        let host = request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let count = min(10, max(1, Int(request.options["count"] ?? "4") ?? 4))
        guard let ping = await cli.which("ping") else {
            throw ToolError.failed("ping not found on PATH.")
        }
        let result = try await cli.run(
            executable: ping,
            arguments: ["-c", String(count), host],
            timeoutSeconds: 20
        )
        let body = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return ToolOutput(body, meta: "ping")
    }

    private func traceroute(_ host: String) async throws -> ToolOutput {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw ToolError.invalidInput("Enter a host.") }
        let bin: String?
        if let traceroute = await cli.which("traceroute") {
            bin = traceroute
        } else {
            bin = await cli.which("traceroute6")
        }
        guard let bin else { throw ToolError.failed("traceroute not found on PATH.") }
        let result = try await cli.run(executable: bin, arguments: ["-m", "16", value], timeoutSeconds: 45)
        let body = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return ToolOutput(ToolLimits.truncate(body), meta: "traceroute")
    }

    private func ssl(_ request: ToolRequest) async throws -> ToolOutput {
        let host = request.primary.trimmingCharacters(in: .whitespacesAndNewlines)
        let port = request.options["port"] ?? "443"
        guard !host.isEmpty else { throw ToolError.invalidInput("Enter a host.") }
        guard let openssl = await cli.which("openssl") else {
            throw ToolError.failed("openssl not found on PATH.")
        }
        let args: [String]
        switch request.toolID {
        case "net.sslChain":
            args = ["s_client", "-showcerts", "-servername", host, "-connect", "\(host):\(port)"]
        case "net.tlsHandshake":
            args = ["s_client", "-tls1_2", "-servername", host, "-connect", "\(host):\(port)"]
        default:
            args = ["s_client", "-servername", host, "-connect", "\(host):\(port)"]
        }
        // openssl s_client waits for stdin; send quit.
        let result = try await cli.run(
            executable: openssl,
            arguments: args,
            stdin: "Q\n",
            timeoutSeconds: 20
        )
        let body = [result.stdout, result.stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        let filtered = body
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter {
                $0.contains("CONNECTED")
                    || $0.contains("subject=")
                    || $0.contains("issuer=")
                    || $0.contains("Protocol")
                    || $0.contains("Cipher")
                    || $0.contains("BEGIN CERTIFICATE")
                    || $0.contains("END CERTIFICATE")
                    || $0.hasPrefix("depth=")
                    || $0.contains("Verify return code")
            }
            .joined(separator: "\n")
        return ToolOutput(filtered.isEmpty ? ToolLimits.truncate(body) : filtered, meta: "openssl")
    }

    private func httpHeaders(_ urlString: String) async throws -> ToolOutput {
        let cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: cleaned), let scheme = url.scheme, ["http", "https"].contains(scheme) else {
            throw ToolError.invalidInput("Enter an http(s) URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ToolError.failed("No HTTP response.")
        }
        var lines = ["status: \(http.statusCode)"]
        for key in http.allHeaderFields.keys.sorted(by: { String(describing: $0) < String(describing: $1) }) {
            lines.append("\(key): \(http.allHeaderFields[key] ?? "")")
        }
        return ToolOutput(lines.joined(separator: "\n"))
    }

    private func cookieInspect(_ text: String) -> String {
        let chunks = text
            .replacingOccurrences(of: "\n", with: ";")
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var lines: [String] = []
        for chunk in chunks {
            if chunk.contains("=") {
                let parts = chunk.split(separator: "=", maxSplits: 1).map(String.init)
                lines.append("name: \(parts[0])")
                lines.append("value: \(parts.count > 1 ? parts[1] : "")")
            } else {
                lines.append("attribute: \(chunk)")
            }
            lines.append("---")
        }
        return lines.isEmpty ? "No cookies found." : lines.joined(separator: "\n")
    }

    private func userAgent(_ ua: String) -> String {
        let text = ua.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return "Paste a User-Agent string to parse browser, engine, OS, and device details."
        }

        func token(_ name: String) -> String? {
            guard let regex = try? NSRegularExpression(pattern: "\(name)/([\\w\\.\\-]+)") else { return nil }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let vr = Range(match.range(at: 1), in: text)
            else { return nil }
            return String(text[vr])
        }

        var browser = "unknown"
        var browserVersion = ""
        if text.contains("Edg/") {
            browser = "Edge"
            browserVersion = token("Edg") ?? ""
        } else if text.contains("OPR/") || text.contains("Opera/") {
            browser = "Opera"
            browserVersion = token("OPR") ?? token("Opera") ?? ""
        } else if text.contains("Chrome/") && !text.contains("Edg/") {
            browser = "Chrome"
            browserVersion = token("Chrome") ?? ""
        } else if text.contains("Firefox/") {
            browser = "Firefox"
            browserVersion = token("Firefox") ?? ""
        } else if text.contains("Safari/") && text.contains("Version/") && !text.contains("Chrome/") {
            browser = "Safari"
            browserVersion = token("Version") ?? ""
        } else if text.contains("MSIE ") || text.contains("Trident/") {
            browser = "Internet Explorer"
            browserVersion = token("rv") ?? ""
        } else if text.lowercased().contains("curl/") {
            browser = "curl"
            browserVersion = token("curl") ?? ""
        }

        var engine = "unknown"
        var engineVersion = ""
        if text.contains("AppleWebKit/") {
            engine = text.contains("Chrome/") || text.contains("Edg/") ? "Blink" : "WebKit"
            engineVersion = token("AppleWebKit") ?? ""
        } else if text.contains("Gecko/") {
            engine = "Gecko"
            engineVersion = token("rv") ?? token("Gecko") ?? ""
        } else if text.contains("Trident/") {
            engine = "Trident"
            engineVersion = token("Trident") ?? ""
        }

        var os = "unknown"
        var osVersion = ""
        if let regex = try? NSRegularExpression(pattern: "Windows NT ([\\d\\.]+)"),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
           let r = Range(match.range(at: 1), in: text) {
            os = "Windows"
            let nt = String(text[r])
            osVersion = [
                "10.0": "10/11", "6.3": "8.1", "6.2": "8", "6.1": "7",
            ][nt] ?? nt
        } else if text.contains("Android"),
                  let regex = try? NSRegularExpression(pattern: "Android ([\\d\\.]+)"),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
                  let r = Range(match.range(at: 1), in: text) {
            os = "Android"
            osVersion = String(text[r])
        } else if text.contains("iPhone") || text.contains("iPad") {
            os = text.contains("iPad") ? "iPadOS" : "iOS"
            if let regex = try? NSRegularExpression(pattern: "OS ([\\d_]+)"),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
               let r = Range(match.range(at: 1), in: text) {
                osVersion = String(text[r]).replacingOccurrences(of: "_", with: ".")
            }
        } else if text.contains("Mac OS X") || text.contains("Macintosh") {
            os = "macOS"
            if let regex = try? NSRegularExpression(pattern: "Mac OS X ([\\d_]+)"),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
               let r = Range(match.range(at: 1), in: text) {
                osVersion = String(text[r]).replacingOccurrences(of: "_", with: ".")
            }
        } else if text.contains("CrOS") {
            os = "Chrome OS"
        } else if text.contains("Linux") {
            os = "Linux"
        }

        let device: String
        if text.contains("iPad") { device = "tablet" }
        else if text.contains("iPhone") || text.contains("Android") || text.contains("Mobile") { device = "mobile" }
        else if text.contains("bot") || text.contains("Bot") || text.contains("Spider") || text.contains("crawler") {
            device = "bot"
        } else if text.contains("Macintosh") || text.contains("Windows") || text.contains("X11") || text.contains("Linux") {
            device = "desktop"
        } else {
            device = "unknown"
        }

        var architecture = "unknown"
        if text.contains("arm64") || text.contains("aarch64") { architecture = "arm64" }
        else if text.contains("x86_64") || text.contains("Win64") || text.contains("WOW64") { architecture = "x86_64" }
        else if text.contains("iPhone") || text.contains("iPad") { architecture = "arm" }

        let isBot = device == "bot"
            || text.range(of: "Googlebot|bingbot|Slackbot|Twitterbot|facebookexternalhit|Applebot", options: .regularExpression) != nil

        var lines = [
            "raw: \(text)",
            "browser: \(browser)\(browserVersion.isEmpty ? "" : " \(browserVersion)")",
            "engine: \(engine)\(engineVersion.isEmpty ? "" : " \(engineVersion)")",
            "os: \(os)\(osVersion.isEmpty ? "" : " \(osVersion)")",
            "device: \(device)",
            "architecture: \(architecture)",
            "bot: \(isBot ? "yes" : "no")",
        ]
        if let safari = token("Safari"), browser != "Safari" {
            lines.append("safariCompat: \(safari)")
        }
        return lines.joined(separator: "\n")
    }

    private func mime(_ text: String) -> String {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let map: [String: String] = [
            "html": "text/html", "htm": "text/html", "css": "text/css", "js": "text/javascript",
            "json": "application/json", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
            "gif": "image/gif", "svg": "image/svg+xml", "webp": "image/webp", "pdf": "application/pdf",
            "txt": "text/plain", "xml": "application/xml", "zip": "application/zip",
            "wasm": "application/wasm", "mp4": "video/mp4", "mp3": "audio/mpeg",
            "woff2": "font/woff2", "ttf": "font/ttf",
        ]
        if value.contains("/") {
            let matches = map.filter { $0.value == value }.map(\.key).sorted()
            return matches.isEmpty ? "No known extensions for \(value)" : "\(value) → \(matches.joined(separator: ", "))"
        }
        let key = value.hasPrefix(".") ? String(value.dropFirst()) : value
        return map[key].map { ".\(key) → \($0)" } ?? "Unknown extension: \(key)"
    }

    private func parsePorts(_ text: String) -> [UInt16] {
        var ports: [UInt16] = []
        for part in text.split(separator: ",") {
            let token = part.trimmingCharacters(in: .whitespaces)
            if token.contains("-") {
                let bounds = token.split(separator: "-")
                if bounds.count == 2, let lo = UInt16(bounds[0]), let hi = UInt16(bounds[1]), lo <= hi {
                    ports.append(contentsOf: lo...min(hi, lo &+ 32))
                }
            } else if let port = UInt16(token) {
                ports.append(port)
            }
        }
        return ports
    }

    private func tcpConnect(host: String, port: UInt16, timeoutMs: Int) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: .tcp
            )
            final class Gate: @unchecked Sendable {
                private let lock = NSLock()
                private var resumed = false
                private let connection: NWConnection
                private let continuation: CheckedContinuation<Bool, Never>

                init(connection: NWConnection, continuation: CheckedContinuation<Bool, Never>) {
                    self.connection = connection
                    self.continuation = continuation
                }

                func finish(_ value: Bool) {
                    lock.lock()
                    defer { lock.unlock() }
                    guard !resumed else { return }
                    resumed = true
                    connection.cancel()
                    continuation.resume(returning: value)
                }
            }
            let gate = Gate(connection: connection, continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: gate.finish(true)
                case .failed, .cancelled: gate.finish(false)
                default: break
                }
            }
            connection.start(queue: DispatchQueue.global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
                gate.finish(false)
            }
        }
    }

    private func ipv4(_ text: String) -> UInt32? {
        var addr = in_addr()
        guard inet_pton(AF_INET, text, &addr) == 1 else { return nil }
        return CFSwapInt32BigToHost(addr.s_addr)
    }

    private func dotted(_ value: UInt32) -> String {
        "\((value >> 24) & 0xff).\((value >> 16) & 0xff).\((value >> 8) & 0xff).\(value & 0xff)"
    }
}
