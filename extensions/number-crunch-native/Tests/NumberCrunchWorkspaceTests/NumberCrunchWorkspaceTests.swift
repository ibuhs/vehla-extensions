import XCTest
import VehlaNativeUISDK
@testable import NumberCrunchWorkspace

final class NumberCrunchWorkspaceTests: XCTestCase {
    func testSumsAndAveragesNumbers() throws {
        XCTAssertEqual(try NumberCrunchEngine.sum("Tea 2, milk 3.5, chocolate 10"), "15.5")
        XCTAssertEqual(try NumberCrunchEngine.average("2\n4\n6"), "4")
        XCTAssertEqual(try NumberCrunchEngine.sum("1,234 and 6"), "1240")
    }

    func testEvaluatesExpressions() throws {
        XCTAssertEqual(try NumberCrunchEngine.evaluate("2 + 3 * 4"), "2 + 3 * 4 = 14")
        XCTAssertEqual(try NumberCrunchEngine.evaluate("(2 + 3) * 4"), "(2 + 3) * 4 = 20")
        XCTAssertEqual(try NumberCrunchEngine.evaluate("2^3"), "2^3 = 8")
        XCTAssertEqual(try NumberCrunchEngine.evaluate("$1,200 / 4"), "$1,200 / 4 = 300")
    }

    func testConvertsToMetric() throws {
        let output = try NumberCrunchEngine.convert(
            "Walk 5 miles with a 10 lb bag at 70°F.",
            to: .metric
        )
        XCTAssertTrue(output.contains("8.0467 km"))
        XCTAssertTrue(output.contains("4.5359 kg"))
        XCTAssertTrue(output.contains("21.1111 °C"))
    }

    func testConvertsToImperial() throws {
        let output = try NumberCrunchEngine.convert(
            "Drive 10 km with 2 kg at 0°C.",
            to: .imperial
        )
        XCTAssertTrue(output.contains("6.2137 mi"))
        XCTAssertTrue(output.contains("4.4092 lb"))
        XCTAssertTrue(output.contains("32 °F"))
    }

    func testHumanizesAndExpandsFileSizes() throws {
        XCTAssertEqual(try NumberCrunchEngine.humanizeSizes("2048 bytes"), "2 KiB")
        XCTAssertEqual(try NumberCrunchEngine.humanizeSizes("2048"), "2 KiB")
        XCTAssertEqual(try NumberCrunchEngine.toBytes("2 KiB"), "2048 B")
        XCTAssertEqual(try NumberCrunchEngine.toBytes("1.5 MB"), "1500000 B")
        XCTAssertEqual(try NumberCrunchEngine.toBytes("16 bits"), "2 B")
        XCTAssertTrue(
            try NumberCrunchEngine.humanizeSizes("The cache is 1.5 MB.")
                .contains("1.4305 MiB")
        )
        XCTAssertEqual(try NumberCrunchEngine.toKilobytes("2048 bytes"), "2.048 KB")
        XCTAssertEqual(try NumberCrunchEngine.toMegabytes("1500 KB"), "1.5 MB")
        XCTAssertEqual(try NumberCrunchEngine.toGigabytes("2048 MB"), "2.048 GB")
        XCTAssertEqual(try NumberCrunchEngine.toKilobytes("1.5 MB"), "1500 KB")
    }

    func testLeavesOppositeUnitsAlone() throws {
        XCTAssertEqual(
            try NumberCrunchEngine.convert("10 kg and 5 miles", to: .metric),
            "10 kg and 8.0467 km"
        )
    }

    func testWorkerRunsCatalogActions() async throws {
        let sum = try await NumberCrunchWorker.shared.perform(
            .sum,
            selectedText: "1 2 3"
        )
        XCTAssertEqual(sum, "6")
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
        XCTAssertEqual(manifest["id"] as? String, "com.ibuhs.vehla.number-crunch")
        XCTAssertEqual(manifest["runtime"] as? String, "nativeUI")
        let capabilities = try XCTUnwrap(manifest["capabilities"] as? [String])
        XCTAssertTrue(capabilities.contains("selectedText"))
        XCTAssertTrue(capabilities.contains("persistentStorage"))
        XCTAssertFalse(capabilities.contains("networkAccess"))

        let entries = try XCTUnwrap(
            manifest["quickGlassActions"] as? [[String: String]]
        )
        XCTAssertEqual(entries.count, NumberCrunchActionCatalog.all.count)
        for (entry, action) in zip(entries, NumberCrunchActionCatalog.all) {
            XCTAssertEqual(entry["id"], action.rawValue)
            XCTAssertEqual(entry["title"], action.title)
            XCTAssertEqual(entry["systemImage"], action.systemImage)
            XCTAssertEqual(
                entry["delivery"],
                action.delivery == .replaceSelection ? "replaceSelection" : "compactResult"
            )
        }
    }
}
