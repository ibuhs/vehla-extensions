import NotchKit
import SwiftUI
import WellbeingCore

struct WellbeingTabView: View {
    @ObservedObject var model: WellbeingModel
    @State private var showingSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            header
            if showingSettings {
                SettingsView(model: model)
            } else {
                ScaleToFit {
                    HStack(spacing: 10) {
                        WaterCard(model: model)
                        MindfulCard(model: model)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .nkTab(horizontal: 14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(showingSettings ? "Settings" : "Wellbeing").font(.system(size: 15, weight: .semibold))
            if !showingSettings {
                let streak = model.data.streak(now: Date())
                if streak > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "flame.fill").font(.system(size: 10))
                        Text("\(streak) day\(streak == 1 ? "" : "s")").font(NK.Font.label)
                    }
                    .foregroundStyle(NK.Palette.secondary)
                }
            }
            Spacer(minLength: 0)
            NKStatusLine(model.status).frame(maxWidth: 220, alignment: .trailing)
            NKIconButton(showingSettings ? "xmark" : "gearshape", help: showingSettings ? "Close settings" : "Settings") {
                showingSettings.toggle()
            }
        }
        .padding(.horizontal, 12)
    }
}

// MARK: - Fit to the panel

private struct IdealSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        value = CGSize(width: max(value.width, next.width), height: max(value.height, next.height))
    }
}

/// Lays its content out at the size it needs, then scales it down uniformly if the Notch panel is smaller
/// (a smaller display, a shorter tab). Without this the content overflows and the edges are clipped.
private struct ScaleToFit<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var ideal: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let scale = fitScale(in: proxy.size)
            content
                .fixedSize()
                .background(GeometryReader { Color.clear.preference(key: IdealSizeKey.self, value: $0.size) })
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: ideal.width * scale, height: ideal.height * scale, alignment: .topLeading)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .onPreferenceChange(IdealSizeKey.self) { ideal = $0 }
    }

    private func fitScale(in size: CGSize) -> CGFloat {
        guard ideal.width > 0, ideal.height > 0 else { return 1 }
        return min(1, size.width / ideal.width, size.height / ideal.height)
    }
}

// MARK: - Water

private struct WaterCard: View {
    @ObservedObject var model: WellbeingModel
    @State private var simulator = WaterSimulator()
    @State private var customOpen = false
    @State private var customText = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let unit = model.unit
        let totalML = model.today.waterML
        let goalML = max(1, model.settings.waterGoalML)
        let percent = Double(totalML) / Double(goalML) * 100
        HStack(spacing: 10) {
            CupView(simulator: simulator)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Water today")
                .accessibilityValue("\(unit.fromML(totalML)) of \(unit.fromML(goalML)) \(unit.label)")

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    CountingText(value: Double(unit.fromML(totalML)))
                        .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    Text("of \(unit.fromML(goalML)) \(unit.label)").font(NK.Font.caption.monospacedDigit()).foregroundStyle(NK.Palette.tertiary)
                    CountingText(value: percent, suffix: "%")
                        .font(NK.Font.caption.monospacedDigit())
                        .foregroundStyle(totalML > goalML ? Color.waterPastel : NK.Palette.secondary)
                    Spacer(minLength: 0)
                    NKIconButton("arrow.uturn.backward", help: "Undo last drink", size: 20) { model.undoWater() }
                        .disabled(model.today.water.isEmpty)
                }
                .animation(.easeOut(duration: 0.7), value: totalML)
                controls(unit: unit)
                WeekBars(week: model.data.week(now: Date()), goal: goalML)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .nkCard(padding: 8)
        .onChange(of: totalML, initial: true) { _, _ in
            simulator.apply(total: totalML, goal: goalML, reduceMotion: reduceMotion)
        }
        .onChange(of: goalML) { _, _ in
            simulator.apply(total: totalML, goal: goalML, reduceMotion: reduceMotion)
        }
    }

    @ViewBuilder private func controls(unit: VolumeUnit) -> some View {
        if customOpen {
            HStack(spacing: 6) {
                TextField(unit.label, text: $customText)
                    .textFieldStyle(.plain).font(NK.Font.label.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 56)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(NK.Palette.surfaceRaised))
                    .onSubmit(commitCustom)
                Button("Add", action: commitCustom).buttonStyle(NKPillButtonStyle(.light)).fixedSize()
                    .disabled(Int(customText.trimmingCharacters(in: .whitespaces)).map { $0 <= 0 } ?? true)
                NKIconButton("xmark", help: "Cancel", size: 22) { customOpen = false; customText = "" }
            }
        } else {
            HStack(spacing: 6) {
                ForEach(unit.quickAmounts, id: \.self) { amount in
                    Button("\(amount)") { model.addWater(amount) }
                        .buttonStyle(NKPillButtonStyle(amount == unit.glass ? .light : .secondary))
                        .fixedSize()
                        .help("Add \(amount) \(unit.label)")
                }
                NKIconButton("plus", help: "Add a custom amount", size: 22) { customOpen = true }
            }
        }
    }

    private func commitCustom() {
        guard let amount = Int(customText.trimmingCharacters(in: .whitespaces)), amount > 0 else { return }
        model.addWater(min(amount, 5000))
        customText = ""
        customOpen = false
    }
}

/// A number that counts up and down smoothly alongside the water level.
private struct CountingText: View, @preconcurrency Animatable {
    var value: Double
    var suffix = ""

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View { Text("\(Int(value.rounded()))\(suffix)") }
}

extension Color {
    /// Water only: a soft pastel blue. Everything else in the Notch stays white.
    fileprivate static let waterPastel = Color(red: 0.62, green: 0.82, blue: 0.99)
}

// MARK: - Cup

/// The glass. It draws only while the water is moving and pauses when still, so an idle glass uses no CPU.
/// Sweeping the pointer across it, or dragging, makes the water slosh.
private struct CupView: View {
    let simulator: WaterSimulator

    var body: some View {
        // The physics steps at 60 Hz, so drawing faster would only repeat frames.
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: simulator.isAtRest)) { timeline in
            Canvas { context, size in
                simulator.advance(to: timeline.date)
                var c = context
                CupRenderer.draw(&c, size: size, physics: simulator.physics)
            }
        }
        .frame(width: CupGeometry.width, height: CupGeometry.height)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): simulator.pointerMoved(x: point.x, at: Date())
            case .ended: simulator.pointerLeft()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { simulator.pointerMoved(x: $0.location.x, at: Date()) }
                .onEnded { _ in simulator.pointerLeft() }
        )
    }
}

private struct WeekBars: View {
    let week: [(date: Date, ml: Int)]
    let goal: Int

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(week.enumerated()), id: \.offset) { index, day in
                VStack(spacing: 2) {
                    Capsule()
                        .fill(day.ml >= goal ? Color.waterPastel : Color.waterPastel.opacity(0.32))
                        .frame(width: 14, height: max(3, 16 * min(1, Double(day.ml) / Double(goal))))
                    Text(day.date, format: .dateTime.weekday(.narrow))
                        .font(.system(size: 8, weight: index == week.count - 1 ? .bold : .regular))
                        .foregroundStyle(index == week.count - 1 ? NK.Palette.secondary : NK.Palette.tertiary)
                }
            }
        }
        .frame(height: 26, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Water over the last seven days")
    }
}

// MARK: - Mindfulness

private struct MindfulCard: View {
    @ObservedObject var model: WellbeingModel

    var body: some View {
        HStack(spacing: 10) {
            BreathingView(pattern: model.data.pattern, startedAt: model.breathStartedAt)
            Group {
                if let breath = model.breath { session(breath) } else { idle }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .nkCard(padding: 8)
    }

    private var idle: some View {
        VStack(alignment: .leading, spacing: 8) {
            NKSectionHeader("Mindful") {
                let minutes = model.today.mindfulSeconds / 60
                if minutes > 0 { NKChip("\(minutes) min today") }
            }
            HStack(spacing: 6) {
                Menu {
                    ForEach(BreathPattern.all) { pattern in
                        Button(pattern.name) { model.update { $0.patternID = pattern.id } }
                    }
                } label: { Text(model.data.pattern.name).font(NK.Font.label) }
                .menuStyle(.button).buttonStyle(NKPillButtonStyle()).fixedSize()

                Menu {
                    ForEach([1, 3, 5, 10], id: \.self) { m in
                        Button("\(m) min") { model.update { $0.sessionMinutes = m } }
                    }
                } label: { Text("\(model.settings.sessionMinutes) min").font(NK.Font.label) }
                .menuStyle(.button).buttonStyle(NKPillButtonStyle()).fixedSize()
            }
            Spacer(minLength: 0)
            Button { model.startBreathing() } label: {
                Label("Breathe", systemImage: "wind").frame(maxWidth: .infinity)
            }
            .buttonStyle(NKPillButtonStyle(.light))
        }
    }

    private func session(_ state: BreathState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NKSectionHeader("Cycle \(state.cycle + 1)")
            Text(state.phase.label).font(.system(size: 17, weight: .semibold, design: .rounded))
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.25), value: state.phaseIndex)
            Text(timeString(model.breathRemaining)).font(NK.Font.figure).foregroundStyle(NK.Palette.secondary)
            Spacer(minLength: 0)
            Button("End session") { model.stopBreathing() }.buttonStyle(NKPillButtonStyle()).fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeString(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// The breathing visual. While a session runs it redraws every frame from the clock, so the comet and orb move
/// smoothly; when idle it draws once and stops. Reduce Motion updates once a second instead of animating.
private struct BreathingView: View {
    let pattern: BreathPattern
    let startedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let startedAt {
                if reduceMotion {
                    TimelineView(.periodic(from: startedAt, by: 1)) { frame(startedAt, $0.date) }
                } else {
                    // 60 fps is plenty for slow movement; a 120 Hz display would double the work.
                    TimelineView(.animation(minimumInterval: 1.0 / 60)) { frame(startedAt, $0.date) }
                }
            } else {
                Canvas { context, size in
                    var c = context
                    BreathRenderer.draw(&c, size: size, pattern: pattern, state: nil, time: 0)
                }
            }
        }
        .frame(width: BreathRenderer.size.width, height: BreathRenderer.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(startedAt == nil ? "Breathing guide" : "Breathing guide, in progress")
    }

    private func frame(_ start: Date, _ now: Date) -> some View {
        let elapsed = max(0, now.timeIntervalSince(start))
        let state = pattern.state(at: elapsed)
        return ZStack {
            Canvas { context, size in
                var c = context
                BreathRenderer.draw(&c, size: size, pattern: pattern, state: state, time: reduceMotion ? 0 : elapsed)
            }
            // The seconds left in this phase, counting down inside the orb.
            Text("\(max(1, Int(state.secondsLeftInPhase.rounded(.up))))")
                .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 2)
        }
    }
}

// MARK: - Settings

private struct SettingsView: View {
    @ObservedObject var model: WellbeingModel
    @State private var confirmingReset = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Text("Water units").font(NK.Font.body)
                    Spacer()
                    ForEach(VolumeUnit.allCases, id: \.self) { unit in
                        Button(unit.label) { model.update { $0.unit = unit } }
                            .buttonStyle(NKPillButtonStyle(unit == model.unit ? .light : .secondary))
                    }
                }
                .nkCard(padding: 6)
                row("Daily water goal", model.unit.format(ml: model.settings.waterGoalML),
                    minus: { stepGoal(-1) }, plus: { stepGoal(1) })
                HStack {
                    Text("Today's water").font(NK.Font.body)
                    Spacer()
                    Button(confirmingReset ? "Tap again to reset" : "Reset today") {
                        if confirmingReset { model.resetToday(); confirmingReset = false }
                        else {
                            confirmingReset = true
                            Task { try? await Task.sleep(for: .seconds(4)); confirmingReset = false }
                        }
                    }
                    .buttonStyle(NKPillButtonStyle(confirmingReset ? .destructive : .secondary))
                    .disabled(model.today.water.isEmpty)
                }
                .nkCard(padding: 6)
                HStack {
                    Text("Reminders").font(NK.Font.body)
                    Spacer()
                    Toggle("", isOn: Binding(get: { model.settings.remindersEnabled },
                                             set: { on in model.update { $0.remindersEnabled = on } }))
                        .toggleStyle(.switch).labelsHidden().controlSize(.small).tint(.white)
                }
                .nkCard(padding: 8)
                if model.settings.remindersEnabled {
                    row("Remind every", "\(model.settings.reminderMinutes) min",
                        minus: { model.update { $0.reminderMinutes = max(15, $0.reminderMinutes - 15) } },
                        plus: { model.update { $0.reminderMinutes = min(240, $0.reminderMinutes + 15) } })
                    row("Quiet from", hour(model.settings.quietStartHour),
                        minus: { model.update { $0.quietStartHour = ($0.quietStartHour + 23) % 24 } },
                        plus: { model.update { $0.quietStartHour = ($0.quietStartHour + 1) % 24 } })
                    row("Quiet until", hour(model.settings.quietEndHour),
                        minus: { model.update { $0.quietEndHour = ($0.quietEndHour + 23) % 24 } },
                        plus: { model.update { $0.quietEndHour = ($0.quietEndHour + 1) % 24 } })
                }
            }
        }
    }

    /// Steps the goal by one increment in the current unit (8 fl oz or 250 ml), staying within a sane range.
    private func stepGoal(_ direction: Int) {
        let unit = model.unit
        model.update {
            let current = unit.fromML($0.waterGoalML)
            let stepped = min(unit.fromML(6000), max(unit.fromML(500), current + direction * unit.goalStep))
            $0.waterGoalML = unit.toML(stepped)
        }
    }

    private func hour(_ h: Int) -> String { String(format: "%02d:00", h) }

    private func row(_ title: String, _ value: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).font(NK.Font.body)
            Spacer()
            NKIconButton("minus", help: "Decrease \(title)", size: 22, action: minus)
            Text(value).font(NK.Font.label.monospacedDigit()).frame(minWidth: 64)
            NKIconButton("plus", help: "Increase \(title)", size: 22, action: plus)
        }
        .nkCard(padding: 6)
    }
}
