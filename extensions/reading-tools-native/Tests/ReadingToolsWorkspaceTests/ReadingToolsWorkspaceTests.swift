import XCTest
import VehlaNativeUISDK
@testable import ReadingToolsWorkspace

final class ReadingToolsWorkspaceTests: XCTestCase {
    private let sample = "The cat sat. Dogs run!"

    func testAnalysisCountsAndFormulaInputs() throws {
        XCTAssertEqual(
            try ReadingToolsEngine.analyze(sample),
            ReadingStats(words: 5, characters: 22, lines: 1, sentences: 2, syllables: 5)
        )

        let formulaStats = ReadingStats(
            words: 100,
            characters: 0,
            lines: 1,
            sentences: 5,
            syllables: 150
        )
        XCTAssertEqual(formulaStats.wordsPerSentence, 20, accuracy: 0.0001)
        XCTAssertEqual(formulaStats.syllablesPerWord, 1.5, accuracy: 0.0001)
        XCTAssertEqual(formulaStats.readingSeconds, 30, accuracy: 0.0001)
        XCTAssertEqual(formulaStats.fleschReadingEase, 59.635, accuracy: 0.0001)
        XCTAssertEqual(formulaStats.fleschKincaidGradeLevel, 9.91, accuracy: 0.0001)
    }

    func testEveryActionOutput() throws {
        XCTAssertEqual(
            try ReadingToolsEngine.output(for: .stats, text: sample),
            """
            Words: 5
            Characters: 22
            Lines: 1
            Sentences: 2
            Syllables (estimated): 5
            Estimated reading time: 1.5 sec
            """
        )
        XCTAssertEqual(
            try ReadingToolsEngine.output(for: .count, text: sample),
            """
            Words: 5
            Characters: 22
            """
        )
        XCTAssertEqual(
            try ReadingToolsEngine.output(for: .time, text: sample),
            """
            Words: 5
            At 200 WPM: 1.5 sec
            """
        )
        XCTAssertEqual(
            try ReadingToolsEngine.output(for: .readability, text: sample),
            """
            Flesch Reading Ease: 119.7
            Interpretation: Very easy
            """
        )
        XCTAssertEqual(
            try ReadingToolsEngine.output(for: .gradeLevel, text: sample),
            "Flesch-Kincaid grade level: 0.0"
        )
        XCTAssertEqual(
            try ReadingToolsEngine.output(for: .sentences, text: sample),
            """
            Sentences: 2
            Average words per sentence: 2.5
            """
        )
        XCTAssertEqual(
            try ReadingToolsEngine.output(for: .syllables, text: sample),
            "Estimated syllables: 5"
        )
        XCTAssertEqual(
            try ReadingToolsEngine.output(for: .largeType, text: sample),
            sample
        )
    }

    func testReadingTimePreservesSubMinutePrecision() throws {
        XCTAssertEqual(ReadingToolsEngine.formatReadingTime(seconds: 0.3), "0.3 sec")
        XCTAssertEqual(ReadingToolsEngine.formatReadingTime(seconds: 59.7), "59.7 sec")
        XCTAssertEqual(ReadingToolsEngine.formatReadingTime(seconds: 60), "1.0 min")
        XCTAssertEqual(ReadingToolsEngine.formatReadingTime(seconds: 90), "1.5 min")
    }

    func testReadabilityInterpretations() {
        XCTAssertEqual(ReadingToolsEngine.readabilityInterpretation(for: 95), "Very easy")
        XCTAssertEqual(ReadingToolsEngine.readabilityInterpretation(for: 85), "Easy")
        XCTAssertEqual(ReadingToolsEngine.readabilityInterpretation(for: 75), "Fairly easy")
        XCTAssertEqual(ReadingToolsEngine.readabilityInterpretation(for: 65), "Standard")
        XCTAssertEqual(ReadingToolsEngine.readabilityInterpretation(for: 55), "Fairly difficult")
        XCTAssertEqual(ReadingToolsEngine.readabilityInterpretation(for: 40), "Difficult")
        XCTAssertEqual(ReadingToolsEngine.readabilityInterpretation(for: 20), "Very difficult")
    }

    func testUnicodeWordsAndPunctuation() {
        XCTAssertEqual(
            ReadingToolsEngine.words(in: "Hello, 世界! l’été — 42."),
            ["Hello", "世界", "l’été", "42"]
        )
        XCTAssertEqual(
            ReadingToolsEngine.sentenceCount(in: "Hello?! Really… Yes。 最後"),
            4
        )
    }

    func testCRLFUnicodeSeparatorsAndBlankLines() throws {
        let text = "one\r\ntwo\rthree\u{0085}\u{2028}four\u{2029}"
        let stats = try ReadingToolsEngine.analyze(text)
        XCTAssertEqual(stats.words, 4)
        XCTAssertEqual(stats.lines, 6)
        XCTAssertEqual(stats.sentences, 1)
    }

    func testEstimatedSyllableHeuristic() {
        XCTAssertEqual(ReadingToolsEngine.estimatedSyllables(in: "make"), 1)
        XCTAssertEqual(ReadingToolsEngine.estimatedSyllables(in: "table"), 2)
        XCTAssertEqual(ReadingToolsEngine.estimatedSyllables(in: "rhythm"), 1)
        XCTAssertEqual(ReadingToolsEngine.estimatedSyllables(in: "queue"), 1)
        XCTAssertEqual(ReadingToolsEngine.estimatedSyllables(in: "東京"), 1)
        XCTAssertEqual(ReadingToolsEngine.estimatedSyllables(in: "123"), 1)
    }

    func testEmptySelectionAndNoWordErrors() {
        XCTAssertThrowsError(try ReadingToolsEngine.analyze(" \r\n\u{2028}\t")) {
            XCTAssertEqual($0 as? ReadingToolsError, .emptySelection)
        }
        XCTAssertThrowsError(
            try ReadingToolsEngine.output(for: .readability, text: "?!")
        ) {
            XCTAssertEqual($0 as? ReadingToolsError, .noWords)
        }
        XCTAssertNoThrow(
            try ReadingToolsEngine.output(for: .largeType, text: "")
        )
        XCTAssertEqual(
            try? ReadingToolsEngine.output(for: .largeType, text: ""),
            ""
        )
    }

    func testWorkerRunsCatalogActions() async throws {
        let output = try await ReadingToolsWorker.shared.perform(.count, selectedText: sample)
        XCTAssertEqual(output, "Words: 5\nCharacters: 22")
    }

    func testLargeTypeLaunchRoutingAndQueryFallback() {
        XCTAssertEqual(
            ReadingToolsWorkspaceContent.from(
                VehlaWorkspaceLaunchRequest(query: "normal palette query")
            ),
            .reference
        )
        XCTAssertEqual(
            ReadingToolsWorkspaceContent.from(
                VehlaWorkspaceLaunchRequest(
                    query: "fallback",
                    payload: [
                        "quickGlassActionID": ReadingToolsActionID.largeType.rawValue,
                        "selectedText": "Selected text",
                    ]
                )
            ),
            .largeType("Selected text")
        )
        XCTAssertEqual(
            ReadingToolsWorkspaceContent.from(
                VehlaWorkspaceLaunchRequest(
                    query: "Fallback text",
                    payload: [
                        "quickGlassActionID": ReadingToolsActionID.largeType.rawValue,
                        "selectedText": "",
                    ]
                )
            ),
            .largeType("Fallback text")
        )
        XCTAssertEqual(
            ReadingToolsWorkspaceContent.from(
                VehlaWorkspaceLaunchRequest(
                    payload: [
                        "quickGlassActionID": ReadingToolsActionID.largeType.rawValue,
                    ]
                )
            ),
            .largeType("")
        )
    }

    func testCatalogMatchesManifestAndExcludesSpeech() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestData = try Data(
            contentsOf: packageRoot.appendingPathComponent("extension.json")
        )
        let manifest = try XCTUnwrap(
            JSONSerialization.jsonObject(with: manifestData) as? [String: Any]
        )

        XCTAssertEqual(manifest["apiVersion"] as? Int, 2)
        XCTAssertEqual(manifest["id"] as? String, "com.ibuhs.vehla.reading-tools")
        XCTAssertEqual(manifest["version"] as? String, "1.0.1")
        XCTAssertEqual(manifest["runtime"] as? String, "nativeUI")
        XCTAssertEqual(
            manifest["capabilities"] as? [String],
            ["persistentStorage", "selectedText"]
        )

        let entries = try XCTUnwrap(
            manifest["quickGlassActions"] as? [[String: String]]
        )
        XCTAssertEqual(entries.count, ReadingToolsActionCatalog.all.count)
        for (entry, action) in zip(entries, ReadingToolsActionCatalog.all) {
            XCTAssertEqual(entry["id"], action.rawValue)
            XCTAssertEqual(entry["title"], action.title)
            XCTAssertEqual(entry["systemImage"], action.systemImage)
            XCTAssertEqual(
                entry["delivery"],
                action == .largeType ? "openPalette" : "compactResult"
            )
        }
        XCTAssertEqual(
            entries.first { $0["id"] == ReadingToolsActionID.largeType.rawValue }?["delivery"],
            "openPalette"
        )
        XCTAssertTrue(
            entries
                .filter { $0["id"] != ReadingToolsActionID.largeType.rawValue }
                .allSatisfy { $0["delivery"] == "compactResult" }
        )
        XCTAssertFalse(entries.contains {
            ($0["id"] ?? "").localizedCaseInsensitiveContains("speak")
                || ($0["title"] ?? "").localizedCaseInsensitiveContains("speak")
                || ($0["id"] ?? "").localizedCaseInsensitiveContains("speech")
        })

        let packageText = try String(
            contentsOf: packageRoot.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(packageText.contains("AVFoundation"))
        XCTAssertFalse(packageText.contains("AVSpeechSynthesizer"))
    }
}
