import Foundation
import VehlaStoreSDK

private struct SavedRun: Codable {
    let note: String
    let endpoint: String
    let runCount: Int
    let savedAt: Date
}

private enum SwiftSDKLabError: LocalizedError {
    case unknownCommand(String)
    case invalidEndpoint

    var errorDescription: String? {
        switch self {
        case .unknownCommand(let command):
            return "Unknown Swift SDK Lab command: \(command)"
        case .invalidEndpoint:
            return "Enter a complete HTTP or HTTPS endpoint."
        }
    }
}

@main
private struct SwiftSDKLabExtension {
    static func main() async {
        await runStoreExtension { invocation in
            guard invocation.commandID == "run-demo" else {
                throw SwiftSDKLabError.unknownCommand(invocation.commandID)
            }
            return try await runDemo(invocation)
        }
    }

    private static func runDemo(
        _ invocation: StoreInvocation
    ) async throws -> StoreResult {
        let note = invocation.context.formValues["note"]?.stringValue
            ?? (invocation.query.isEmpty
                ? "Created by the Vehla Swift SDK."
                : invocation.query)
        let endpointValue = invocation.context.formValues["endpoint"]?.stringValue
            ?? "https://api.github.com/zen"
        guard let endpoint = URL(string: endpointValue),
              let scheme = endpoint.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw SwiftSDKLabError.invalidEndpoint
        }

        let storage = try invocation.storage()
        let preferences = try invocation.preferences()
        let logger = invocation.logger(category: "service-demo")
        let http = try invocation.httpClient(maximumBodySize: 256 * 1_024)

        let previousCount = try await preferences.value(
            forKey: "runCount",
            as: Int.self
        ) ?? 0
        let runCount = previousCount + 1
        try await preferences.set(runCount, forKey: "runCount")

        let savedRun = SavedRun(
            note: note,
            endpoint: endpoint.absoluteString,
            runCount: runCount,
            savedAt: Date()
        )
        try storage.write(savedRun, to: "runs/latest.json")
        let savedRunRoundTrip = try storage.read(
            SavedRun.self,
            from: "runs/latest.json"
        )

        let token = invocation.context.secrets["apiToken"] ?? ""
        logger.info(
            "Starting request with token \(token)",
            metadata: [
                "endpoint": endpoint.absoluteString,
                "runCount": "\(runCount)",
            ]
        )
        var headers = [
            "Accept": "application/json, text/plain;q=0.9, */*;q=0.8",
            "User-Agent": "Vehla-Swift-SDK-Lab/1.0",
        ]
        if !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        let response = try await http.get(
            endpoint,
            headers: headers,
            timeout: 10
        ).requireSuccess()
        logger.notice(
            "Request completed",
            metadata: [
                "status": "\(response.statusCode)",
                "bytes": "\(response.body.count)",
            ]
        )

        let body = response.string() ?? "<non-text response>"
        let preview = String(body.prefix(2_000))
        return Store.view(
            StoreRichView(
                title: "Swift SDK Lab completed",
                subtitle: "Storage, preferences, logging, and networking",
                sections: [
                    StoreRichSection(
                        title: "Persistent services",
                        items: [
                            .detail("Run count", value: "\(runCount)"),
                            .detail(
                                "Saved file",
                                value: "runs/latest.json"
                            ),
                            .detail(
                                "Round-trip note",
                                value: savedRunRoundTrip.note
                            ),
                        ]
                    ),
                    StoreRichSection(
                        title: "Permission-aware HTTP",
                        items: [
                            .detail(
                                "Endpoint",
                                value: response.url.absoluteString
                            ),
                            .detail(
                                "Status",
                                value: "\(response.statusCode)"
                            ),
                            .detail(
                                "Response bytes",
                                value: "\(response.body.count)"
                            ),
                            .code(preview),
                        ]
                    ),
                    StoreRichSection(
                        title: "Security",
                        items: [
                            .detail(
                                "Granted capabilities",
                                value: invocation.context.grantedCapabilities
                                    .map(\.rawValue)
                                    .sorted()
                                    .joined(separator: ", ")
                            ),
                            .text(
                                "StoreLogger wrote structured diagnostics to standard error and redacted the configured API token."
                            ),
                        ]
                    ),
                ]
            )
        )
    }
}
