import AppKit
import XCTest
@testable import VehlaNotchSDK

final class VehlaNotchSDKTests: XCTestCase {
    func testActivityInfoCarriesOnlyWhatWasSet() {
        let plain = VehlaNotchActivity(id: "a", systemImage: "bolt", title: "Title").info
        XCTAssertEqual(Set(plain.keys), ["id", "symbol", "title"])

        let end = Date(timeIntervalSince1970: 100)
        let full = VehlaNotchActivity(id: "a", systemImage: "bolt", title: "Title", detail: "Detail", tintHex: "#FF0000",
                                      progress: 4, timerEnd: end, duration: 5,
                                      buttons: [.init(id: "one", title: "One"), .init(id: "two", title: "Two", systemImage: "xmark"),
                                                .init(id: "three", title: "Three")]).info
        XCTAssertEqual(full["progress"] as? Double, 1)
        XCTAssertEqual(full["timerEnd"] as? Date, end)
        XCTAssertEqual(full["seconds"] as? Double, 5)
        let buttons = full["buttons"] as? [[String: String]]
        XCTAssertEqual(buttons?.count, 2)
        XCTAssertEqual(buttons?.last, ["id": "two", "title": "Two", "symbol": "xmark"])
    }

    func testProtocolsKeepTheirObjectiveCNames() {
        XCTAssertEqual(NSStringFromProtocol(VehlaNotchHost.self), "VehlaNotchHost")
        XCTAssertEqual(NSStringFromProtocol(VehlaNotchPlugin.self), "VehlaNotchPlugin")
        XCTAssertEqual(VehlaNotchAPIVersion, 4)
    }

    @MainActor func testWrapperForwardsToTheHost() {
        final class Host: NSObject, VehlaNotchHost {
            var packageID = "com.example.test"
            var dataDirectoryPath = "/tmp/x"
            var capabilities = ["openURL"]
            var shown: [[String: Any]] = [], ended: [String] = [], actions: [String] = []
            func themeInfo() -> [String: Any] { ["isDark": true] }
            func showActivity(_ info: [String: Any]) { shown.append(info) }
            func endActivity(_ activityID: String) { ended.append(activityID) }
            func openTab(_ tabID: String) { actions.append("tab:" + tabID) }
            func perform(_ action: String, info: [String: Any]) -> Bool { actions.append(action); return action != "nope" }
            func secret(named secretID: String) -> String? { secretID == "key" ? "value" : nil }
        }
        let host = Host()
        let notch = VehlaNotch(host)
        notch.show(.init(id: "a", systemImage: "bolt", title: "T"))
        notch.end("a")
        notch.openTab("main")
        XCTAssertTrue(notch.copy("text"))
        notch.log("hello")
        XCTAssertEqual(host.shown.count, 1)
        XCTAssertEqual(host.ended, ["a"])
        XCTAssertEqual(host.actions, ["tab:main", "copyText", "log"])
        XCTAssertTrue(notch.hasCapability("openURL") && !notch.hasCapability("networkAccess"))
        XCTAssertEqual(notch.secret(named: "key"), "value")
        XCTAssertEqual(notch.dataDirectory.path, "/tmp/x")
    }
}
