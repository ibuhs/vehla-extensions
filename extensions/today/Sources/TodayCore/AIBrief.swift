import Foundation

// MARK: - Providers

public enum AIProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case anthropic, openai, gemini, deepseek, custom
    public var id: String { rawValue }
}

public struct AIProvider: Sendable, Identifiable {
    public enum Style: Sendable { case anthropic, openAICompatible, gemini }

    public let id: AIProviderID
    public let name: String
    public let shortName: String
    public let style: Style
    public let defaultModel: String
    /// The `secrets` id in the manifest that holds this provider's API key.
    public let secretID: String
    public let secretLabel: String
    public let requiresKey: Bool
    /// Base URL for OpenAI-style providers (without `/chat/completions`).
    public let baseURL: String?

    public static let all: [AIProvider] = [
        AIProvider(id: .anthropic, name: "Anthropic (Claude)", shortName: "Claude", style: .anthropic,
                   defaultModel: "claude-haiku-5-5", secretID: "anthropicKey", secretLabel: "Anthropic API key",
                   requiresKey: true, baseURL: nil),
        AIProvider(id: .openai, name: "OpenAI", shortName: "OpenAI", style: .openAICompatible,
                   defaultModel: "gpt-4o-mini", secretID: "openaiKey", secretLabel: "OpenAI API key",
                   requiresKey: true, baseURL: "https://api.openai.com/v1"),
        AIProvider(id: .gemini, name: "Google Gemini", shortName: "Gemini", style: .gemini,
                   defaultModel: "gemini-2.0-flash", secretID: "geminiKey", secretLabel: "Gemini API key",
                   requiresKey: true, baseURL: nil),
        AIProvider(id: .deepseek, name: "DeepSeek", shortName: "DeepSeek", style: .openAICompatible,
                   defaultModel: "deepseek-chat", secretID: "deepseekKey", secretLabel: "DeepSeek API key",
                   requiresKey: true, baseURL: "https://api.deepseek.com"),
        AIProvider(id: .custom, name: "Custom (OpenAI-compatible)", shortName: "Custom", style: .openAICompatible,
                   defaultModel: "", secretID: "customKey", secretLabel: "Custom endpoint API key",
                   requiresKey: false, baseURL: nil),
    ]

    public static func provider(_ id: AIProviderID) -> AIProvider { all.first { $0.id == id } ?? all[0] }
}

/// Which provider, model and (for Custom) endpoint to use.
public struct AIConfig: Equatable, Sendable {
    public var provider: AIProviderID
    public var model: String
    public var customBaseURL: String

    public init(provider: AIProviderID = .anthropic, model: String = "", customBaseURL: String = "") {
        self.provider = provider; self.model = model; self.customBaseURL = customBaseURL
    }

    public var info: AIProvider { AIProvider.provider(provider) }
    public var effectiveModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? info.defaultModel : trimmed
    }
}

// MARK: - Brief

/// An optional, opt-in summary written by a model from the same facts the local brief uses.
/// Only event titles/times, reminder titles and the weather are sent; never notes or attendees.
public enum AIBrief {
    public static let system = """
        You write the short morning brief shown in a Mac notch widget. Use only the facts given. \
        Two or three friendly sentences, under 55 words, second person, no emojis, no markdown, \
        and mention nothing that isn't in the facts. Always end on a complete sentence.
        """

    public static func facts(
        now: Date, events: [CalendarItem], reminders: [ReminderItem], weather: WeatherSnapshot?,
        fahrenheit: Bool = false,
        time: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
    ) -> String {
        "Now: \(time(now))\n" + changeKey(events: events, reminders: reminders, weather: weather,
                                           fahrenheit: fahrenheit, time: time)
    }

    /// The facts without the clock: two equal keys mean there is nothing new to write about. (Comparing the
    /// facts themselves would differ every minute, and ask for a new brief every minute.)
    public static func changeKey(
        events: [CalendarItem], reminders: [ReminderItem], weather: WeatherSnapshot?,
        fahrenheit: Bool = false,
        time: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
    ) -> String {
        var lines: [String] = []
        let timed = events.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        lines.append("Events today:")
        lines += timed.isEmpty ? ["- none"] : timed.prefix(12).map { "- \(time($0.start))–\(time($0.end)) \($0.title)" }
        events.filter(\.isAllDay).prefix(3).forEach { lines.append("- all day: \($0.title)") }
        if let weather {
            let t = { (c: Double) in Temperature.format(c, fahrenheit: fahrenheit) }
            lines.append("Weather: \(WeatherCondition.forCode(weather.code).summary), now \(t(weather.temperatureC)), "
                         + "high \(t(weather.highC)), low \(t(weather.lowC)), "
                         + "\(weather.precipitationChance)% chance of rain. Use \(fahrenheit ? "Fahrenheit" : "Celsius").")
        }
        lines.append("Reminders due: \(reminders.isEmpty ? "none" : reminders.prefix(8).map(\.title).joined(separator: "; "))")
        return lines.joined(separator: "\n")
    }

    public enum AIError: Error, LocalizedError, Equatable {
        case api(String), empty, badEndpoint(String), missingModel
        public var errorDescription: String? {
            switch self {
            case .api(let message): return message
            case .empty: return "The model returned no text."
            case .badEndpoint(let why): return why
            case .missingModel: return "Enter a model name for the custom endpoint."
            }
        }
    }

    /// The host that will receive the facts, for the consent text.
    public static func destinationHost(_ config: AIConfig) -> String {
        (try? endpoint(for: config).host) ?? "your endpoint"
    }

    // MARK: Requests

    public static func endpoint(for config: AIConfig) throws -> URL {
        let info = config.info
        switch info.style {
        case .anthropic:
            return URL(string: "https://api.anthropic.com/v1/messages")!
        case .gemini:
            let model = config.effectiveModel.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? config.effectiveModel
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        case .openAICompatible:
            let base = info.baseURL ?? config.customBaseURL.trimmingCharacters(in: .whitespaces)
            return try chatCompletionsURL(base)
        }
    }

    /// Custom endpoints must be https, except for a model running on this Mac.
    static func chatCompletionsURL(_ base: String) throws -> URL {
        guard !base.isEmpty, let url = URL(string: base), let scheme = url.scheme, let host = url.host else {
            throw AIError.badEndpoint("Enter the endpoint's base URL, e.g. https://openrouter.ai/api/v1")
        }
        let local = ["localhost", "127.0.0.1", "::1"].contains(host)
        guard scheme == "https" || (scheme == "http" && local) else {
            throw AIError.badEndpoint("Endpoints must use https (http is allowed only for localhost).")
        }
        var text = base
        while text.hasSuffix("/") { text.removeLast() }
        if !text.hasSuffix("/chat/completions") { text += "/chat/completions" }
        guard let final = URL(string: text) else { throw AIError.badEndpoint("That URL isn't valid.") }
        return final
    }

    public static func makeRequest(facts: String, config: AIConfig, apiKey: String?) throws -> URLRequest {
        let info = config.info
        if info.id == .custom && config.effectiveModel.isEmpty { throw AIError.missingModel }
        var request = URLRequest(url: try endpoint(for: config))
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let body: [String: Any]
        switch info.style {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = ["model": config.effectiveModel, "max_tokens": 300, "system": system,
                    "messages": [["role": "user", "content": facts]]]
        case .gemini:
            // The key goes in a header, not the URL, so it never lands in logs or history.
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            body = ["systemInstruction": ["parts": [["text": system]]],
                    "contents": [["role": "user", "parts": [["text": facts]]]],
                    "generationConfig": ["maxOutputTokens": 1200, "temperature": 0.6]]
        case .openAICompatible:
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization") }
            var json: [String: Any] = [
                "model": config.effectiveModel,
                "messages": [["role": "system", "content": system], ["role": "user", "content": facts]],
            ]
            // OpenAI's current models reject max_tokens; everyone else expects it.
            json[info.id == .openai ? "max_completion_tokens" : "max_tokens"] = 600
            body = json
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: Responses

    public static func parse(_ data: Data, provider: AIProviderID) throws -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AIError.empty }
        if let error = object["error"] as? [String: Any] {
            throw AIError.api((error["message"] as? String) ?? "Request failed.")
        }
        if let error = object["error"] as? String { throw AIError.api(error) }

        let text: String?
        let truncated: Bool
        switch AIProvider.provider(provider).style {
        case .anthropic:
            text = (object["content"] as? [[String: Any]])?
                .compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: " ")
            truncated = object["stop_reason"] as? String == "max_tokens"
        case .gemini:
            let candidate = (object["candidates"] as? [[String: Any]])?.first
            text = (candidate?["content"] as? [String: Any])
                .flatMap { $0["parts"] as? [[String: Any]] }?
                .compactMap { $0["text"] as? String }.joined(separator: " ")
            truncated = candidate?["finishReason"] as? String == "MAX_TOKENS"
        case .openAICompatible:
            let choice = (object["choices"] as? [[String: Any]])?.first
            text = (choice?["message"] as? [String: Any])?["content"] as? String
            truncated = choice?["finish_reason"] as? String == "length"
        }
        let cleaned = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cleaned, !cleaned.isEmpty else { throw AIError.empty }
        return truncated ? completeSentences(cleaned) : cleaned
    }

    /// A reply cut off by the token limit ends mid-sentence; keep everything up to the last full stop.
    /// If there is none, the partial text is better than nothing.
    public static func completeSentences(_ text: String) -> String {
        guard let end = text.lastIndex(where: { ".!?".contains($0) }) else { return text }
        return String(text[...end])
    }
}
