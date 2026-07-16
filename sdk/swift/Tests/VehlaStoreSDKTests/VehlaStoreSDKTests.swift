import Foundation
import Testing
@testable import VehlaStoreSDK

private struct PreferenceFixture: Codable, Equatable {
    let count: Int
    let name: String
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var statusCode = 200
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: Self.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(
            self,
            didReceive: response,
            cacheStoragePolicy: .notAllowed
        )
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func temporaryContext(
    capabilities: [StoreCapability] = [.persistentStorage],
    secrets: [String: String] = [:]
) throws -> (StoreInvocationContext, URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "vehla-sdk-tests-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    return (
        StoreInvocationContext(
            dataDirectory: root.path,
            grantedCapabilities: capabilities,
            secrets: secrets
        ),
        root
    )
}

@Test
func decodesInvocationContext() throws {
    let data = Data(
        """
        {
          "packageID": "com.example.swift",
          "commandID": "inspect",
          "query": "hello",
          "context": {
            "grantedCapabilities": ["networkAccess", "persistentStorage"],
            "secrets": {"token": "value"},
            "formValues": {
              "enabled": true,
              "name": "Vehla",
              "file": {
                "path": "/tmp/example.txt",
                "name": "example.txt",
                "isDirectory": false,
                "size": 42
              }
            }
          }
        }
        """.utf8
    )
    let invocation = try JSONDecoder().decode(
        StoreInvocation.self,
        from: data
    )

    #expect(invocation.commandID == "inspect")
    #expect(invocation.context.grants(.networkAccess))
    #expect(invocation.context.grants(.persistentStorage))
    #expect(invocation.context.secrets["token"] == "value")
    #expect(invocation.context.formValues["enabled"]?.boolValue == true)
    #expect(invocation.context.formValues["name"]?.stringValue == "Vehla")
    #expect(
        invocation.context.formValues["file"]?.fileValue?.name
            == "example.txt"
    )
}

@Test
func storageRoundTripsAndConfinesPaths() throws {
    let (context, root) = try temporaryContext()
    defer { try? FileManager.default.removeItem(at: root) }
    let storage = try StoreStorage(context: context)

    try storage.write("hello", to: "notes/today.txt")
    #expect(try storage.readString("notes/today.txt") == "hello")
    #expect(try storage.exists("notes/today.txt"))
    #expect(try storage.list("notes").map(\.name) == ["today.txt"])
    #expect(throws: (any Error).self) {
        try storage.write("escape", to: "../outside.txt")
    }

    let link = root.appendingPathComponent("outside")
    try FileManager.default.createSymbolicLink(
        at: link,
        withDestinationURL: FileManager.default.temporaryDirectory
    )
    #expect(throws: (any Error).self) {
        try storage.write("escape", to: "outside/escaped.txt")
    }
}

@Test
func preferencesRoundTripTypedValues() async throws {
    let (context, root) = try temporaryContext()
    defer { try? FileManager.default.removeItem(at: root) }
    let preferences = try StorePreferences(context: context)
    let fixture = PreferenceFixture(count: 3, name: "Vehla")

    try await preferences.set(fixture, forKey: "fixture")
    let decoded = try await preferences.value(
        forKey: "fixture",
        as: PreferenceFixture.self
    )
    #expect(decoded == fixture)
    #expect(try await preferences.contains("fixture"))
    #expect(try await preferences.allKeys() == ["fixture"])
    try await preferences.removeValue(forKey: "fixture")
    #expect(try await preferences.contains("fixture") == false)
}

@Test
func servicesRequireGrantedCapabilities() throws {
    let context = StoreInvocationContext(
        dataDirectory: FileManager.default.temporaryDirectory.path
    )
    #expect(throws: StoreServiceError.self) {
        try StoreStorage(context: context)
    }
    #expect(throws: StoreServiceError.self) {
        try StoreHTTPClient(context: context)
    }
}

@Test
func loggerRedactsSecrets() {
    let logger = StoreLogger(
        packageID: "com.example",
        redacting: ["top-secret"]
    )
    #expect(logger.redact("token=top-secret") == "token=[REDACTED]")
}

@Test
func httpClientValidatesAndDecodesResponses() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let context = StoreInvocationContext(
        grantedCapabilities: [.networkAccess]
    )
    let client = try StoreHTTPClient(
        context: context,
        maximumBodySize: 1_024,
        session: session
    )
    MockURLProtocol.statusCode = 200
    MockURLProtocol.body = Data(#"{"value":"ok"}"#.utf8)

    let response = try await client.get(
        URL(string: "https://example.com/value")!
    )
    let object = try response.decode([String: String].self)
    #expect(response.statusCode == 200)
    #expect(object["value"] == "ok")

    await #expect(throws: StoreServiceError.self) {
        try await client.get(URL(fileURLWithPath: "/tmp/value"))
    }
    await #expect(throws: StoreServiceError.self) {
        try await client.get(
            URL(string: "https://example.com")!,
            timeout: 16
        )
    }
}

@Test
func encodesRichResultWireFormat() throws {
    let result = Store.view(
        StoreRichView(
            title: "Swift result",
            sections: [
                StoreRichSection(
                    title: "Details",
                    items: [
                        .detail("Runtime", value: "Swift"),
                        .code("let value = 1", language: "swift"),
                    ]
                ),
            ],
            actions: [
                StoreAction(
                    type: .copyText,
                    value: "Copied",
                    label: "Copy"
                ),
            ]
        )
    )
    let object = try #require(
        JSONSerialization.jsonObject(
            with: JSONEncoder().encode(result)
        ) as? [String: Any]
    )
    let view = try #require(object["view"] as? [String: Any])
    let sections = try #require(view["sections"] as? [[String: Any]])
    let actions = try #require(view["actions"] as? [[String: Any]])

    #expect(view["title"] as? String == "Swift result")
    #expect(sections.first?["title"] as? String == "Details")
    #expect(actions.first?["type"] as? String == "copyText")
}
