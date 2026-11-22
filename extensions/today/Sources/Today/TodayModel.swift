import AppKit
import EventKit
import NotchKit
import SwiftUI
import TodayCore
import VehlaNotchSDK

struct TodayPrefs: Codable, Equatable, Sendable {
    var place: Place?
    var aiEnabled: Bool?
    var provider: AIProviderID?
    /// Model name per provider id; empty means the provider's default.
    var models: [String: String]?
    var customBaseURL: String?
}

enum AIState: Equatable {
    case off, loading, ready, failed(String)
}

@MainActor
final class TodayModel: ObservableObject {
    @Published private(set) var events: [CalendarItem] = []
    @Published private(set) var reminders: [ReminderItem] = []
    @Published private(set) var weather: WeatherSnapshot?
    @Published private(set) var weatherError: String?
    @Published private(set) var brief = Brief(greeting: BriefComposer.greeting(hour: 9), sentences: [])
    @Published private(set) var aiText: String?
    @Published private(set) var aiState: AIState = .off
    @Published private(set) var eventAccess: Access = .unknown
    @Published private(set) var reminderAccess: Access = .unknown
    @Published private(set) var prefs = TodayPrefs()
    @Published private(set) var status: String?
    @Published private(set) var searchingPlace = false
    @Published private(set) var liveModels: [AIProviderID: [String]] = [:]
    @Published private(set) var loadingModels = false
    @Published private(set) var modelsNote: String?

    let fahrenheit = Locale.current.measurementSystem == .us
    private let calendar = SystemCalendar()
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        return URLSession(configuration: c)
    }()
    private var notch: VehlaNotch?
    private var store: NKJSONStore<TodayPrefs>?
    private var loop: Task<Void, Never>?
    private var aiTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private var weatherFetchedAt: Date?
    private var aiFactsHash: Int?
    private var aiFetchedAt: Date?
    private var announcedEventID: String?

    var aiEnabled: Bool { prefs.aiEnabled == true }

    var aiConfig: AIConfig {
        let provider = prefs.provider ?? .anthropic
        return AIConfig(provider: provider, model: prefs.models?[provider.rawValue] ?? "",
                        customBaseURL: prefs.customBaseURL ?? "")
    }

    private var apiKey: String? {
        let value = notch?.secret(named: aiConfig.info.secretID) ?? ""
        return value.isEmpty ? nil : value
    }

    var hasAPIKey: Bool { apiKey != nil }

    // MARK: Lifecycle

    func start(_ notch: VehlaNotch) {
        self.notch = notch
        let store = NKJSONStore<TodayPrefs>(directory: notch.dataDirectory, name: "today.json")
        self.store = store
        prefs = store.load() ?? TodayPrefs()
        aiState = aiEnabled ? .ready : .off
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        loop = Task { [weak self] in
            await self?.refresh(force: true)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await self?.refresh()
            }
        }
    }

    func stop() {
        loop?.cancel(); aiTask?.cancel(); statusTask?.cancel()
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        notch?.end("next-event")
        notch = nil
    }

    // MARK: Refresh

    func refresh(force: Bool = false) async {
        eventAccess = calendar.eventAccess
        reminderAccess = calendar.reminderAccess
        events = eventAccess == .granted ? calendar.events(on: Date()) : []
        if reminderAccess == .granted { reminders = await calendar.reminders(dueBy: Date()) } else { reminders = [] }
        await refreshWeather(force: force)
        recomposeBrief()
        announceNextEvent()
        maybeRequestAI(force: false)
    }

    private func refreshWeather(force: Bool) async {
        guard let place = prefs.place else { weather = nil; return }
        if !force, let fetched = weatherFetchedAt, Date().timeIntervalSince(fetched) < 30 * 60 { return }
        do {
            let (data, _) = try await session.data(from: OpenMeteo.forecastURL(for: place))
            weather = try OpenMeteo.parseForecast(data)
            weatherFetchedAt = Date()
            weatherError = nil
        } catch {
            weatherError = error.localizedDescription
        }
    }

    private func recomposeBrief() {
        brief = BriefComposer.compose(now: Date(), events: events, reminders: reminders, weather: weather,
                                      fahrenheit: fahrenheit)
    }

    private func announceNextEvent() {
        guard let notch else { return }
        let now = Date()
        if let next = BriefComposer.upcoming(events, now: now) {
            announcedEventID = next.id
            notch.show(VehlaNotchActivity(
                id: "next-event", systemImage: "calendar", title: RiskLimit.cut(next.title, 58),
                detail: next.location.map { RiskLimit.cut($0, 78) }, tintHex: "#5C9EFF",
                timerEnd: next.start, duration: next.start.timeIntervalSince(now) + 60,
                buttons: next.joinURL == nil ? [] : [VehlaNotchActivityButton(id: "join", title: "Join", systemImage: "video.fill")]))
        } else if announcedEventID != nil {
            announcedEventID = nil
            notch.end("next-event")
        }
    }

    func activityAction(_ activityID: String, _ actionID: String) {
        guard activityID == "next-event" else { return }
        if actionID == "join", let url = events.first(where: { $0.id == announcedEventID })?.joinURL {
            notch?.open(url)
        } else {
            notch?.openTab("today")
        }
    }

    // MARK: Access

    func requestCalendar() {
        Task { _ = await calendar.requestEvents(); await refresh() }
    }

    func requestReminders() {
        Task { _ = await calendar.requestReminders(); await refresh() }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Place and AI settings

    func setPlace(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        searchingPlace = true
        Task {
            defer { searchingPlace = false }
            do {
                let (data, _) = try await session.data(from: OpenMeteo.geocodeURL(for: trimmed))
                let place = try OpenMeteo.parseGeocode(data)
                prefs.place = place
                store?.save(prefs)
                weatherFetchedAt = nil
                await refresh(force: true)
                flash("Weather set to \(place.name)")
            } catch {
                flash(error.localizedDescription)
            }
        }
    }

    func setAI(enabled: Bool) {
        prefs.aiEnabled = enabled
        store?.save(prefs)
        if enabled {
            aiState = .ready
            maybeRequestAI(force: true)
            loadModels()
        } else {
            aiTask?.cancel()
            aiState = .off
            aiText = nil
        }
    }

    func regenerateAI() { maybeRequestAI(force: true) }

    func setProvider(_ provider: AIProviderID) {
        guard provider != aiConfig.provider else { return }
        prefs.provider = provider
        providerChanged()
        loadModels()
    }

    func setModel(_ model: String) {
        let trimmed = model.trimmingCharacters(in: .whitespaces)
        guard trimmed != (prefs.models?[aiConfig.provider.rawValue] ?? "") else { return }
        var models = prefs.models ?? [:]
        models[aiConfig.provider.rawValue] = trimmed
        prefs.models = models
        providerChanged()
    }

    func setCustomBaseURL(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        guard trimmed != (prefs.customBaseURL ?? "") else { return }
        prefs.customBaseURL = trimmed
        liveModels[.custom] = nil
        providerChanged()
        loadModels()
    }

    /// Models for the dropdown: the provider's live list when we have it, else a built-in short list.
    var modelOptions: [String] { AIModels.options(live: liveModels[aiConfig.provider], config: aiConfig) }

    func loadModels() {
        let config = aiConfig
        if config.info.requiresKey && apiKey == nil {
            modelsNote = "Add your key to load the live model list."
            return
        }
        let request: URLRequest
        do { request = try AIModels.makeListRequest(config: config, apiKey: apiKey) }
        catch { modelsNote = error.localizedDescription; return }
        loadingModels = true
        modelsNote = nil
        let provider = config.provider
        Task { [session] in
            defer { self.loadingModels = false }
            do {
                let (data, _) = try await session.data(for: request)
                self.liveModels[provider] = try AIModels.parse(data, provider: provider)
            } catch {
                self.modelsNote = provider == .custom
                    ? "This endpoint didn't list models. Enter the model name below."
                    : "Couldn't load the live list (\(error.localizedDescription)). Showing common models."
            }
        }
    }

    private func providerChanged() {
        store?.save(prefs)
        aiText = nil
        aiFactsHash = nil
        aiFetchedAt = nil
        modelsNote = nil
        if aiEnabled { maybeRequestAI(force: true) }
    }

    private func maybeRequestAI(force: Bool) {
        guard aiEnabled else { return }
        let config = aiConfig
        if config.info.requiresKey && apiKey == nil {
            aiState = .failed("Add your \(config.info.secretLabel) in Vehla's Store settings.")
            return
        }
        let facts = AIBrief.facts(now: Date(), events: events, reminders: reminders, weather: weather,
                                  fahrenheit: fahrenheit)
        let hash = facts.hashValue
        let stale = aiFetchedAt.map { Date().timeIntervalSince($0) > 60 * 60 } ?? true
        guard force || hash != aiFactsHash || stale, aiState != .loading else { return }

        let request: URLRequest
        do { request = try AIBrief.makeRequest(facts: facts, config: config, apiKey: apiKey) }
        catch { aiState = .failed(error.localizedDescription); return }

        aiFactsHash = hash
        aiState = .loading
        aiTask?.cancel()
        let provider = config.provider
        aiTask = Task { [session] in
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                do {
                    let text = try AIBrief.parse(data, provider: provider)
                    self.aiText = text
                    self.aiFetchedAt = Date()
                    self.aiState = .ready
                } catch AIBrief.AIError.empty where status >= 400 {
                    throw AIBrief.AIError.api("The service returned HTTP \(status).")
                }
            } catch is CancellationError {
                return
            } catch {
                self.aiFactsHash = nil
                self.aiState = .failed(error.localizedDescription)
            }
        }
    }

    private func flash(_ message: String) {
        status = message
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { self.status = nil }
        }
    }
}

enum RiskLimit {
    static func cut(_ text: String, _ limit: Int) -> String {
        text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}
