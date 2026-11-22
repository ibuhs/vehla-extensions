import AppKit
import NotchKit
import SwiftUI
import VehlaNotchSDK
import WellbeingCore

@MainActor
final class WellbeingModel: ObservableObject {
    @Published private(set) var data = WellbeingData()
    @Published private(set) var breath: BreathState?
    @Published private(set) var breathRemaining: TimeInterval = 0
    /// When the running session began; the breathing view derives its animation from this, frame by frame.
    @Published private(set) var breathStartedAt: Date?
    @Published private(set) var status: String?

    private var notch: VehlaNotch?
    private var store: NKJSONStore<WellbeingData>?
    private var reminderTask: Task<Void, Never>?
    private var breathTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var nextReminder: Date?
    private var breathStart: Date?
    private var breathTotal: TimeInterval = 0

    var today: DayLog { data.day(for: Date()) }
    var isBreathing: Bool { breath != nil }
    var settings: WellbeingSettings { data.settings }
    var unit: VolumeUnit { settings.unit ?? .automatic() }

    // MARK: Lifecycle

    func start(_ notch: VehlaNotch) {
        self.notch = notch
        let store = NKJSONStore<WellbeingData>(directory: notch.dataDirectory, name: "wellbeing.json")
        self.store = store
        data = store.load() ?? WellbeingData()
        migrateGoalToLocalUnit()
        data.prune(now: Date())
        persist()
        scheduleReminder()
        reminderTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                self?.checkReminder()
            }
        }
    }

    func stop() {
        reminderTask?.cancel()
        statusTask?.cancel()
        if isBreathing { finishBreathing() }
        notch?.end("water")
        notch = nil
    }

    private func persist() { store?.save(data) }

    /// A goal still at the 2000 ml default reads as an odd "68 fl oz" in the US; make it a round 64.
    private func migrateGoalToLocalUnit() {
        guard data.settings.unit == nil, VolumeUnit.automatic() == .ounces, data.settings.waterGoalML == 2000 else { return }
        data.settings.waterGoalML = VolumeUnit.ounces.defaultGoalML
        data.settings.unit = .ounces
    }

    // MARK: Water

    /// `amount` is in the current display unit (fl oz or ml).
    func addWater(_ amount: Int) {
        data.addWater(unit.toML(amount), at: Date())
        persist()
        notch?.end("water")
        scheduleReminder()
        let total = today.waterML
        flash(total >= settings.waterGoalML ? "Goal reached" : "+\(amount) \(unit.label)")
    }

    func undoWater() {
        guard let ml = data.undoLastWater(on: Date()) else { return }
        persist()
        scheduleReminder()
        flash("Removed \(unit.format(ml: ml))")
    }

    /// The daily reset: clears today's water (mindfulness minutes are kept).
    func resetToday() {
        data.resetWater(on: Date())
        persist()
        notch?.end("water")
        scheduleReminder()
        flash("Today's water reset")
    }

    // MARK: Reminders

    private func scheduleReminder(notBefore: Date? = nil) {
        nextReminder = ReminderPlanner.next(now: Date(), data: data, notBefore: notBefore)
    }

    private func checkReminder() {
        guard let due = nextReminder, Date() >= due, !isBreathing else { return }
        let total = today.waterML
        notch?.show(VehlaNotchActivity(
            id: "water", systemImage: "drop.fill", title: "Time for water",
            detail: "\(unit.fromML(total)) of \(unit.format(ml: settings.waterGoalML)) today",
            progress: min(1, Double(total) / Double(max(1, settings.waterGoalML))), duration: 300,
            buttons: [
                VehlaNotchActivityButton(id: "logGlass", title: "Log \(unit.glass) \(unit.label)", systemImage: "drop.fill"),
                VehlaNotchActivityButton(id: "snooze", title: "Snooze 15 min", systemImage: "clock"),
            ]))
        scheduleReminder(notBefore: Date().addingTimeInterval(TimeInterval(max(15, settings.reminderMinutes) * 60)))
    }

    func activityAction(_ activityID: String, _ actionID: String) {
        switch (activityID, actionID) {
        case ("water", "logGlass"): addWater(unit.glass)
        case ("water", "snooze"):
            notch?.end("water")
            scheduleReminder(notBefore: Date().addingTimeInterval(15 * 60))
        case ("breathe", "stop"): finishBreathing()
        default: notch?.openTab("wellbeing")
        }
    }

    func update(_ change: (inout WellbeingSettings) -> Void) {
        change(&data.settings)
        persist()
        scheduleReminder()
    }

    // MARK: Breathing

    func startBreathing() {
        guard !isBreathing else { return }
        let pattern = data.pattern
        breathTotal = TimeInterval(max(1, settings.sessionMinutes) * 60)
        breathStart = Date()
        breathStartedAt = breathStart
        breath = pattern.state(at: 0)
        breathRemaining = breathTotal
        notch?.end("water")
        publishBreathActivity(pattern.state(at: 0))
        breathTask = Task { [weak self] in
            var last: (Int, Int)?
            while !Task.isCancelled {
                guard let self, let start = self.breathStart else { return }
                let elapsed = Date().timeIntervalSince(start)
                if elapsed >= self.breathTotal { self.finishBreathing(); return }
                let state = self.data.pattern.state(at: elapsed)
                self.breath = state
                self.breathRemaining = max(0, self.breathTotal - elapsed)
                if last?.0 != state.phaseIndex || last?.1 != state.cycle {
                    last = (state.phaseIndex, state.cycle)
                    self.publishBreathActivity(state)
                    // A light tap on the trackpad marks each new phase, so you can breathe with your eyes closed.
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopBreathing() { finishBreathing() }

    private func publishBreathActivity(_ state: BreathState) {
        guard let start = breathStart else { return }
        notch?.show(VehlaNotchActivity(
            id: "breathe", systemImage: "wind", title: state.phase.label, detail: nil,
            progress: min(1, Date().timeIntervalSince(start) / max(1, breathTotal)),
            timerEnd: start.addingTimeInterval(breathTotal), duration: breathTotal + 5,
            buttons: [VehlaNotchActivityButton(id: "stop", title: "End session", systemImage: "stop.fill")]))
    }

    private func finishBreathing() {
        breathTask?.cancel()
        guard let start = breathStart else { return }
        let seconds = Int(min(Date().timeIntervalSince(start), breathTotal))
        breathStart = nil
        breathStartedAt = nil
        breath = nil
        breathRemaining = 0
        if seconds >= 20 {
            data.addMindful(seconds: seconds, at: Date())
            persist()
            notch?.show(VehlaNotchActivity(
                id: "breathe", systemImage: "checkmark.circle.fill", title: "Session complete",
                detail: Self.minutes(seconds), duration: 4))
            flash("Logged \(Self.minutes(seconds))")
        } else {
            notch?.end("breathe")
        }
    }

    static func minutes(_ seconds: Int) -> String {
        seconds < 90 ? "\(seconds) sec" : "\(Int((Double(seconds) / 60).rounded())) min"
    }

    private func flash(_ message: String) {
        status = message
        statusTask?.cancel()
        statusTask = Task {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { self.status = nil }
        }
    }
}
