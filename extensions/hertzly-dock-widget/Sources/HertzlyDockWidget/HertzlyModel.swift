import AppKit
import Combine
import Foundation
import VehlaDockWidgetSDK

@MainActor
final class HertzlyModel: ObservableObject {
    @Published private(set) var stations: [RadioStation] = []
    @Published private(set) var selectedCountryCode = "US"
    @Published private(set) var currentStationIndex = 0
    @Published private(set) var favoriteStations: [RadioStation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var tileTextColor = NSColor.white
    @Published private(set) var popupTextColor = NSColor.white
    @Published private(set) var popupSecondaryTextColor = NSColor.secondaryLabelColor
    @Published private(set) var isDarkTheme = true

    let player = RadioPlayer()

    private var context: VehlaDockWidgetContext?
    private var repository: HertzlyRepository?
    private let client = RadioBrowserClient()
    private var loadTask: Task<Void, Never>?
    private var fetchTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var isStarted = false
    private var hasLoaded = false
    private var requestGeneration = 0

    var selectedCountry: RadioCountry {
        RadioCountry.country(code: selectedCountryCode)
            ?? RadioCountry(code: selectedCountryCode, name: selectedCountryCode)
    }

    var currentStation: RadioStation? {
        if let playing = player.station,
           !stations.contains(where: { $0.id == playing.id }) {
            return playing
        }
        guard stations.indices.contains(currentStationIndex) else { return player.station }
        return stations[currentStationIndex]
    }

    var frequency: Double {
        TunerMapping.frequency(for: currentStationIndex, stationCount: stations.count)
    }

    var isCurrentFavorite: Bool {
        guard let currentStation else { return false }
        return favoriteStations.contains { $0.id == currentStation.id }
    }

    func configure(context: VehlaDockWidgetContext) {
        self.context = context
        tileTextColor = context.theme.tileTextColor
        popupTextColor = context.theme.primaryTextColor
        popupSecondaryTextColor = context.theme.secondaryTextColor
        isDarkTheme = context.theme.isDark
        if repository == nil {
            repository = HertzlyRepository(directory: context.dataDirectory)
        }
    }

    func updateTheme(_ theme: VehlaDockWidgetTheme) {
        tileTextColor = theme.tileTextColor
        popupTextColor = theme.primaryTextColor
        popupSecondaryTextColor = theme.secondaryTextColor
        isDarkTheme = theme.isDark
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        player.onNext = { [weak self] in self?.nextStation() }
        player.onPrevious = { [weak self] in self?.previousStation() }
        guard !hasLoaded, let repository else {
            if stations.isEmpty { fetchStations() }
            return
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let preferences = try await repository.loadPreferences()
                guard !Task.isCancelled else { return }
                selectedCountryCode = preferences.selectedCountryCode
                favoriteStations = preferences.favoriteStations
                player.setVolume(preferences.volume)
                hasLoaded = true

                if let cached = try await repository.loadStations(countryCode: selectedCountryCode),
                   !cached.isEmpty {
                    stations = cached
                    restoreStation(id: preferences.currentStationID)
                    isLoading = false
                }
                fetchStations(showLoading: stations.isEmpty)
            } catch {
                hasLoaded = true
                errorMessage = "Could not load saved radio settings."
                fetchStations()
            }
        }
    }

    func stop() {
        isStarted = false
        loadTask?.cancel()
        loadTask = nil
        fetchTask?.cancel()
        fetchTask = nil
        isLoading = false
        persist()
    }

    func close() {
        stop()
        persistTask?.cancel()
        player.shutdown()
    }

    func selectCountry(_ country: RadioCountry) {
        guard country.code != selectedCountryCode else { return }
        selectedCountryCode = country.code
        stations = []
        currentStationIndex = 0
        errorMessage = nil
        player.stop()
        feedback()
        persist()
        fetchStations()
    }

    func refresh() {
        fetchStations(showLoading: stations.isEmpty)
    }

    func selectStation(at index: Int, autoplay: Bool = true) {
        guard stations.indices.contains(index) else { return }
        currentStationIndex = index
        feedback()
        if autoplay { player.play(stations[index]) }
        persist()
    }

    func playFavorite(_ station: RadioStation) {
        if let index = stations.firstIndex(where: { $0.id == station.id }) {
            selectStation(at: index)
        } else {
            player.play(station)
            persist()
        }
    }

    func togglePlayback() {
        if player.station != nil {
            player.toggle()
        } else if let currentStation {
            player.play(currentStation)
        }
        feedback()
    }

    func nextStation() {
        guard !stations.isEmpty else { return }
        selectStation(at: (currentStationIndex + 1) % stations.count)
    }

    func previousStation() {
        guard !stations.isEmpty else { return }
        selectStation(at: currentStationIndex > 0 ? currentStationIndex - 1 : stations.count - 1)
    }

    func tune(to frequency: Double, autoplay: Bool) {
        guard !stations.isEmpty else { return }
        let index = TunerMapping.stationIndex(for: frequency, stationCount: stations.count)
        guard index != currentStationIndex else {
            if autoplay { player.play(stations[index]) }
            return
        }
        currentStationIndex = index
        feedback()
        if autoplay { player.play(stations[index]) }
        persist()
    }

    func toggleFavorite() {
        guard let station = currentStation else { return }
        if let index = favoriteStations.firstIndex(where: { $0.id == station.id }) {
            favoriteStations.remove(at: index)
        } else {
            favoriteStations.append(station)
        }
        feedback()
        persist()
    }

    func removeFavorite(_ station: RadioStation) {
        favoriteStations.removeAll { $0.id == station.id }
        persist()
    }

    func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        context?.open(url)
    }

    func showMessage(_ message: String) {
        context?.showMessage(message)
    }

    private func fetchStations(showLoading: Bool = true) {
        guard isStarted, let repository else { return }
        requestGeneration += 1
        let generation = requestGeneration
        let countryCode = selectedCountryCode
        fetchTask?.cancel()
        if showLoading { isLoading = true }
        errorMessage = nil

        fetchTask = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            do {
                let fetched = try await client.fetchStations(countryCode: countryCode)
                try Task.checkCancellation()
                guard generation == requestGeneration, countryCode == selectedCountryCode else { return }
                stations = fetched
                currentStationIndex = min(currentStationIndex, max(fetched.count - 1, 0))
                isLoading = false
                errorMessage = nil
                try? await repository.saveStations(fetched, countryCode: countryCode)
                persist()
            } catch is CancellationError {
                return
            } catch {
                guard generation == requestGeneration, countryCode == selectedCountryCode else { return }
                if stations.isEmpty,
                   let cached = try? await repository.loadStations(countryCode: countryCode),
                   !cached.isEmpty {
                    stations = cached
                    errorMessage = "Offline — showing saved stations."
                } else {
                    errorMessage = error.localizedDescription
                }
                isLoading = false
            }
        }
    }

    private func restoreStation(id: String?) {
        guard let id, let index = stations.firstIndex(where: { $0.id == id }) else {
            currentStationIndex = 0
            return
        }
        currentStationIndex = index
    }

    private func persist() {
        guard let repository else { return }
        let preferences = HertzlyPreferences(
            selectedCountryCode: selectedCountryCode,
            currentStationID: currentStation?.id,
            favoriteStations: favoriteStations,
            volume: 1
        )
        persistTask?.cancel()
        persistTask = Task {
            try? await repository.savePreferences(preferences)
        }
    }

    private func feedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
