import NotchKit
import SwiftUI
import TodayCore

struct TodayTabView: View {
    @ObservedObject var model: TodayModel
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if showingSettings {
                SettingsView(model: model)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        accessPrompts
                        HStack(alignment: .top, spacing: 10) {
                            BriefCard(model: model)
                            WeatherCard(model: model, onSetCity: { showingSettings = true })
                        }
                        if model.eventAccess == .granted { schedule }
                        if model.reminderAccess == .granted, !model.reminders.isEmpty { reminders }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .nkTab()
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(showingSettings ? "Settings" : "Today").font(.system(size: 15, weight: .semibold))
            if !showingSettings {
                Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                    .font(NK.Font.caption).foregroundStyle(NK.Palette.secondary)
            }
            Spacer(minLength: 0)
            NKStatusLine(model.status).frame(maxWidth: 240, alignment: .trailing)
            NKIconButton(showingSettings ? "xmark" : "gearshape", help: showingSettings ? "Close settings" : "Settings") {
                showingSettings.toggle()
            }
        }
    }

    // MARK: Sections

    @ViewBuilder private var accessPrompts: some View {
        switch model.eventAccess {
        case .unknown:
            promptCard("calendar", "See your schedule here", "Vehla will ask macOS for Calendar access.",
                       button: "Allow Calendar") { model.requestCalendar() }
        case .denied:
            promptCard("calendar.badge.exclamationmark", "Calendar access is off",
                       "Turn on Calendar for Vehla in System Settings › Privacy & Security.",
                       button: "Open Settings") { model.openPrivacySettings() }
        case .granted: EmptyView()
        }
    }

    private func promptCard(_ icon: String, _ title: String, _ message: String, button: String,
                            action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 16)).foregroundStyle(NK.Palette.info)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(NK.Font.title)
                Text(message).font(NK.Font.caption).foregroundStyle(NK.Palette.secondary)
            }
            Spacer(minLength: 8)
            Button(button, action: action).buttonStyle(NKPillButtonStyle(.primary))
        }
        .nkCard(padding: 10)
    }

    private var schedule: some View {
        let now = Date()
        let allDay = model.events.filter(\.isAllDay)
        let timed = model.events.filter { !$0.isAllDay }
        return VStack(alignment: .leading, spacing: 0) {
            NKSectionHeader("Schedule").padding(.bottom, 2)
            ForEach(allDay) { EventRow(event: $0, now: now) }
            ForEach(timed) { EventRow(event: $0, now: now) }
            if model.events.isEmpty {
                Text("Nothing scheduled today.").font(NK.Font.caption).foregroundStyle(NK.Palette.tertiary).padding(.vertical, 6)
            }
        }
    }

    private var reminders: some View {
        VStack(alignment: .leading, spacing: 0) {
            NKSectionHeader("Reminders").padding(.bottom, 2)
            ForEach(model.reminders) { item in
                HStack(spacing: 10) {
                    Image(systemName: "circle").font(.system(size: 11)).foregroundStyle(NK.Palette.tertiary)
                    Text(item.title).font(NK.Font.body).lineLimit(1)
                    Spacer(minLength: 8)
                    if let due = item.due {
                        Text(due, style: due < Date() ? .relative : .time)
                            .font(NK.Font.caption).foregroundStyle(due < Date() ? NK.Palette.warning : NK.Palette.tertiary)
                    }
                }
                .padding(.vertical, 6)
                .overlay(alignment: .bottom) { Rectangle().fill(NK.Palette.stroke).frame(height: 1) }
            }
        }
    }
}

// MARK: - Cards

private struct BriefCard: View {
    @ObservedObject var model: TodayModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(model.brief.greeting.uppercased()).font(NK.Font.caption).tracking(0.6)
                    .foregroundStyle(NK.Palette.tertiary)
                if model.aiEnabled {
                    NKChip(chipText, tone: chipTone)
                }
                Spacer(minLength: 0)
                if model.aiEnabled {
                    NKIconButton("arrow.clockwise", help: "Write a fresh AI brief", size: 20) { model.regenerateAI() }
                        .disabled(model.aiState == .loading)
                }
            }
            Text(displayText)
                .font(.system(size: 13))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if case .failed(let message) = model.aiState {
                Text(message).font(NK.Font.caption).foregroundStyle(NK.Palette.warning).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nkCard(padding: 12, highlighted: true)
    }

    private var displayText: String {
        if model.aiEnabled, let ai = model.aiText { return ai }
        return model.brief.text.isEmpty ? "Allow Calendar and add your city to see your day at a glance." : model.brief.text
    }

    private var chipText: String {
        switch model.aiState {
        case .loading: return "Writing…"
        default: return model.aiText == nil ? "AI" : "AI · \(model.aiConfig.info.shortName)"
        }
    }

    private var chipTone: NKChip.Tone { model.aiState == .loading ? .neutral : .purple }
}

private struct WeatherCard: View {
    @ObservedObject var model: TodayModel
    let onSetCity: () -> Void

    var body: some View {
        Group {
            if let weather = model.weather {
                let condition = WeatherCondition.forCode(weather.code)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: condition.symbol).font(.system(size: 22)).symbolRenderingMode(.multicolor)
                        Text(Temperature.format(weather.temperatureC, fahrenheit: model.fahrenheit)).font(NK.Font.figure)
                    }
                    Text(condition.summary).font(NK.Font.label)
                    Text("H \(Temperature.format(weather.highC, fahrenheit: model.fahrenheit))  L \(Temperature.format(weather.lowC, fahrenheit: model.fahrenheit))")
                        .font(NK.Font.caption).foregroundStyle(NK.Palette.secondary)
                    if let place = model.prefs.place {
                        Text(place.name).font(NK.Font.caption).foregroundStyle(NK.Palette.tertiary).lineLimit(1)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "cloud.sun").font(.system(size: 20)).foregroundStyle(NK.Palette.tertiary)
                    Text(model.weatherError ?? "No weather yet").font(NK.Font.caption)
                        .foregroundStyle(NK.Palette.secondary).multilineTextAlignment(.center).lineLimit(2)
                    Button("Set city", action: onSetCity).buttonStyle(NKPillButtonStyle())
                }
            }
        }
        .frame(width: 150, alignment: .leading)
        .frame(minHeight: 86)
        .nkCard(padding: 10)
    }
}

private struct EventRow: View {
    let event: CalendarItem
    let now: Date

    var body: some View {
        let live = event.isInProgress(at: now)
        let past = !event.isAllDay && event.end <= now
        HStack(spacing: 10) {
            Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                .font(NK.Font.caption.monospacedDigit()).foregroundStyle(NK.Palette.secondary)
                .frame(width: 62, alignment: .leading)
            Capsule().fill(live ? NK.Palette.success : NK.Palette.info).frame(width: 3, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(NK.Font.title).lineLimit(1)
                if let location = event.location, event.joinURL == nil {
                    Text(location).font(NK.Font.caption).foregroundStyle(NK.Palette.secondary).lineLimit(1)
                } else if !event.isAllDay {
                    Text("\(event.start.formatted(date: .omitted, time: .shortened)) – \(event.end.formatted(date: .omitted, time: .shortened))")
                        .font(NK.Font.caption).foregroundStyle(NK.Palette.tertiary)
                }
            }
            Spacer(minLength: 8)
            if live { NKChip("Now", tone: .green) }
            if let url = event.joinURL, !past {
                Link(destination: url) {
                    Label("Join", systemImage: "video.fill")
                }
                .buttonStyle(NKPillButtonStyle(live ? .primary : .secondary))
            }
        }
        .padding(.vertical, 6)
        .opacity(past ? 0.45 : 1)
        .overlay(alignment: .bottom) { Rectangle().fill(NK.Palette.stroke).frame(height: 1) }
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @ObservedObject var model: TodayModel
    @State private var city = ""
    @State private var modelName = ""
    @State private var baseURL = ""

    private var config: AIConfig { model.aiConfig }

    private var aiCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NKSectionHeader("AI brief")
                Toggle("", isOn: Binding(get: { model.aiEnabled }, set: { model.setAI(enabled: $0) }))
                    .toggleStyle(.switch).labelsHidden().controlSize(.small)
            }
            Text("Off by default. When on, today's event titles and times, reminder titles and the weather are sent to \(AIBrief.destinationHost(config)) to write a short summary. Notes, attendees and locations are never sent. Without it you get the built-in on-device summary.")
                .font(NK.Font.caption).foregroundStyle(NK.Palette.secondary).fixedSize(horizontal: false, vertical: true)

            if model.aiEnabled {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(AIProvider.all) { provider in
                            Button {
                                model.setProvider(provider.id)
                                modelName = ""
                            } label: {
                                if provider.id == config.provider { Label(provider.name, systemImage: "checkmark") }
                                else { Text(provider.name) }
                            }
                        }
                    } label: { Text(config.info.name).font(NK.Font.label) }
                    .menuStyle(.button).buttonStyle(NKPillButtonStyle()).fixedSize()

                    modelMenu
                }
                if config.provider == .custom {
                    field("Base URL, e.g. https://openrouter.ai/api/v1 or http://localhost:11434/v1", text: $baseURL) {
                        model.setCustomBaseURL(baseURL)
                    }
                }
                if config.provider == .custom && model.modelOptions.isEmpty {
                    field("Model name, e.g. llama3.2", text: $modelName) { model.setModel(modelName) }
                }
                keyStatus
                if let note = model.modelsNote {
                    Text(note).font(NK.Font.caption).foregroundStyle(NK.Palette.tertiary)
                }
            }
        }
        .nkCard(padding: 10)
        .onAppear {
            modelName = model.prefs.models?[config.provider.rawValue] ?? ""
            baseURL = model.prefs.customBaseURL ?? ""
            if model.aiEnabled { model.loadModels() }
        }
    }

    private var modelMenu: some View {
        Menu {
            ForEach(model.modelOptions, id: \.self) { id in
                Button {
                    model.setModel(id)
                } label: {
                    let label = id == config.info.defaultModel ? "\(id)  (suggested)" : id
                    if id == config.effectiveModel { Label(label, systemImage: "checkmark") } else { Text(label) }
                }
            }
            if !model.modelOptions.isEmpty { Divider() }
            Button("Reload list") { model.loadModels() }
        } label: {
            HStack(spacing: 5) {
                if model.loadingModels { ProgressView().controlSize(.mini) }
                Text(config.effectiveModel.isEmpty ? "Choose a model" : config.effectiveModel)
                    .font(NK.Font.label).lineLimit(1)
            }
        }
        .menuStyle(.button).buttonStyle(NKPillButtonStyle()).fixedSize()
        .help("Model used for the AI brief")
    }

    @ViewBuilder private var keyStatus: some View {
        if !config.info.requiresKey {
            Label(model.hasAPIKey ? "Key found" : "No key needed for local models",
                  systemImage: model.hasAPIKey ? "checkmark.seal.fill" : "info.circle")
                .font(NK.Font.caption).foregroundStyle(model.hasAPIKey ? NK.Palette.success : NK.Palette.secondary)
        } else {
            Label(model.hasAPIKey ? "\(config.info.secretLabel) found"
                                  : "Add your \(config.info.secretLabel) under Vehla › Store settings",
                  systemImage: model.hasAPIKey ? "checkmark.seal.fill" : "key")
                .font(NK.Font.caption).foregroundStyle(model.hasAPIKey ? NK.Palette.success : NK.Palette.warning)
        }
    }

    private func field(_ placeholder: String, text: Binding<String>, onSubmit: @escaping () -> Void) -> some View {
        CommitField(placeholder: placeholder, text: text, commit: onSubmit)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    NKSectionHeader("Weather")
                    HStack(spacing: 8) {
                        TextField(model.prefs.place?.name ?? "City", text: $city)
                            .textFieldStyle(.plain).font(NK.Font.body)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Capsule().fill(NK.Palette.surfaceRaised))
                            .onSubmit { model.setPlace(named: city) }
                        Button(model.searchingPlace ? "Finding…" : "Set") { model.setPlace(named: city) }
                            .buttonStyle(NKPillButtonStyle(.primary)).disabled(model.searchingPlace || city.isEmpty)
                    }
                    Text("Forecasts from Open-Meteo. Only the city name and its coordinates are sent.")
                        .font(NK.Font.caption).foregroundStyle(NK.Palette.tertiary)
                }
                .nkCard(padding: 10)

                aiCard

                VStack(alignment: .leading, spacing: 6) {
                    NKSectionHeader("Reminders")
                    HStack {
                        Text(model.reminderAccess == .granted ? "Showing reminders due today"
                             : "Show reminders due today").font(NK.Font.body)
                        Spacer()
                        if model.reminderAccess != .granted {
                            Button("Allow") { model.requestReminders() }.buttonStyle(NKPillButtonStyle(.primary))
                        } else {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(NK.Palette.success)
                        }
                    }
                }
                .nkCard(padding: 10)
            }
        }
    }
}

/// A pill-shaped text field that saves by itself: shortly after you stop typing, on Return,
/// and when you leave the screen, so nothing is lost if you never press Return.
private struct CommitField: View {
    let placeholder: String
    @Binding var text: String
    let commit: () -> Void
    @State private var pending: Task<Void, Never>?

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain).font(NK.Font.body)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Capsule().fill(NK.Palette.surfaceRaised))
            .onSubmit(flush)
            .onChange(of: text) { _, _ in
                pending?.cancel()
                pending = Task {
                    try? await Task.sleep(for: .milliseconds(700))
                    if !Task.isCancelled { commit() }
                }
            }
            .onDisappear(perform: flush)
    }

    private func flush() {
        guard pending != nil else { return }
        pending?.cancel()
        pending = nil
        commit()
    }
}
