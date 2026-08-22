import Foundation
import VehlaNativeUISDK

enum ReadingToolsActionID: String, CaseIterable, Sendable {
    case stats = "read.stats"
    case time = "read.time"
    case readability = "read.readability"
    case gradeLevel = "read.grade-level"
    case sentences = "read.sentences"
    case syllables = "read.syllables"

    var title: String {
        switch self {
        case .stats: "Reading Stats"
        case .time: "Reading Time"
        case .readability: "Readability Score"
        case .gradeLevel: "Grade Level"
        case .sentences: "Sentence Analysis"
        case .syllables: "Syllable Count"
        }
    }

    var systemImage: String {
        switch self {
        case .stats: "doc.text.magnifyingglass"
        case .time: "clock"
        case .readability: "gauge.with.needle"
        case .gradeLevel: "graduationcap"
        case .sentences: "text.quote"
        case .syllables: "waveform"
        }
    }

    var caption: String {
        switch self {
        case .stats: "Counts text and summarizes estimated reading time."
        case .time: "Estimates reading time at 200 words per minute."
        case .readability: "Calculates Flesch Reading Ease with an interpretation."
        case .gradeLevel: "Estimates a Flesch-Kincaid US grade level."
        case .sentences: "Counts sentences and averages their word count."
        case .syllables: "Estimates English syllables with a local heuristic."
        }
    }

    var delivery: VehlaWorkspaceQuickGlassDelivery { .compactResult }

    var descriptor: VehlaWorkspaceQuickGlassActionDescriptor {
        VehlaWorkspaceQuickGlassActionDescriptor(
            id: rawValue,
            title: title,
            systemImage: systemImage,
            delivery: delivery
        )
    }
}

enum ReadingToolsActionCatalog {
    static let all: [ReadingToolsActionID] = ReadingToolsActionID.allCases

    static func action(id: String) -> ReadingToolsActionID? {
        ReadingToolsActionID(rawValue: id)
    }
}
