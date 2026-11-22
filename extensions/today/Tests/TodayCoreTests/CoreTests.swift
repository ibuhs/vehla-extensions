import Foundation
import Testing
@testable import TodayCore

private var cal: Calendar {
    var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
}
private func at(_ h: Int, _ m: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: h, minute: m))!
}
private func fmt(_ d: Date) -> String { String(format: "%02d:%02d", cal.component(.hour, from: d), cal.component(.minute, from: d)) }
private func event(_ id: String, _ title: String, _ s: Date, _ e: Date, allDay: Bool = false) -> CalendarItem {
    CalendarItem(id: id, title: title, start: s, end: e, isAllDay: allDay)
}

@Suite struct WeatherTests {
    @Test func codes() {
        #expect(WeatherCondition.forCode(0).symbol == "sun.max.fill")
        #expect(WeatherCondition.forCode(63).isWet)
        #expect(WeatherCondition.forCode(95).summary == "Thunderstorms")
        #expect(!WeatherCondition.forCode(3).isWet)
        #expect(WeatherCondition.forCode(999).summary == "Unsettled")
    }

    @Test func parsesForecast() throws {
        let json = #"{"current":{"temperature_2m":12.3,"weather_code":61},"daily":{"temperature_2m_max":[14.1],"temperature_2m_min":[7.0],"precipitation_probability_max":[80]}}"#
        let w = try OpenMeteo.parseForecast(Data(json.utf8))
        #expect(w == WeatherSnapshot(temperatureC: 12.3, code: 61, highC: 14.1, lowC: 7.0, precipitationChance: 80))
    }

    @Test func forecastToleratesMissingDaily() throws {
        let json = #"{"current":{"temperature_2m":5,"weather_code":0},"daily":{"temperature_2m_max":[null],"temperature_2m_min":[],"precipitation_probability_max":null}}"#
        let w = try OpenMeteo.parseForecast(Data(json.utf8))
        #expect(w.highC == 5)
        #expect(w.precipitationChance == 0)
    }

    @Test func rejectsGarbage() {
        #expect(throws: WeatherError.self) { try OpenMeteo.parseForecast(Data("{}".utf8)) }
    }

    @Test func parsesGeocode() throws {
        let json = #"{"results":[{"name":"Oslo","latitude":59.91,"longitude":10.75,"country":"Norway","admin1":"Oslo"}]}"#
        #expect(try OpenMeteo.parseGeocode(Data(json.utf8)) == Place(name: "Oslo", latitude: 59.91, longitude: 10.75))
        #expect(throws: WeatherError.self) { try OpenMeteo.parseGeocode(Data("{}".utf8)) }
    }

    @Test func urlsCarryTheirQuery() {
        let url = OpenMeteo.forecastURL(for: Place(name: "x", latitude: 1.5, longitude: -2)).absoluteString
        #expect(url.contains("latitude=1.5") && url.contains("longitude=-2.0") && url.contains("timezone=auto"))
        #expect(OpenMeteo.geocodeURL(for: "New York").absoluteString.contains("name=New%20York"))
    }

    @Test func temperatureUnits() {
        #expect(Temperature.format(20, fahrenheit: false) == "20°")
        #expect(Temperature.format(20, fahrenheit: true) == "68°")
        #expect(Temperature.format(-0.4, fahrenheit: false) == "-0°" || Temperature.format(-0.4, fahrenheit: false) == "0°")
    }
}

@Suite struct JoinTests {
    @Test func findsCommonProviders() {
        #expect(JoinLink.find(in: [nil, "Join: https://acme.zoom.us/j/123?pwd=abc now"])?.host == "acme.zoom.us")
        #expect(JoinLink.find(in: ["https://meet.google.com/abc-defg-hij"])?.absoluteString == "https://meet.google.com/abc-defg-hij")
        #expect(JoinLink.find(in: ["https://teams.microsoft.com/l/meetup-join/xyz"]) != nil)
        #expect(JoinLink.find(in: ["https://example.com/zoom", "Conference Room 4"]) == nil)
        #expect(JoinLink.find(in: [nil, nil]) == nil)
    }
}

@Suite struct BriefTests {
    private let standup = event("1", "Standup", at(9, 30), at(10))
    private let review = event("2", "Design review", at(14), at(15))

    @Test func greetingByHour() {
        #expect(BriefComposer.greeting(hour: 8) == "Good morning")
        #expect(BriefComposer.greeting(hour: 13) == "Good afternoon")
        #expect(BriefComposer.greeting(hour: 21) == "Good evening")
        #expect(BriefComposer.greeting(hour: 2) == "Good evening")
    }

    @Test func composesFullDay() {
        let weather = WeatherSnapshot(temperatureC: 12, code: 2, highC: 15, lowC: 6, precipitationChance: 70)
        let brief = BriefComposer.compose(
            now: at(8), events: [review, standup, event("a", "Holiday", at(0), at(23), allDay: true)],
            reminders: [ReminderItem(id: "r", title: "Pay rent", due: nil)], weather: weather, calendar: cal, time: fmt)
        #expect(brief.greeting == "Good morning")
        #expect(brief.sentences == [
            "2 events left today, starting with Standup at 09:30.",
            "All day: Holiday.",
            "Partly cloudy, 12° with a high of 15°. Rain is likely (70%).",
            "1 reminder due today.",
        ])
    }

    @Test func inProgressAndClearCalendar() {
        let during = BriefComposer.compose(now: at(9, 45), events: [standup], reminders: [], weather: nil, calendar: cal, time: fmt)
        #expect(during.sentences == ["Standup is on until 10:00."])
        let clear = BriefComposer.compose(now: at(9), events: [], reminders: [], weather: nil, calendar: cal, time: fmt)
        #expect(clear.sentences == ["Your calendar is clear today."])
        let done = BriefComposer.compose(now: at(18), events: [standup], reminders: [], weather: nil, calendar: cal, time: fmt)
        #expect(done.sentences == ["Nothing else on your calendar today."])
    }

    @Test func wetWeatherDoesNotAddRainWarning() {
        let weather = WeatherSnapshot(temperatureC: 9, code: 63, highC: 10, lowC: 6, precipitationChance: 90)
        let brief = BriefComposer.compose(now: at(8), events: [], reminders: [], weather: weather, calendar: cal, time: fmt)
        #expect(!brief.text.contains("likely"))
    }

    @Test func upcomingWindow() {
        let events = [standup, review, event("d", "All day", at(0), at(23), allDay: true)]
        #expect(BriefComposer.upcoming(events, now: at(9, 25))?.id == "1")
        #expect(BriefComposer.upcoming(events, now: at(9, 0)) == nil)      // 30 min away
        #expect(BriefComposer.upcoming(events, now: at(9, 31)) == nil)     // already started
        #expect(BriefComposer.upcoming(events, now: at(13, 55), leadMinutes: 10)?.id == "2")
    }
}

@Suite struct AIBriefTests {
    @Test func factsContainOnlyTitlesTimesAndWeather() {
        let e = CalendarItem(id: "1", title: "Standup", start: at(9, 30), end: at(10), location: "Secret room 5",
                             joinURL: URL(string: "https://zoom.us/j/1"))
        let text = AIBrief.facts(now: at(8), events: [e], reminders: [ReminderItem(id: "r", title: "Pay rent", due: nil)],
                                 weather: WeatherSnapshot(temperatureC: 12, code: 61, highC: 14, lowC: 7, precipitationChance: 80), time: fmt)
        #expect(text.contains("- 09:30–10:00 Standup"))
        #expect(text.contains("Rain") && text.contains("80% chance"))
        #expect(text.contains("Pay rent"))
        #expect(!text.contains("Secret room") && !text.contains("zoom.us"))
    }

    @Test func factsUseTheViewersTemperatureUnit() {
        let w = WeatherSnapshot(temperatureC: 18, code: 1, highC: 22, lowC: 15, precipitationChance: 0)
        let f = AIBrief.facts(now: at(8), events: [], reminders: [], weather: w, fahrenheit: true, time: fmt)
        #expect(f.contains("now 64°") && f.contains("high 72°") && f.contains("Use Fahrenheit"))
        let c = AIBrief.facts(now: at(8), events: [], reminders: [], weather: w, fahrenheit: false, time: fmt)
        #expect(c.contains("now 18°") && c.contains("Use Celsius"))
    }

    @Test func truncatedRepliesAreCutToACompleteSentence() throws {
        let gemini = #"{"candidates":[{"finishReason":"MAX_TOKENS","content":{"parts":[{"text":"It is mostly clear. You have two events. An expected"}]}}]}"#
        #expect(try AIBrief.parse(Data(gemini.utf8), provider: .gemini) == "It is mostly clear. You have two events.")
        let openai = #"{"choices":[{"finish_reason":"length","message":{"content":"Good morning! Standup is at 9, and then"}}]}"#
        #expect(try AIBrief.parse(Data(openai.utf8), provider: .openai) == "Good morning!")
        let anthropic = #"{"stop_reason":"max_tokens","content":[{"type":"text","text":"One sentence only and then"}]}"#
        #expect(try AIBrief.parse(Data(anthropic.utf8), provider: .anthropic) == "One sentence only and then")
        // Finished replies are left alone.
        let done = #"{"candidates":[{"finishReason":"STOP","content":{"parts":[{"text":"All done"}]}}]}"#
        #expect(try AIBrief.parse(Data(done.utf8), provider: .gemini) == "All done")
        #expect(AIBrief.completeSentences("No punctuation") == "No punctuation")
    }

    @Test func tokenBudgetsLeaveRoomForThinkingModels() throws {
        let g = try AIBrief.makeRequest(facts: "f", config: AIConfig(provider: .gemini), apiKey: "k")
        let gen = (try JSONSerialization.jsonObject(with: g.httpBody!) as? [String: Any])?["generationConfig"] as? [String: Any]
        #expect((gen?["maxOutputTokens"] as? Int ?? 0) >= 1000)
        let o = try AIBrief.makeRequest(facts: "f", config: AIConfig(provider: .openai), apiKey: "k")
        #expect(((try JSONSerialization.jsonObject(with: o.httpBody!) as? [String: Any])?["max_completion_tokens"] as? Int ?? 0) >= 500)
    }

    private func body(_ r: URLRequest) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: r.httpBody!) as? [String: Any])
    }

    @Test func anthropicRequest() throws {
        let r = try AIBrief.makeRequest(facts: "Now: 08:00", config: AIConfig(provider: .anthropic), apiKey: "sk-ant")
        #expect(r.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(r.value(forHTTPHeaderField: "x-api-key") == "sk-ant")
        #expect(r.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        let b = try body(r)
        #expect(b["model"] as? String == "claude-haiku-5-5")
        #expect(b["system"] as? String == AIBrief.system)
    }

    @Test func openAIRequestUsesBearerAndCompletionTokens() throws {
        let r = try AIBrief.makeRequest(facts: "facts", config: AIConfig(provider: .openai, model: "gpt-4.1-mini"), apiKey: " sk-oai \n")
        #expect(r.url?.absoluteString == "https://api.openai.com/v1/chat/completions")
        #expect(r.value(forHTTPHeaderField: "authorization") == "Bearer sk-oai")
        let b = try body(r)
        #expect(b["model"] as? String == "gpt-4.1-mini")
        #expect(b["max_completion_tokens"] as? Int == 600)
        #expect(b["max_tokens"] == nil)
        let messages = try #require(b["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["system", "user"])
    }

    @Test func deepSeekIsOpenAIStyleWithMaxTokens() throws {
        let r = try AIBrief.makeRequest(facts: "f", config: AIConfig(provider: .deepseek), apiKey: "k")
        #expect(r.url?.absoluteString == "https://api.deepseek.com/chat/completions")
        let b = try body(r)
        #expect(b["model"] as? String == "deepseek-chat")
        #expect(b["max_tokens"] as? Int == 600)
        #expect(b["max_completion_tokens"] == nil)
    }

    @Test func geminiKeepsTheKeyOutOfTheURL() throws {
        let r = try AIBrief.makeRequest(facts: "f", config: AIConfig(provider: .gemini, model: "gemini-2.5-flash"), apiKey: "g-key")
        #expect(r.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent")
        #expect(!r.url!.absoluteString.contains("g-key"))
        #expect(r.value(forHTTPHeaderField: "x-goog-api-key") == "g-key")
        let b = try body(r)
        #expect(b["systemInstruction"] != nil)
        #expect((b["contents"] as? [[String: Any]])?.first?["role"] as? String == "user")
    }

    @Test func customEndpointRules() throws {
        let cfg = AIConfig(provider: .custom, model: "llama3.2", customBaseURL: "https://openrouter.ai/api/v1/")
        #expect(try AIBrief.makeRequest(facts: "f", config: cfg, apiKey: "k").url?.absoluteString
                == "https://openrouter.ai/api/v1/chat/completions")
        // Already a full path: don't double it.
        let full = AIConfig(provider: .custom, model: "m", customBaseURL: "https://x.example/v1/chat/completions")
        #expect(try AIBrief.endpoint(for: full).absoluteString == "https://x.example/v1/chat/completions")
        // Local models need no key and may use http on localhost.
        let local = AIConfig(provider: .custom, model: "llama3.2", customBaseURL: "http://localhost:11434/v1")
        let r = try AIBrief.makeRequest(facts: "f", config: local, apiKey: nil)
        #expect(r.url?.absoluteString == "http://localhost:11434/v1/chat/completions")
        #expect(r.value(forHTTPHeaderField: "authorization") == nil)
        // Plain http to a remote host, junk, and a missing model are all refused.
        #expect(throws: AIBrief.AIError.self) { try AIBrief.endpoint(for: AIConfig(provider: .custom, model: "m", customBaseURL: "http://evil.example/v1")) }
        #expect(throws: AIBrief.AIError.self) { try AIBrief.endpoint(for: AIConfig(provider: .custom, model: "m", customBaseURL: "not a url")) }
        #expect(throws: AIBrief.AIError.self) { try AIBrief.endpoint(for: AIConfig(provider: .custom, model: "m", customBaseURL: "")) }
        #expect(throws: AIBrief.AIError.missingModel) { try AIBrief.makeRequest(facts: "f", config: AIConfig(provider: .custom, customBaseURL: "https://a.b/v1"), apiKey: nil) }
    }

    @Test func destinationHostForConsentText() {
        #expect(AIBrief.destinationHost(AIConfig(provider: .anthropic)) == "api.anthropic.com")
        #expect(AIBrief.destinationHost(AIConfig(provider: .gemini)) == "generativelanguage.googleapis.com")
        #expect(AIBrief.destinationHost(AIConfig(provider: .deepseek)) == "api.deepseek.com")
        #expect(AIBrief.destinationHost(AIConfig(provider: .custom, customBaseURL: "https://openrouter.ai/api/v1")) == "openrouter.ai")
        #expect(AIBrief.destinationHost(AIConfig(provider: .custom)) == "your endpoint")
    }

    @Test func everyProviderHasItsOwnSecret() {
        let ids = AIProvider.all.map(\.secretID)
        #expect(Set(ids).count == AIProviderID.allCases.count)
        #expect(AIProvider.all.filter { !$0.requiresKey }.map(\.id) == [.custom])
    }

    @Test func parsesEachResponseShape() throws {
        let anthropic = #"{"content":[{"type":"text","text":" Good morning! "}]}"#
        #expect(try AIBrief.parse(Data(anthropic.utf8), provider: .anthropic) == "Good morning!")
        let openai = #"{"choices":[{"message":{"role":"assistant","content":"Hi there."}}]}"#
        #expect(try AIBrief.parse(Data(openai.utf8), provider: .openai) == "Hi there.")
        #expect(try AIBrief.parse(Data(openai.utf8), provider: .deepseek) == "Hi there.")
        let gemini = #"{"candidates":[{"content":{"parts":[{"text":"One."},{"text":"Two."}]}}]}"#
        #expect(try AIBrief.parse(Data(gemini.utf8), provider: .gemini) == "One. Two.")
    }

    @Test func surfacesAPIErrorsAndEmptyResults() {
        #expect(throws: AIBrief.AIError.api("invalid x-api-key")) { try AIBrief.parse(Data(#"{"error":{"message":"invalid x-api-key"}}"#.utf8), provider: .anthropic) }
        #expect(throws: AIBrief.AIError.api("quota")) { try AIBrief.parse(Data(#"{"error":"quota"}"#.utf8), provider: .openai) }
        #expect(throws: AIBrief.AIError.empty) { try AIBrief.parse(Data(#"{"content":[]}"#.utf8), provider: .anthropic) }
        #expect(throws: AIBrief.AIError.empty) { try AIBrief.parse(Data(#"{"candidates":[]}"#.utf8), provider: .gemini) }
        #expect(throws: AIBrief.AIError.empty) { try AIBrief.parse(Data("nope".utf8), provider: .openai) }
    }
}

@Suite struct AIModelsTests {
    private func models(_ json: String, _ p: AIProviderID) throws -> [String] { try AIModels.parse(Data(json.utf8), provider: p) }

    @Test func anthropicKeepsServerOrder() throws {
        let json = #"{"data":[{"id":"claude-opus-5-5"},{"id":"claude-haiku-5-5"},{"id":"claude-opus-5-5"}]}"#
        #expect(try models(json, .anthropic) == ["claude-opus-5-5", "claude-haiku-5-5"])
    }

    @Test func openAIFiltersToChatModels() throws {
        let json = #"{"data":[{"id":"text-embedding-3-small"},{"id":"gpt-4o"},{"id":"whisper-1"},{"id":"gpt-4o-realtime-preview"},{"id":"o3-mini"},{"id":"gpt-4o-mini"},{"id":"dall-e-3"},{"id":"gpt-4o-mini-tts"},{"id":"gpt-3.5-turbo-instruct"}]}"#
        #expect(try models(json, .openai) == ["gpt-4o", "gpt-4o-mini", "o3-mini"])
    }

    @Test func geminiKeepsGenerateContentModelsAndStripsPrefix() throws {
        let json = #"{"models":[{"name":"models/gemini-2.5-flash","supportedGenerationMethods":["generateContent","countTokens"]},{"name":"models/text-embedding-004","supportedGenerationMethods":["embedContent"]},{"name":"models/gemini-2.5-pro","supportedGenerationMethods":["generateContent"]},{"name":"models/gemma-3","supportedGenerationMethods":["generateContent"]}]}"#
        #expect(try models(json, .gemini) == ["gemini-2.5-flash", "gemini-2.5-pro"])
    }

    @Test func deepSeekAndCustomTakeEverything() throws {
        #expect(try models(#"{"data":[{"id":"deepseek-reasoner"},{"id":"deepseek-chat"}]}"#, .deepseek) == ["deepseek-chat", "deepseek-reasoner"])
        #expect(try models(#"{"data":[{"id":"llama3.2:latest"},{"id":"qwen2.5"}]}"#, .custom) == ["llama3.2:latest", "qwen2.5"])
    }

    @Test func errorsAndEmpty() {
        #expect(throws: AIBrief.AIError.api("bad key")) { try models(#"{"error":{"message":"bad key"}}"#, .openai) }
        #expect(throws: AIBrief.AIError.empty) { try models(#"{"data":[]}"#, .deepseek) }
        #expect(throws: AIBrief.AIError.empty) { try models("nope", .custom) }
    }

    @Test func listRequests() throws {
        let a = try AIModels.makeListRequest(config: AIConfig(provider: .anthropic), apiKey: "k")
        #expect(a.url?.absoluteString == "https://api.anthropic.com/v1/models?limit=100")
        #expect(a.value(forHTTPHeaderField: "x-api-key") == "k")
        let g = try AIModels.makeListRequest(config: AIConfig(provider: .gemini), apiKey: "gk")
        #expect(g.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models?pageSize=100")
        #expect(g.value(forHTTPHeaderField: "x-goog-api-key") == "gk")
        let o = try AIModels.makeListRequest(config: AIConfig(provider: .openai), apiKey: "ok")
        #expect(o.url?.absoluteString == "https://api.openai.com/v1/models")
        #expect(o.value(forHTTPHeaderField: "authorization") == "Bearer ok")
        let d = try AIModels.makeListRequest(config: AIConfig(provider: .deepseek), apiKey: "dk")
        #expect(d.url?.absoluteString == "https://api.deepseek.com/models")
        let local = try AIModels.makeListRequest(config: AIConfig(provider: .custom, customBaseURL: "http://localhost:11434/v1/"), apiKey: nil)
        #expect(local.url?.absoluteString == "http://localhost:11434/v1/models")
        #expect(local.value(forHTTPHeaderField: "authorization") == nil)
        #expect(throws: AIBrief.AIError.self) { try AIModels.makeListRequest(config: AIConfig(provider: .custom, customBaseURL: "http://evil.example"), apiKey: nil) }
    }

    @Test func optionsAlwaysIncludeTheCurrentChoice() {
        let cfg = AIConfig(provider: .openai, model: "gpt-5-old")
        #expect(AIModels.options(live: ["gpt-4o"], config: cfg) == ["gpt-5-old", "gpt-4o"])
        #expect(AIModels.options(live: nil, config: AIConfig(provider: .deepseek)).first == "deepseek-chat")
        #expect(AIModels.options(live: [], config: AIConfig(provider: .custom)) == [])
        #expect(AIProviderID.allCases.filter { $0 != .custom }.allSatisfy { !AIModels.fallback($0).isEmpty })
    }
}
