import Foundation

enum ReadingToolsError: LocalizedError, Equatable {
    case emptySelection
    case noWords
    case unknownAction(String)

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Select some text first."
        case .noWords:
            return "The selection does not contain any words to analyze."
        case .unknownAction(let id):
            return "Unknown Reading Tools action “\(id)”."
        }
    }
}

struct ReadingStats: Equatable, Sendable {
    let words: Int
    let characters: Int
    let lines: Int
    let sentences: Int
    let syllables: Int

    var wordsPerSentence: Double {
        guard sentences > 0 else { return 0 }
        return Double(words) / Double(sentences)
    }

    var syllablesPerWord: Double {
        guard words > 0 else { return 0 }
        return Double(syllables) / Double(words)
    }

    var readingSeconds: Double {
        Double(words) / ReadingToolsEngine.readingWordsPerMinute * 60
    }

    var fleschReadingEase: Double {
        206.835 - (1.015 * wordsPerSentence) - (84.6 * syllablesPerWord)
    }

    var fleschKincaidGradeLevel: Double {
        max(0, (0.39 * wordsPerSentence) + (11.8 * syllablesPerWord) - 15.59)
    }
}

enum ReadingToolsEngine {
    static let readingWordsPerMinute = 200.0

    static func analyze(_ text: String) throws -> ReadingStats {
        try requireSelection(text)
        let words = words(in: text)
        return ReadingStats(
            words: words.count,
            characters: text.count,
            lines: lineCount(in: text),
            sentences: sentenceCount(in: text),
            syllables: words.reduce(0) { $0 + estimatedSyllables(in: $1) }
        )
    }

    static func output(for action: ReadingToolsActionID, text: String) throws -> String {
        let stats = try analyze(text)
        switch action {
        case .stats:
            return [
                "Words: \(stats.words)",
                "Characters: \(stats.characters)",
                "Lines: \(stats.lines)",
                "Sentences: \(stats.sentences)",
                "Syllables (estimated): \(stats.syllables)",
                "Estimated reading time: \(formatReadingTime(seconds: stats.readingSeconds))",
            ].joined(separator: "\n")
        case .time:
            return [
                "Words: \(stats.words)",
                "At 200 WPM: \(formatReadingTime(seconds: stats.readingSeconds))",
            ].joined(separator: "\n")
        case .readability:
            try requireWords(stats)
            return [
                "Flesch Reading Ease: \(oneDecimal(stats.fleschReadingEase))",
                "Interpretation: \(readabilityInterpretation(for: stats.fleschReadingEase))",
            ].joined(separator: "\n")
        case .gradeLevel:
            try requireWords(stats)
            return "Flesch-Kincaid grade level: \(oneDecimal(stats.fleschKincaidGradeLevel))"
        case .sentences:
            try requireWords(stats)
            return [
                "Sentences: \(stats.sentences)",
                "Average words per sentence: \(oneDecimal(stats.wordsPerSentence))",
            ].joined(separator: "\n")
        case .syllables:
            try requireWords(stats)
            return "Estimated syllables: \(stats.syllables)"
        }
    }

    static func words(in text: String) -> [String] {
        text.split { character in
            !character.isLetter
                && !character.isNumber
                && character != "'"
                && character != "’"
        }
        .map(String.init)
        .filter { token in token.contains { $0.isLetter || $0.isNumber } }
    }

    static func sentenceCount(in text: String) -> Int {
        var count = 0
        var hasContent = false
        var justEndedSentence = false

        for character in text {
            if character.isLetter || character.isNumber {
                hasContent = true
                justEndedSentence = false
            } else if sentenceTerminators.contains(character), hasContent, !justEndedSentence {
                count += 1
                hasContent = false
                justEndedSentence = true
            }
        }
        if hasContent { count += 1 }
        return count
    }

    static func lineCount(in text: String) -> Int {
        var count = 1
        var previousWasCarriageReturn = false
        for scalar in text.unicodeScalars {
            if scalar.value == 0x0A {
                if !previousWasCarriageReturn { count += 1 }
                previousWasCarriageReturn = false
            } else if lineSeparatorValues.contains(scalar.value) {
                count += 1
                previousWasCarriageReturn = scalar.value == 0x0D
            } else {
                previousWasCarriageReturn = false
            }
        }
        return count
    }

    /// Estimates English syllables by counting vowel groups, accounting for a
    /// common silent-e ending, preserving consonant-le endings, and returning
    /// at least one syllable for every word.
    static func estimatedSyllables(in word: String) -> Int {
        let folded = word
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: posixLocale)
            .lowercased()
        let letters = folded.unicodeScalars.compactMap { scalar -> Character? in
            guard (97...122).contains(scalar.value) else { return nil }
            return Character(String(scalar))
        }
        guard !letters.isEmpty else { return 1 }

        var groups = 0
        var previousWasVowel = false
        for letter in letters {
            let isVowel = vowels.contains(letter)
            if isVowel && !previousWasVowel { groups += 1 }
            previousWasVowel = isVowel
        }

        if groups > 1, letters.last == "e" {
            let keepsConsonantLE = letters.count >= 3
                && letters[letters.count - 2] == "l"
                && !vowels.contains(letters[letters.count - 3])
            if !keepsConsonantLE { groups -= 1 }
        }
        return max(1, groups)
    }

    static func readabilityInterpretation(for score: Double) -> String {
        switch score {
        case 90...: "Very easy"
        case 80..<90: "Easy"
        case 70..<80: "Fairly easy"
        case 60..<70: "Standard"
        case 50..<60: "Fairly difficult"
        case 30..<50: "Difficult"
        default: "Very difficult"
        }
    }

    static func formatReadingTime(seconds: Double) -> String {
        if seconds < 60 {
            return "\(oneDecimal(seconds)) sec"
        }
        return "\(oneDecimal(seconds / 60)) min"
    }

    private static func requireSelection(_ text: String) throws {
        let hasVisibleContent = text.unicodeScalars.contains {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        }
        guard hasVisibleContent else { throw ReadingToolsError.emptySelection }
    }

    private static func requireWords(_ stats: ReadingStats) throws {
        guard stats.words > 0 else { throw ReadingToolsError.noWords }
    }

    private static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", locale: posixLocale, value)
    }

    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
    private static let sentenceTerminators: Set<Character> = [
        ".", "!", "?", "…", "。", "！", "？", "｡",
    ]
    private static let lineSeparatorValues: Set<UInt32> = [0x0D, 0x85, 0x2028, 0x2029]
}
