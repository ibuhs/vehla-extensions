import Foundation
import Testing
@testable import TodayCore

private let base = Date(timeIntervalSince1970: 1_760_000_000)
private func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }
private func event(_ start: Double, _ end: Double) -> CalendarItem {
    CalendarItem(id: "\(start)", title: "E", start: at(start), end: at(end))
}

@Suite struct RefreshPlanTests {
    private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    @Test func sleepsUntilSomethingHappens() {
        #expect(RefreshPlan.nextWake(now: at(0), events: [], calendar: utc) == at(15))
        #expect(RefreshPlan.nextWake(now: at(0), events: [event(18, 48)], calendar: utc) == at(8))    // ten minutes before
        #expect(RefreshPlan.nextWake(now: at(8), events: [event(18, 48)], calendar: utc) == at(18))   // it starts
        #expect(RefreshPlan.nextWake(now: at(40), events: [event(18, 48)], calendar: utc) == at(48))  // it ends
    }

    @Test func wakesAtMidnight() {
        let midnight = utc.date(byAdding: .day, value: 1, to: utc.startOfDay(for: base))!
        #expect(RefreshPlan.nextWake(now: midnight.addingTimeInterval(-300), events: [], calendar: utc) == midnight)
    }

    @Test func neverSpins() {
        let now = at(0)
        let soon = CalendarItem(id: "x", title: "x", start: now.addingTimeInterval(0.01), end: at(30))
        #expect(RefreshPlan.nextWake(now: now, events: [soon], calendar: utc) >= now.addingTimeInterval(1))
    }
}

@Suite struct AIRefreshPolicyTests {
    private func ask(force: Bool = false, visible: Bool = true, now: Date = at(0), attempt: Date? = nil,
                     success: Date? = nil, key: String = "a", last: String? = "a") -> Bool {
        AIRefreshPolicy.shouldRequest(force: force, visible: visible, now: now, lastAttempt: attempt,
                                      lastSuccess: success, key: key, lastKey: last)
    }

    @Test func theClockAloneIsNotNews() {
        let fmt: (Date) -> String = { "\($0.timeIntervalSince1970)" }
        let a = AIBrief.facts(now: at(0), events: [event(60, 90)], reminders: [], weather: nil, time: fmt)
        let b = AIBrief.facts(now: at(1), events: [event(60, 90)], reminders: [], weather: nil, time: fmt)
        #expect(a != b)   // the model is still told the time...
        let key = AIBrief.changeKey(events: [event(60, 90)], reminders: [], weather: nil, time: fmt)
        #expect(a.hasSuffix(key) && b.hasSuffix(key))   // ...but the key is the same
        #expect(key != AIBrief.changeKey(events: [event(61, 90)], reminders: [], weather: nil, time: fmt))
    }

    @Test func nothingIsSentWhileNobodyIsLooking() {
        #expect(!ask(visible: false, key: "b"))
        #expect(!ask(visible: false, success: at(-600)))
        #expect(ask(force: true, visible: false))
    }

    @Test func automaticRequestsAreSpacedOut() {
        #expect(!ask(now: at(9), attempt: at(0), success: at(0), key: "b"))
        #expect(ask(now: at(11), attempt: at(0), success: at(0), key: "b"))
        #expect(!ask(now: at(9), attempt: at(0), success: nil))          // a failure isn't retried at once
        #expect(ask(now: at(11), attempt: at(0), success: nil))
        #expect(ask(force: true, now: at(1), attempt: at(0), success: at(0)))
    }

    @Test func anUnchangedDayIsRewrittenHourly() {
        #expect(!ask(now: at(59), attempt: at(0), success: at(0)))
        #expect(ask(now: at(61), attempt: at(0), success: at(0)))
    }
}
