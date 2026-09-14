import AppKit
import SwiftUI
import VehlaDockWidgetSDK

struct HertzlyRootView: View {
    let surface: VehlaDockWidgetSurface
    @ObservedObject var model: HertzlyModel

    @ViewBuilder
    var body: some View {
        switch surface {
        case .compact:
            CompactRadioView(model: model)
        case .inline:
            InlineRadioView(model: model)
        case .popup:
            PopupRadioView(model: model)
        @unknown default:
            EmptyView()
        }
    }
}

private struct CompactRadioView: View {
    @ObservedObject var model: HertzlyModel
    @ObservedObject private var player: RadioPlayer

    init(model: HertzlyModel) {
        self.model = model
        player = model.player
    }

    var body: some View {
        Button(action: model.togglePlayback) {
            VStack(spacing: 4) {
                Image(systemName: playerIcon)
                    .font(.system(size: 20, weight: .semibold))
                Text(player.station?.name ?? model.currentStation?.name ?? "Hertzly")
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color(nsColor: model.tileTextColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(player.isPlaying ? "Pause radio" : "Play radio")
    }

    private var playerIcon: String {
        if player.isLoading { return "antenna.radiowaves.left.and.right" }
        return player.isPlaying ? "pause.fill" : "radio.fill"
    }
}

private struct InlineRadioView: View {
    @ObservedObject var model: HertzlyModel
    @ObservedObject private var player: RadioPlayer

    init(model: HertzlyModel) {
        self.model = model
        player = model.player
    }

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(player.station?.name ?? model.currentStation?.name ?? "Hertzly")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                Text(String(format: "%.1f FM", model.frequency))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .opacity(0.7)
            }
            Spacer(minLength: 2)
            control("backward.fill", action: model.previousStation)
            control(player.isPlaying ? "pause.fill" : "play.fill", action: model.togglePlayback)
            control("forward.fill", action: model.nextStation)
            control(model.isCurrentFavorite ? "heart.fill" : "heart", action: model.toggleFavorite)
        }
        .foregroundStyle(Color(nsColor: model.tileTextColor))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func control(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.plain)
    }
}

private struct PopupRadioView: View {
    @ObservedObject var model: HertzlyModel
    @ObservedObject private var player: RadioPlayer
    @State private var page: PopupPage?

    init(model: HertzlyModel) {
        self.model = model
        player = model.player
    }

    var body: some View {
        Group {
            switch page {
            case .countries:
                CountryPicker(model: model) { page = nil }
            case .stations:
                StationList(model: model) { page = nil }
            case .favorites:
                FavoritesList(model: model) { page = nil }
            case .settings:
                HertzlySettings(model: model) { page = nil }
            case nil:
                tuner
            }
        }
        .background(Color.clear)
    }

    private var tuner: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(popupColor.opacity(0.12))

            ScrollView {
                VStack(spacing: 14) {
                    frequencyDisplay
                    FrequencyDial(model: model)
                        .frame(height: 125)
                    DotMatrixVisualizer(isPlaying: player.isPlaying, color: popupColor)
                        .frame(height: 300)
                    if let error = model.errorMessage ?? player.errorMessage {
                        errorBanner(error)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }

            Divider().overlay(popupColor.opacity(0.12))
            bottomBar
        }
        .foregroundStyle(popupColor)
        .background(Color.clear)
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Liked Stations", systemImage: "heart.fill") { page = .favorites }
                Button("Settings", systemImage: "gearshape.fill") { page = .settings }
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.borderlessButton)

            Button { page = .countries } label: {
                HStack(spacing: 7) {
                    Text(model.selectedCountry.flag)
                    Text(model.selectedCountry.name).lineLimit(1)
                    Spacer()
                    Image(systemName: "magnifyingglass").opacity(0.55)
                }
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(popupColor.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: model.refresh) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(model.isLoading ? .degrees(360) : .zero)
                    .animation(
                        model.isLoading
                            ? .linear(duration: 1).repeatForever(autoreverses: false)
                            : .default,
                        value: model.isLoading
                    )
            }
            .buttonStyle(.plain)
            .disabled(model.isLoading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var frequencyDisplay: some View {
        HStack {
            roundControl("chevron.left", action: model.previousStation)
            Spacer()
            VStack(spacing: 2) {
                Text(String(format: "%.1f", model.frequency))
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text(player.station?.name ?? model.currentStation?.name ?? "No Station")
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                Text("FM")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            roundControl("chevron.right", action: model.nextStation)
        }
        .padding(.horizontal, 8)
    }

    private var bottomBar: some View {
        HStack {
            Button(action: model.toggleFavorite) {
                Label("Liked", systemImage: model.isCurrentFavorite ? "heart.fill" : "heart")
                    .foregroundStyle(model.isCurrentFavorite ? .red : popupColor.opacity(0.75))
            }
            .buttonStyle(.plain)
            .disabled(model.currentStation == nil)

            Spacer()

            Button { page = .stations } label: {
                Label("Stations", systemImage: "list.bullet")
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: model.togglePlayback) {
                ZStack {
                    Circle().fill(.white).frame(width: 44, height: 44)
                    if player.isLoading {
                        ProgressView().controlSize(.small).tint(.black)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .foregroundStyle(.black)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(model.currentStation == nil && player.station == nil)
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
    }

    private func roundControl(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Circle().stroke(popupColor.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(model.stations.isEmpty)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(message).font(.caption).lineLimit(2)
            Spacer()
        }
        .padding(10)
        .background(popupColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var popupColor: Color {
        Color(nsColor: model.popupTextColor)
    }
}

private enum PopupPage {
    case countries, stations, favorites, settings
}

private struct FrequencyDial: View {
    @ObservedObject var model: HertzlyModel
    @State private var displayedFrequency = 93.1
    @State private var dragStartFrequency: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FM")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            GeometryReader { geometry in
                ZStack {
                    Canvas { context, size in
                        let dialColor = Color(nsColor: model.popupTextColor)
                        let center = size.width / 2
                        for offset in -30...30 {
                            let value = displayedFrequency + Double(offset) * 0.1
                            let x = center + CGFloat(offset) * 12
                            let major = Int((value * 10).rounded()) % 10 == 0
                            let height: CGFloat = major ? 68 : 35
                            context.fill(
                                Path(CGRect(x: x, y: 30, width: major ? 1.5 : 0.7, height: height)),
                                with: .color(dialColor.opacity(major ? 0.55 : 0.2))
                            )
                            if major {
                                context.draw(
                                    Text(String(format: "%.0f", value))
                                        .font(.caption.bold())
                                        .foregroundStyle(dialColor),
                                    at: CGPoint(x: x, y: 10)
                                )
                            }
                        }
                    }
                    Rectangle().fill(.red).frame(width: 2.5, height: 94)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStartFrequency == nil {
                                dragStartFrequency = model.frequency
                            }
                            let delta = -Double(value.translation.width / max(geometry.size.width, 1)) * 20.5
                            displayedFrequency = min(max((dragStartFrequency ?? model.frequency) + delta, 87.5), 108)
                            model.tune(to: displayedFrequency, autoplay: false)
                        }
                        .onEnded { _ in
                            displayedFrequency = model.frequency
                            model.tune(to: displayedFrequency, autoplay: true)
                            dragStartFrequency = nil
                        }
                )
            }
        }
        .onAppear { displayedFrequency = model.frequency }
        .onChange(of: model.frequency) { _, value in displayedFrequency = value }
    }
}

private struct DotMatrixVisualizer: View {
    let isPlaying: Bool
    let color: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !isPlaying)) { timeline in
            Canvas { context, size in
                let columns = 32
                let rows = 24
                let phase = timeline.date.timeIntervalSinceReferenceDate
                for column in 0..<columns {
                    let wave = (sin(Double(column) * 0.52 + phase * 3.2) + 1) / 2
                    let level = isPlaying ? Int(3 + wave * Double(rows - 3)) : 0
                    for row in 0..<rows {
                        let spacingX = size.width / CGFloat(columns)
                        let spacingY = size.height / CGFloat(rows)
                        let rect = CGRect(
                            x: CGFloat(column) * spacingX + spacingX / 2 - 2,
                            y: size.height - CGFloat(row + 1) * spacingY + spacingY / 2 - 2,
                            width: 4,
                            height: 4
                        )
                        context.fill(
                            Circle().path(in: rect),
                            with: .color(color.opacity(row < level ? 0.75 : 0.06))
                        )
                    }
                }
            }
        }
    }
}

private struct CountryPicker: View {
    @ObservedObject var model: HertzlyModel
    let onDone: () -> Void
    @State private var searchText = ""

    private var countries: [RadioCountry] {
        guard !searchText.isEmpty else { return RadioCountry.all }
        return RadioCountry.all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if searchText.isEmpty {
                    Section("Popular") {
                        ForEach(RadioCountry.popular) { countryRow($0) }
                    }
                }
                Section(searchText.isEmpty ? "All Countries" : "Results") {
                    ForEach(countries) { countryRow($0) }
                }
            }
            .scrollContentBackground(.hidden)
            .searchable(text: $searchText, prompt: "Search countries")
            .navigationTitle("Select Country")
            .toolbar { Button("Done", action: onDone) }
        }
        .background(Color.clear)
    }

    private func countryRow(_ country: RadioCountry) -> some View {
        Button {
            model.selectCountry(country)
            onDone()
        } label: {
            HStack {
                Text(country.flag).font(.title2)
                Text(country.name)
                Spacer()
                if country.code == model.selectedCountryCode {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct StationList: View {
    @ObservedObject var model: HertzlyModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoading && model.stations.isEmpty {
                    ProgressView("Finding stations…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else if model.stations.isEmpty {
                    ContentUnavailableView(
                        "No Stations",
                        systemImage: "radio",
                        description: Text(model.errorMessage ?? "No stations are available.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List(Array(model.stations.enumerated()), id: \.element.id) { index, station in
                        StationRow(
                            station: station,
                            isPlaying: model.player.station?.id == station.id
                        ) {
                            model.selectStation(at: index)
                            onDone()
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("All Stations")
            .toolbar {
                Button("Refresh", action: model.refresh)
                Button("Done", action: onDone)
            }
        }
        .background(Color.clear)
    }
}

private struct FavoritesList: View {
    @ObservedObject var model: HertzlyModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if model.favoriteStations.isEmpty {
                    ContentUnavailableView(
                        "No Liked Stations",
                        systemImage: "heart",
                        description: Text("Like a station from the tuner to keep it here.")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                } else {
                    List(model.favoriteStations) { station in
                        StationRow(
                            station: station,
                            isPlaying: model.player.station?.id == station.id
                        ) {
                            model.playFavorite(station)
                            onDone()
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { model.removeFavorite(station) }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Liked Stations")
            .toolbar { Button("Done", action: onDone) }
        }
        .background(Color.clear)
    }
}

private struct StationRow: View {
    let station: RadioStation
    let isPlaying: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                AsyncImage(url: station.favicon.flatMap(URL.init(string:))) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Image(systemName: "radio").foregroundStyle(.secondary)
                }
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 7))

                VStack(alignment: .leading, spacing: 2) {
                    Text(station.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    HStack(spacing: 5) {
                        if station.bitrate > 0 { Text("\(station.bitrate) kbps") }
                        if let tag = station.tags.split(separator: ",").first, !tag.isEmpty { Text(String(tag)) }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                if isPlaying { Image(systemName: "waveform").foregroundStyle(.green) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 3)
    }
}

private struct HertzlySettings: View {
    @ObservedObject var model: HertzlyModel
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Support") {
                    settingsButton("Contact Support", icon: "envelope.fill") {
                        if let url = URL(string: "mailto:kailaconsulting@outlook.com") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    settingsButton("Radio Browser Website", icon: "network") {
                        model.open("https://www.radio-browser.info/")
                    }
                }
                Section("About") {
                    LabeledContent("Data Source", value: "Radio Browser")
                    LabeledContent("Runs in", value: "Vehla Dock Widgets")
                    LabeledContent("Version", value: "1.0.0")
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Hertzly Settings")
            .toolbar { Button("Done", action: onDone) }
        }
        .background(Color.clear)
    }

    private func settingsButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon) }
    }
}
