import Foundation

actor LinkWorker {
    static let shared = LinkWorker()

    func perform(_ action: LinkLensActionID, selectedText: String) async throws -> String {
        let text = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LinkLensError.emptySelection }
        let matches = LinkEngine.extract(text)
        guard !matches.isEmpty else { throw LinkLensError.noURL }

        switch action {
        case .clean:
            return try LinkEngine.replaceEachURL(in: selectedText, transform: LinkEngine.clean)
        case .unwrap:
            return try await unwrap(selectedText, matches: matches)
        case .inspect:
            return LinkEngine.inspect(matches.map(\.url))
        case .extract:
            return LinkEngine.extractList(matches.map(\.url))
        case .safety:
            return await safety(matches.map(\.url))
        }
    }

    private func unwrap(_ text: String, matches: [LinkMatch]) async throws -> String {
        var destinations: [URL: URL] = [:]
        for match in matches {
            destinations[match.url] = await resolve(match.url)
        }
        return try LinkEngine.replaceEachURL(in: text) { url in
            destinations[url] ?? LinkEngine.unwrapLocally(url)
        }
    }

    private func safety(_ urls: [URL]) async -> String {
        var hops: [URL: [URL]] = [:]
        for url in urls {
            hops[url] = await redirectChain(from: url)
        }
        return LinkEngine.safetyReport(urls: urls, redirectHops: hops)
    }

    private func resolve(_ url: URL) async -> URL {
        let local = LinkEngine.unwrapLocally(url)
        let chain = await redirectChain(from: local)
        return chain.last ?? local
    }

    private func redirectChain(from url: URL) async -> [URL] {
        let recorder = RedirectRecorder(start: url)
        let session = URLSession(
            configuration: Self.sessionConfiguration,
            delegate: recorder,
            delegateQueue: nil
        )
        defer { session.invalidateAndCancel() }

        if await finish(url, method: "HEAD", session: session) {
            return await recorder.hops()
        }
        _ = await finish(url, method: "GET", session: session)
        return await recorder.hops()
    }

    private func finish(
        _ url: URL,
        method: String,
        session: URLSession
    ) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue("Vehla-LinkLens/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("0", forHTTPHeaderField: "Content-Length")
        if method == "GET" {
            request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        }
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse) != nil
        } catch {
            return false
        }
    }

    private static var sessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 12
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpMaximumConnectionsPerHost = 2
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }
}

private final class RedirectRecorder: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URL]

    init(start: URL) {
        recorded = [start]
    }

    func hops() async -> [URL] {
        lock.withLock { recorded }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard recorded.count < 6, let next = request.url else {
            completionHandler(nil)
            return
        }
        recorded.append(next)
        completionHandler(request)
    }
}
