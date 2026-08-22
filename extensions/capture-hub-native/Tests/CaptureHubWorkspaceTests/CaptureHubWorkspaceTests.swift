import XCTest
import VehlaNativeUISDK
@testable import CaptureHubWorkspace

final class CaptureHubWorkspaceTests: XCTestCase {
    func testReminderDateParsingAndTitleCleaning() throws {
        let text = "Submit report January 15, 2030 at 3:00 PM"
        let phrase = "January 15, 2030 at 3:00 PM"
        let range = (text as NSString).range(of: phrase)
        let dueDate = Date(timeIntervalSince1970: 1_894_730_400)
        let draft = try CaptureHubEngine.reminderDraft(
            from: text,
            dateMatches: [
                CaptureHubDateMatch(range: range, date: dueDate, duration: 0),
            ]
        )

        XCTAssertEqual(draft.title, "Submit report")
        XCTAssertEqual(draft.dueDate, dueDate)
        let detected = try CaptureHubEngine.detectDates(in: text)
        XCTAssertFalse(detected.isEmpty)
        XCTAssertEqual(
            (text as NSString).substring(with: try XCTUnwrap(detected.first?.range)),
            phrase
        )
    }

    func testReminderWithoutDateKeepsTitle() throws {
        let draft = try CaptureHubEngine.reminderDraft(
            from: "Buy oat milk",
            dateMatches: []
        )
        XCTAssertEqual(draft, ReminderDraft(title: "Buy oat milk", dueDate: nil))
    }

    func testReminderLinesAreTrimmedOrderedAndLimited() throws {
        XCTAssertEqual(
            try CaptureHubEngine.reminderLines(from: " first \n\nsecond\n third "),
            ["first", "second", "third"]
        )
        let tooMany = (1...101).map(String.init).joined(separator: "\n")
        XCTAssertThrowsError(try CaptureHubEngine.reminderLines(from: tooMany)) { error in
            XCTAssertEqual(error as? CaptureHubError, .tooManyReminderLines(101))
        }
    }

    func testEventUsesExplicitDurationAndRemovesParsingText() throws {
        let text = "Project review June 1, 2030 at 9:00 AM for 90 minutes"
        let phrase = "June 1, 2030 at 9:00 AM"
        let start = Date(timeIntervalSince1970: 1_906_540_800)
        let draft = try CaptureHubEngine.eventDraft(
            from: text,
            dateMatches: [
                CaptureHubDateMatch(
                    range: (text as NSString).range(of: phrase),
                    date: start,
                    duration: 0
                ),
            ]
        )
        XCTAssertEqual(draft.title, "Project review")
        XCTAssertEqual(draft.startDate, start)
        XCTAssertEqual(draft.endDate.timeIntervalSince(start), 90 * 60)
        XCTAssertEqual(draft.notes, text)
    }

    func testEventUsesDetectedDurationThenSecondDate() throws {
        let text = "Workshop tomorrow until Friday"
        let tomorrow = (text as NSString).range(of: "tomorrow")
        let friday = (text as NSString).range(of: "Friday")
        let start = Date(timeIntervalSince1970: 2_000_000_000)
        let later = start.addingTimeInterval(3 * 3_600)

        let durationDraft = try CaptureHubEngine.eventDraft(
            from: text,
            dateMatches: [
                CaptureHubDateMatch(range: tomorrow, date: start, duration: 7_200),
            ]
        )
        XCTAssertEqual(durationDraft.endDate.timeIntervalSince(start), 7_200)

        let twoDateDraft = try CaptureHubEngine.eventDraft(
            from: text,
            dateMatches: [
                CaptureHubDateMatch(range: tomorrow, date: start, duration: 7_200),
                CaptureHubDateMatch(range: friday, date: later, duration: 0),
            ]
        )
        XCTAssertEqual(twoDateDraft.endDate, later)
        XCTAssertEqual(twoDateDraft.title, "Workshop until")
    }

    func testEventDefaultsToNextWholeHourAndOneHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(
            from: DateComponents(year: 2030, month: 1, day: 2, hour: 10, minute: 37)
        )!
        let draft = try CaptureHubEngine.eventDraft(
            from: "Focus block",
            now: now,
            calendar: calendar,
            dateMatches: []
        )
        XCTAssertEqual(calendar.component(.hour, from: draft.startDate), 11)
        XCTAssertEqual(calendar.component(.minute, from: draft.startDate), 0)
        XCTAssertEqual(draft.endDate.timeIntervalSince(draft.startDate), 3_600)
    }

    func testNoteTitleTruncationAndHTMLEscaping() throws {
        let longTitle = String(repeating: "a", count: 100)
        let title = try CaptureHubEngine.noteTitle(from: "\n\(longTitle)\nBody")
        XCTAssertEqual(title.count, 80)
        XCTAssertTrue(title.hasSuffix("…"))
        XCTAssertEqual(
            CaptureHubEngine.html(from: "<tag> & \"quote\"\nnext"),
            "&lt;tag&gt; &amp; &quot;quote&quot;<br>next"
        )
        XCTAssertEqual(
            CaptureHubEngine.appleScriptString(#"a\b"c"#),
            #"a\\b\"c"#
        )
    }

    func testEmptySelectionAndUnknownActionErrors() {
        XCTAssertThrowsError(
            try CaptureHubEngine.reminderLines(from: " \n ")
        ) { error in
            XCTAssertEqual(error as? CaptureHubError, .emptySelection)
        }
        XCTAssertEqual(
            CaptureHubError.unknownAction("missing").localizedDescription,
            "Unknown Capture Hub action “missing”."
        )
    }

    func testCatalogMatchesManifest() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: packageRoot.appendingPathComponent("extension.json"))
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(manifest["id"] as? String, "com.ibuhs.vehla.capture-hub")
        XCTAssertEqual(manifest["version"] as? String, "1.0.0")
        XCTAssertEqual(manifest["runtime"] as? String, "nativeUI")
        XCTAssertEqual(manifest["apiVersion"] as? Int, 2)
        XCTAssertEqual(
            manifest["capabilities"] as? [String],
            ["persistentStorage", "selectedText"]
        )

        let entries = try XCTUnwrap(
            manifest["quickGlassActions"] as? [[String: String]]
        )
        XCTAssertEqual(entries.count, CaptureHubActionCatalog.all.count)
        for (entry, action) in zip(entries, CaptureHubActionCatalog.all) {
            XCTAssertEqual(entry["id"], action.rawValue)
            XCTAssertEqual(entry["title"], action.title)
            XCTAssertEqual(entry["systemImage"], action.systemImage)
            XCTAssertEqual(entry["delivery"], "compactResult")
        }
    }
}
