import Foundation

/// Lists the models a provider offers, so the settings screen can show a dropdown instead of a text box.
public enum AIModels {
    /// Shown when the live list can't be loaded (no key yet, offline, or an endpoint without /models).
    public static func fallback(_ provider: AIProviderID) -> [String] {
        switch provider {
        case .anthropic: return ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-2"]
        case .openai: return ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1"]
        case .gemini: return ["gemini-2.0-flash", "gemini-2.5-flash", "gemini-2.5-pro"]
        case .deepseek: return ["deepseek-chat", "deepseek-reasoner"]
        case .custom: return []
        }
    }

    public static func listURL(for config: AIConfig) throws -> URL {
        switch config.info.style {
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/models?limit=100")!
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=100")!
        case .openAICompatible:
            // Same base as chat completions, with /models instead.
            let chat = try AIBrief.endpoint(for: config).absoluteString
            let base = chat.hasSuffix("/chat/completions") ? String(chat.dropLast("/chat/completions".count)) : chat
            guard let url = URL(string: base + "/models") else { throw AIBrief.AIError.badEndpoint("That URL isn't valid.") }
            return url
        }
    }

    public static func makeListRequest(config: AIConfig, apiKey: String?) throws -> URLRequest {
        var request = URLRequest(url: try listURL(for: config))
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch config.info.style {
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini:
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .openAICompatible:
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "authorization") }
        }
        return request
    }

    private static let openAIExcluded = ["audio", "realtime", "transcribe", "tts", "image", "embedding",
                                         "moderation", "search", "instruct", "whisper", "dall-e", "davinci", "babbage"]

    public static func parse(_ data: Data, provider: AIProviderID) throws -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIBrief.AIError.empty
        }
        if let error = object["error"] as? [String: Any] {
            throw AIBrief.AIError.api((error["message"] as? String) ?? "Couldn't load models.")
        }
        var ids: [String]
        switch AIProvider.provider(provider).style {
        case .anthropic:
            ids = (object["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
        case .gemini:
            ids = (object["models"] as? [[String: Any]] ?? []).compactMap { model in
                let methods = model["supportedGenerationMethods"] as? [String] ?? []
                guard methods.contains("generateContent"), let name = model["name"] as? String else { return nil }
                let id = name.hasPrefix("models/") ? String(name.dropFirst("models/".count)) : name
                return id.hasPrefix("gemini") ? id : nil
            }
        case .openAICompatible:
            ids = (object["data"] as? [[String: Any]])?.compactMap { $0["id"] as? String } ?? []
            if provider == .openai {
                ids = ids.filter { id in
                    let chatLike = id.hasPrefix("gpt-") || id.hasPrefix("chatgpt") || ["o1", "o3", "o4"].contains { id.hasPrefix($0) }
                    return chatLike && !openAIExcluded.contains { id.contains($0) }
                }
            }
        }
        guard !ids.isEmpty else { throw AIBrief.AIError.empty }
        // Anthropic already returns newest first; everyone else reads best alphabetically.
        if AIProvider.provider(provider).style != .anthropic { ids.sort() }
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }.prefix(60).map { $0 }
    }

    /// The list to show: live models if present, else the fallback, always including the current choice.
    public static func options(live: [String]?, config: AIConfig) -> [String] {
        var list = (live?.isEmpty == false) ? live! : fallback(config.provider)
        let current = config.effectiveModel
        if !current.isEmpty, !list.contains(current) { list.insert(current, at: 0) }
        return list
    }
}
