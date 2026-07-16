import Foundation

public enum StoreServiceError: LocalizedError, Sendable {
    case capabilityRequired(StoreCapability)
    case dataDirectoryUnavailable
    case invalidRelativePath(String)
    case pathEscapesStorage
    case unsupportedURLScheme
    case invalidTimeout
    case requestBodyTooLarge(Int)
    case responseBodyTooLarge(Int)
    case invalidHTTPResponse
    case unsuccessfulHTTPStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .capabilityRequired(let capability):
            return "The \(capability.rawValue) capability was not granted for this invocation."
        case .dataDirectoryUnavailable:
            return "Vehla did not provide a private extension data directory."
        case .invalidRelativePath(let path):
            return "Storage path must be a safe relative path: \(path)"
        case .pathEscapesStorage:
            return "Storage path escapes the extension’s private data directory."
        case .unsupportedURLScheme:
            return "StoreHTTPClient supports only HTTP and HTTPS URLs."
        case .invalidTimeout:
            return "HTTP timeout must be greater than zero and no longer than 15 seconds."
        case .requestBodyTooLarge(let limit):
            return "HTTP request body exceeds the \(limit)-byte limit."
        case .responseBodyTooLarge(let limit):
            return "HTTP response body exceeds the \(limit)-byte limit."
        case .invalidHTTPResponse:
            return "The network request did not return an HTTP response."
        case .unsuccessfulHTTPStatus(let status):
            return "The HTTP request failed with status \(status)."
        }
    }
}

public struct StoreStorageEntry: Codable, Hashable, Sendable {
    public let path: String
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?

    public init(
        path: String,
        name: String,
        isDirectory: Bool,
        size: Int64?
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
    }
}

public struct StoreStorage: Sendable {
    public let rootURL: URL

    public init(context: StoreInvocationContext) throws {
        guard context.grants(.persistentStorage) else {
            throw StoreServiceError.capabilityRequired(.persistentStorage)
        }
        guard let dataDirectory = context.dataDirectory else {
            throw StoreServiceError.dataDirectoryUnavailable
        }
        rootURL = URL(fileURLWithPath: dataDirectory, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: true
        )
    }

    public func exists(_ path: String) throws -> Bool {
        FileManager.default.fileExists(atPath: try resolvedURL(for: path).path)
    }

    public func read(_ path: String) throws -> Data {
        try Data(contentsOf: resolvedURL(for: path))
    }

    public func readString(
        _ path: String,
        encoding: String.Encoding = .utf8
    ) throws -> String {
        let data = try read(path)
        guard let value = String(data: data, encoding: encoding) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        return value
    }

    public func read<Value: Decodable>(
        _ type: Value.Type,
        from path: String,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Value {
        try decoder.decode(type, from: read(path))
    }

    public func write(
        _ data: Data,
        to path: String,
        createDirectories: Bool = true
    ) throws {
        let destination = try resolvedURL(for: path)
        if createDirectories {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        try data.write(to: destination, options: .atomic)
    }

    public func write(
        _ value: String,
        to path: String,
        encoding: String.Encoding = .utf8
    ) throws {
        guard let data = value.data(using: encoding) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        try write(data, to: path)
    }

    public func write<Value: Encodable>(
        _ value: Value,
        to path: String,
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        try write(encoder.encode(value), to: path)
    }

    public func createDirectory(_ path: String) throws {
        try FileManager.default.createDirectory(
            at: resolvedURL(for: path),
            withIntermediateDirectories: true
        )
    }

    public func remove(_ path: String) throws {
        let target = try resolvedURL(for: path)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
    }

    public func list(_ path: String = "") throws -> [StoreStorageEntry] {
        let directory = try resolvedURL(for: path, allowRoot: true)
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .fileSizeKey,
        ]
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        .map { url in
            let values = try url.resourceValues(forKeys: keys)
            let relative = url.path.replacingOccurrences(
                of: rootURL.path + "/",
                with: ""
            )
            return StoreStorageEntry(
                path: relative,
                name: url.lastPathComponent,
                isDirectory: values.isDirectory == true,
                size: values.isDirectory == true
                    ? nil
                    : values.fileSize.map(Int64.init)
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func resolvedURL(
        for path: String,
        allowRoot: Bool = false
    ) throws -> URL {
        if path.isEmpty {
            guard allowRoot else {
                throw StoreServiceError.invalidRelativePath(path)
            }
            return rootURL
        }
        guard !path.hasPrefix("/"),
              !path.contains("\\"),
              path.split(
                separator: "/",
                omittingEmptySubsequences: false
              ).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw StoreServiceError.invalidRelativePath(path)
        }
        let candidate = rootURL.appendingPathComponent(path).standardizedFileURL
        guard candidate.path.hasPrefix(rootURL.path + "/") else {
            throw StoreServiceError.pathEscapesStorage
        }

        var existingAncestor = candidate
        while !FileManager.default.fileExists(atPath: existingAncestor.path),
              existingAncestor.path != rootURL.path {
            existingAncestor.deleteLastPathComponent()
        }
        let resolvedAncestor = existingAncestor.resolvingSymlinksInPath()
        guard resolvedAncestor.path == rootURL.path
                || resolvedAncestor.path.hasPrefix(rootURL.path + "/") else {
            throw StoreServiceError.pathEscapesStorage
        }
        return candidate
    }
}

public actor StorePreferences {
    private struct Values: Codable {
        var values: [String: Data] = [:]
    }

    private let storage: StoreStorage
    private let path = ".vehla/preferences.json"

    public init(context: StoreInvocationContext) throws {
        storage = try StoreStorage(context: context)
    }

    public func value<Value: Decodable>(
        forKey key: String,
        as type: Value.Type = Value.self
    ) throws -> Value? {
        guard let data = try load().values[key] else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    public func set<Value: Encodable>(_ value: Value, forKey key: String) throws {
        try validateKey(key)
        var stored = try load()
        stored.values[key] = try JSONEncoder().encode(value)
        try storage.write(stored, to: path)
    }

    public func removeValue(forKey key: String) throws {
        var stored = try load()
        stored.values.removeValue(forKey: key)
        try storage.write(stored, to: path)
    }

    public func contains(_ key: String) throws -> Bool {
        try load().values[key] != nil
    }

    public func allKeys() throws -> [String] {
        try load().values.keys.sorted()
    }

    public func removeAll() throws {
        try storage.write(Values(), to: path)
    }

    private func load() throws -> Values {
        guard try storage.exists(path) else { return Values() }
        return try storage.read(Values.self, from: path)
    }

    private func validateKey(_ key: String) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              key.utf8.count <= 256 else {
            throw StoreServiceError.invalidRelativePath(key)
        }
    }
}

public enum StoreLogLevel: String, Codable, Sendable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault
}

private final class StoreLogWriter: @unchecked Sendable {
    static let shared = StoreLogWriter()
    private let lock = NSLock()

    func write(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        FileHandle.standardError.write(data)
        FileHandle.standardError.write(Data([0x0A]))
    }
}

public struct StoreLogger: Sendable {
    private struct Entry: Encodable {
        let timestamp: String
        let level: StoreLogLevel
        let packageID: String
        let category: String
        let message: String
        let metadata: [String: String]
    }

    public let packageID: String
    public let category: String
    private let redactedValues: [String]

    public init(
        packageID: String,
        category: String = "extension",
        redacting values: [String] = []
    ) {
        self.packageID = packageID
        self.category = category
        redactedValues = values
            .filter { !$0.isEmpty }
            .sorted { $0.count > $1.count }
    }

    public func log(
        _ level: StoreLogLevel,
        _ message: String,
        metadata: [String: String] = [:]
    ) {
        let entry = Entry(
            timestamp: Date().formatted(.iso8601),
            level: level,
            packageID: packageID,
            category: category,
            message: redact(message),
            metadata: metadata.mapValues(redact)
        )
        guard var data = try? JSONEncoder().encode(entry) else { return }
        data.insert(contentsOf: Data("[VehlaStore] ".utf8), at: 0)
        StoreLogWriter.shared.write(data)
    }

    public func debug(_ message: String, metadata: [String: String] = [:]) {
        log(.debug, message, metadata: metadata)
    }

    public func info(_ message: String, metadata: [String: String] = [:]) {
        log(.info, message, metadata: metadata)
    }

    public func notice(_ message: String, metadata: [String: String] = [:]) {
        log(.notice, message, metadata: metadata)
    }

    public func warning(_ message: String, metadata: [String: String] = [:]) {
        log(.warning, message, metadata: metadata)
    }

    public func error(_ message: String, metadata: [String: String] = [:]) {
        log(.error, message, metadata: metadata)
    }

    public func fault(_ message: String, metadata: [String: String] = [:]) {
        log(.fault, message, metadata: metadata)
    }

    func redact(_ value: String) -> String {
        redactedValues.reduce(value) {
            $0.replacingOccurrences(of: $1, with: "[REDACTED]")
        }
    }
}

public enum StoreHTTPMethod: String, Codable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
    case head = "HEAD"
}

public struct StoreHTTPRequest: Sendable {
    public var method: StoreHTTPMethod
    public var url: URL
    public var headers: [String: String]
    public var body: Data?
    public var timeout: TimeInterval

    public init(
        method: StoreHTTPMethod = .get,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeout: TimeInterval = 10
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.timeout = timeout
    }

    public static func json<Body: Encodable>(
        method: StoreHTTPMethod = .post,
        url: URL,
        body: Body,
        headers: [String: String] = [:],
        timeout: TimeInterval = 10,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> Self {
        var resolvedHeaders = headers
        resolvedHeaders["Content-Type"] = "application/json"
        return Self(
            method: method,
            url: url,
            headers: resolvedHeaders,
            body: try encoder.encode(body),
            timeout: timeout
        )
    }
}

public struct StoreHTTPResponse: Sendable {
    public let statusCode: Int
    public let url: URL
    public let headers: [String: String]
    public let body: Data

    public init(
        statusCode: Int,
        url: URL,
        headers: [String: String],
        body: Data
    ) {
        self.statusCode = statusCode
        self.url = url
        self.headers = headers
        self.body = body
    }

    public var isSuccessful: Bool { (200..<300).contains(statusCode) }

    public func requireSuccess() throws -> Self {
        guard isSuccessful else {
            throw StoreServiceError.unsuccessfulHTTPStatus(statusCode)
        }
        return self
    }

    public func decode<Value: Decodable>(
        _ type: Value.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> Value {
        try decoder.decode(type, from: body)
    }

    public func string(encoding: String.Encoding = .utf8) -> String? {
        String(data: body, encoding: encoding)
    }
}

public struct StoreHTTPClient: Sendable {
    public static let defaultMaximumBodySize = 5 * 1_024 * 1_024
    public static let maximumRequestBodySize = 1 * 1_024 * 1_024

    private let session: URLSession
    public let maximumBodySize: Int

    public init(
        context: StoreInvocationContext,
        maximumBodySize: Int = defaultMaximumBodySize,
        session: URLSession = .shared
    ) throws {
        guard context.grants(.networkAccess) else {
            throw StoreServiceError.capabilityRequired(.networkAccess)
        }
        self.maximumBodySize = max(1, maximumBodySize)
        self.session = session
    }

    public func get(
        _ url: URL,
        headers: [String: String] = [:],
        timeout: TimeInterval = 10
    ) async throws -> StoreHTTPResponse {
        try await send(
            StoreHTTPRequest(
                url: url,
                headers: headers,
                timeout: timeout
            )
        )
    }

    public func send(
        _ request: StoreHTTPRequest
    ) async throws -> StoreHTTPResponse {
        try validate(url: request.url, timeout: request.timeout)
        if let body = request.body,
           body.count > Self.maximumRequestBodySize {
            throw StoreServiceError.requestBodyTooLarge(
                Self.maximumRequestBodySize
            )
        }
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.timeout
        request.headers.forEach {
            urlRequest.setValue($0.value, forHTTPHeaderField: $0.key)
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard data.count <= maximumBodySize else {
            throw StoreServiceError.responseBodyTooLarge(maximumBodySize)
        }
        guard let http = response as? HTTPURLResponse,
              let finalURL = http.url else {
            throw StoreServiceError.invalidHTTPResponse
        }
        try validate(url: finalURL, timeout: request.timeout)
        let headers = http.allHeaderFields.reduce(
            into: [String: String]()
        ) { result, item in
            result[String(describing: item.key)] = String(describing: item.value)
        }
        return StoreHTTPResponse(
            statusCode: http.statusCode,
            url: finalURL,
            headers: headers,
            body: data
        )
    }

    private func validate(url: URL, timeout: TimeInterval) throws {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw StoreServiceError.unsupportedURLScheme
        }
        guard timeout > 0, timeout <= 15 else {
            throw StoreServiceError.invalidTimeout
        }
    }
}

public extension StoreInvocation {
    func storage() throws -> StoreStorage {
        try StoreStorage(context: context)
    }

    func preferences() throws -> StorePreferences {
        try StorePreferences(context: context)
    }

    func logger(category: String = "extension") -> StoreLogger {
        StoreLogger(
            packageID: packageID,
            category: category,
            redacting: Array(context.secrets.values)
        )
    }

    func httpClient(
        maximumBodySize: Int = StoreHTTPClient.defaultMaximumBodySize,
        session: URLSession = .shared
    ) throws -> StoreHTTPClient {
        try StoreHTTPClient(
            context: context,
            maximumBodySize: maximumBodySize,
            session: session
        )
    }
}
