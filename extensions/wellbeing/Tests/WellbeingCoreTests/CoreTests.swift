import Foundation
import Testing
@testable import WellbeingCore

private var cal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

@Suite struct WaterTests {
    @Test func logsAndTotals() {
        var data = WellbeingData()
        let t = date(2026, 3, 10)
        data.addWater(250, at: t, calendar: cal)
        data.addWater(500, at: t.addingTimeInterval(3600), calendar: cal)
        data.addWater(-5, at: t, calendar: cal)
        #expect(data.day(for: t, calendar: cal).waterML == 750)
        #expect(data.lastDrink(on: t, calendar: cal) == t.addingTimeInterval(3600))
        #expect(data.undoLastWater(on: t, calendar: cal) == 500)
        #expect(data.day(for: t, calendar: cal).waterML == 250)
        #expect(data.undoLastWater(on: date(2026, 3, 11), calendar: cal) == nil)
    }

    @Test func streakCountsConsecutiveGoalDays() {
        var data = WellbeingData()
        data.settings.waterGoalML = 1000
        for day in 7...9 { data.addWater(1000, at: date(2026, 3, day), calendar: cal) }
        data.addWater(1000, at: date(2026, 3, 5), calendar: cal) // gap on the 6th
        // Today (10th) not yet met: streak runs to yesterday.
        #expect(data.streak(now: date(2026, 3, 10, 8), calendar: cal) == 3)
        data.addWater(1000, at: date(2026, 3, 10, 9), calendar: cal)
        #expect(data.streak(now: date(2026, 3, 10, 10), calendar: cal) == 4)
        #expect(data.streak(now: date(2026, 3, 20), calendar: cal) == 0)
    }

    @Test func weekIsSevenDaysOldestFirst() {
        var data = WellbeingData()
        data.addWater(300, at: date(2026, 3, 10), calendar: cal)
        let week = data.week(now: date(2026, 3, 10), calendar: cal)
        #expect(week.count == 7)
        #expect(week.last?.ml == 300)
        #expect(week.first!.date < week.last!.date)
    }

    @Test func mindfulAndPrune() {
        var data = WellbeingData()
        data.addMindful(seconds: 180, at: date(2026, 3, 10), calendar: cal)
        data.addMindful(seconds: 0, at: date(2026, 3, 10), calendar: cal)
        #expect(data.day(for: date(2026, 3, 10), calendar: cal).mindfulSeconds == 180)
        #expect(data.day(for: date(2026, 3, 10), calendar: cal).sessions == 1)
        data.addWater(100, at: date(2025, 1, 1), calendar: cal)
        data.prune(now: date(2026, 3, 10), keepDays: 120, calendar: cal)
        #expect(data.days.count == 1)
    }

    @Test func decodesOldOrPartialFiles() throws {
        let data = try JSONDecoder().decode(WellbeingData.self, from: Data(#"{"settings":{"waterGoalML":3000}}"#.utf8))
        #expect(data.settings.waterGoalML == 3000)
        #expect(data.settings.reminderMinutes == 90)
        #expect(data.days.isEmpty)
        let roundTrip = try JSONDecoder().decode(WellbeingData.self, from: JSONEncoder().encode(data))
        #expect(roundTrip == data)
    }
}

@Suite struct ReminderTests {
    @Test func quietHoursWrapMidnight() {
        let s = WellbeingSettings() // quiet 21 -> 9
        #expect(ReminderPlanner.isQuiet(date(2026, 3, 10, 22), settings: s, calendar: cal))
        #expect(ReminderPlanner.isQuiet(date(2026, 3, 10, 3), settings: s, calendar: cal))
        #expect(!ReminderPlanner.isQuiet(date(2026, 3, 10, 9), settings: s, calendar: cal))
        #expect(!ReminderPlanner.isQuiet(date(2026, 3, 10, 20), settings: s, calendar: cal))
    }

    @Test func waitsAnIntervalAfterTheLastDrink() {
        var data = WellbeingData()
        data.addWater(250, at: date(2026, 3, 10, 10), calendar: cal)
        let next = ReminderPlanner.next(now: date(2026, 3, 10, 10, 5), data: data, calendar: cal)
        #expect(next == date(2026, 3, 10, 11, 30))
    }

    @Test func nothingLoggedWaitsFromNow() {
        let next = ReminderPlanner.next(now: date(2026, 3, 10, 10), data: WellbeingData(), calendar: cal)
        #expect(next == date(2026, 3, 10, 11, 30))
    }

    @Test func skipsQuietHoursToMorning() {
        let next = ReminderPlanner.next(now: date(2026, 3, 10, 20, 30), data: WellbeingData(), calendar: cal)
        #expect(next == date(2026, 3, 11, 9))
    }

    @Test func goalMetSilencesTheRestOfTheDay() {
        var data = WellbeingData()
        data.settings.waterGoalML = 500
        data.addWater(500, at: date(2026, 3, 10, 10), calendar: cal)
        #expect(ReminderPlanner.next(now: date(2026, 3, 10, 11), data: data, calendar: cal) == date(2026, 3, 11, 9))
    }

    @Test func notBeforeDelaysAFiredReminder() {
        let now = date(2026, 3, 10, 12)
        let next = ReminderPlanner.next(now: now, data: WellbeingData(), notBefore: now.addingTimeInterval(15 * 60), calendar: cal)
        #expect(next == date(2026, 3, 10, 13, 30)) // the normal 90-minute wait is later than the snooze
        let snoozed = ReminderPlanner.next(now: now, data: WellbeingData(), notBefore: now.addingTimeInterval(7200), calendar: cal)
        #expect(snoozed == date(2026, 3, 10, 14))
    }

    @Test func disabledMeansNoReminder() {
        var data = WellbeingData()
        data.settings.remindersEnabled = false
        #expect(ReminderPlanner.next(now: date(2026, 3, 10, 10), data: data, calendar: cal) == nil)
    }
}

@Suite struct BreathTests {
    @Test func boxPhasesAndScale() {
        let p = BreathPattern.box
        #expect(p.cycleSeconds == 16)
        let start = p.state(at: 0)
        #expect(start.phase.kind == .inhale)
        #expect(abs(start.scale - 0.55) < 1e-9)
        let midInhale = p.state(at: 2)
        #expect(abs(midInhale.progress - 0.5) < 1e-9)
        #expect(abs(midInhale.scale - 0.775) < 1e-9)
        let fullHold = p.state(at: 5)
        #expect(fullHold.phase.kind == .hold)
        #expect(fullHold.scale == 1)
        let exhale = p.state(at: 10)
        #expect(exhale.phase.kind == .exhale)
        #expect(abs(exhale.scale - 0.775) < 1e-9)
        let emptyHold = p.state(at: 13)
        #expect(emptyHold.phase.kind == .hold)
        #expect(abs(emptyHold.scale - 0.55) < 1e-9)
    }

    @Test func cyclesAdvanceAndClamp() {
        let p = BreathPattern.relax
        #expect(p.state(at: 19).cycle == 1) // 4+7+8 = 19
        #expect(p.state(at: -3).phaseIndex == 0)
        #expect(BreathPattern.named("nope") == .box)
        #expect(BreathPattern.all.allSatisfy { $0.cycleSeconds > 0 })
    }
}

@Suite struct UnitTests {
    @Test func conversionsRoundTripForTypicalAmounts() {
        let oz = VolumeUnit.ounces
        #expect(oz.toML(8) == 237)
        #expect(oz.toML(16) == 473)
        #expect(oz.toML(32) == 946)
        for amount in [8, 16, 24, 32, 64, 96] { #expect(oz.fromML(oz.toML(amount)) == amount) }
        #expect(VolumeUnit.milliliters.toML(250) == 250)
        #expect(VolumeUnit.milliliters.fromML(250) == 250)
    }

    @Test func labelsAndQuickAmounts() {
        #expect(VolumeUnit.ounces.quickAmounts == [8, 16, 32])
        #expect(VolumeUnit.ounces.label == "fl oz")
        #expect(VolumeUnit.milliliters.quickAmounts == [150, 250, 500])
        #expect(VolumeUnit.ounces.format(ml: 473) == "16 fl oz")
        #expect(VolumeUnit.ounces.defaultGoalML == 1893)
        #expect(VolumeUnit.ounces.fromML(VolumeUnit.ounces.defaultGoalML) == 64)
    }

    @Test func regionPicksTheDefaultUnit() {
        #expect(VolumeUnit.automatic(locale: Locale(identifier: "en_US")) == .ounces)
        #expect(VolumeUnit.automatic(locale: Locale(identifier: "en_GB")) == .milliliters)
        #expect(VolumeUnit.automatic(locale: Locale(identifier: "de_DE")) == .milliliters)
    }

    @Test func unitSettingPersistsAndOldFilesStillLoad() throws {
        var data = WellbeingData()
        data.settings.unit = .ounces
        let back = try JSONDecoder().decode(WellbeingData.self, from: JSONEncoder().encode(data))
        #expect(back.settings.unit == .ounces)
        let old = try JSONDecoder().decode(WellbeingData.self, from: Data(#"{"settings":{"waterGoalML":2000}}"#.utf8))
        #expect(old.settings.unit == nil)
    }
}

@Suite struct BreathTrackTests {
    private func close(_ a: (x: Double, y: Double), _ b: (x: Double, y: Double), _ tol: Double = 1e-9) -> Bool {
        abs(a.x - b.x) < tol && abs(a.y - b.y) < tol
    }

    @Test func roundedSquareQuartersLandOnTheFourCornersClockwise() {
        let t = BreathTrack.roundedSquare, r = BreathTrack.cornerRadius, d = r * (1 - 2.0.squareRoot() / 2)
        // Mid-point of each corner arc: bottom-left (start), top-left, top-right, bottom-right.
        #expect(close(t.point(at: 0), (d, 1 - d)))
        #expect(close(t.point(at: 0.25), (d, d)))
        #expect(close(t.point(at: 0.5), (1 - d, d)))
        #expect(close(t.point(at: 0.75), (1 - d, 1 - d)))
    }

    @Test func goesUpTheLeftThenAcrossTheTop() {
        let t = BreathTrack.roundedSquare
        #expect(t.point(at: 0.05).y < t.point(at: 0).y)           // heading up first (the in-breath)
        #expect(t.point(at: 0.05).x < 0.2)                          // along the left side
        #expect(t.point(at: 0.375).y < 0.01 && t.point(at: 0.375).x > 0.4 && t.point(at: 0.375).x < 0.6)  // middle of the top
        #expect(t.point(at: 0.625).x > 0.99)                        // down the right side
        #expect(t.point(at: 0.875).y > 0.99)                        // back along the bottom
    }

    @Test func tracksAreClosedContinuousAndInsideTheUnitSquare() {
        for track in [BreathTrack.roundedSquare, .circle] {
            #expect(close(track.point(at: 0), track.point(at: 1), 1e-9))
            var last = track.point(at: 0)
            var longest = 0.0
            for i in 1...2000 {
                let p = track.point(at: Double(i) / 2000)
                longest = max(longest, hypot(p.x - last.x, p.y - last.y))
                #expect(p.x >= -1e-9 && p.x <= 1 + 1e-9 && p.y >= -1e-9 && p.y <= 1 + 1e-9)
                last = p
            }
            #expect(longest < 0.004)                                // no jumps anywhere along the loop
        }
    }

    @Test func circleStartsLeftAndHeadsUp() {
        let c = BreathTrack.circle
        #expect(close(c.point(at: 0), (0, 0.5)))
        #expect(close(c.point(at: 0.25), (0.5, 0)))
        #expect(close(c.point(at: 0.5), (1, 0.5)))
        #expect(BreathTrack.forPattern(.box) == .roundedSquare)
        #expect(BreathTrack.forPattern(.relax) == .circle)
    }

    @Test func samplesRunBetweenTwoPositions() {
        let pts = BreathTrack.roundedSquare.samples(from: 0.1, to: 0.3)
        #expect(pts.count > 20)
        #expect(close(pts.first!, BreathTrack.roundedSquare.point(at: 0.1)))
        #expect(close(pts.last!, BreathTrack.roundedSquare.point(at: 0.3)))
        #expect(BreathTrack.circle.samples(from: 0.5, to: 0.5).count == 1)
    }

    @Test func breathStateReportsCycleProgressAndCountdown() {
        let box = BreathPattern.box
        let s0 = box.state(at: 0)
        #expect(s0.cycleProgress == 0 && s0.phaseStart == 0 && abs(s0.secondsLeftInPhase - 4) < 1e-9)
        let hold = box.state(at: 6)              // 2 s into the first hold
        #expect(hold.phaseIndex == 1 && abs(hold.cycleProgress - 6.0 / 16) < 1e-9)
        #expect(abs(hold.phaseStart - 0.25) < 1e-9 && abs(hold.secondsLeftInPhase - 2) < 1e-9)
        // Every equal box phase starts on a quarter of the loop.
        for (i, start) in [0.0, 0.25, 0.5, 0.75].enumerated() { #expect(abs(box.state(at: Double(i) * 4 + 0.001).phaseStart - start) < 1e-9) }
        let relax = BreathPattern.relax.state(at: 5)   // 4 s inhale, 1 s into the 7 s hold
        #expect(abs(relax.phaseStart - 4.0 / 19) < 1e-9 && abs(relax.secondsLeftInPhase - 6) < 1e-9)
    }
}
