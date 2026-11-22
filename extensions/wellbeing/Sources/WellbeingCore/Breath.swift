import Foundation

public struct BreathPhase: Equatable, Sendable {
    public enum Kind: Sendable { case inhale, hold, exhale }
    public let kind: Kind
    public let seconds: Double

    public var label: String {
        switch kind {
        case .inhale: return "Breathe in"
        case .hold: return "Hold"
        case .exhale: return "Breathe out"
        }
    }
}

public struct BreathState: Equatable, Sendable {
    public let phaseIndex: Int
    public let phase: BreathPhase
    /// 0...1 through the current phase.
    public let progress: Double
    /// 0.55 (empty) ... 1 (full), for the animated circle.
    public let scale: Double
    public let cycle: Int
    /// 0...1 around the whole cycle (the comet's position on the track).
    public let cycleProgress: Double
    /// Where the current phase began, as a fraction of the cycle.
    public let phaseStart: Double
    public let secondsLeftInPhase: Double
}

public struct BreathPattern: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let phases: [BreathPhase]

    public var cycleSeconds: Double { phases.reduce(0) { $0 + $1.seconds } }

    public static let box = BreathPattern(id: "box", name: "Box 4-4-4-4", phases: [
        .init(kind: .inhale, seconds: 4), .init(kind: .hold, seconds: 4),
        .init(kind: .exhale, seconds: 4), .init(kind: .hold, seconds: 4)])
    public static let relax = BreathPattern(id: "478", name: "Relax 4-7-8", phases: [
        .init(kind: .inhale, seconds: 4), .init(kind: .hold, seconds: 7), .init(kind: .exhale, seconds: 8)])
    public static let calm = BreathPattern(id: "calm", name: "Calm 4-6", phases: [
        .init(kind: .inhale, seconds: 4), .init(kind: .exhale, seconds: 6)])
    public static let all = [box, relax, calm]

    public static func named(_ id: String) -> BreathPattern { all.first { $0.id == id } ?? box }

    public static let emptyScale = 0.55

    /// Where the exercise is `elapsed` seconds in.
    public func state(at elapsed: TimeInterval) -> BreathState {
        let cycleLength = cycleSeconds
        let t = max(0, elapsed)
        let cycle = Int(t / cycleLength)
        var local = t - Double(cycle) * cycleLength
        var elapsedInCycle = 0.0
        for (index, phase) in phases.enumerated() {
            if local < phase.seconds || index == phases.count - 1 {
                let progress = min(1, local / phase.seconds)
                return BreathState(
                    phaseIndex: index, phase: phase, progress: progress,
                    scale: scale(for: index, progress: progress), cycle: cycle,
                    cycleProgress: min(1, (elapsedInCycle + progress * phase.seconds) / cycleLength),
                    phaseStart: elapsedInCycle / cycleLength,
                    secondsLeftInPhase: phase.seconds * (1 - progress))
            }
            local -= phase.seconds
            elapsedInCycle += phase.seconds
        }
        fatalError("unreachable: patterns always have phases")
    }

    private func scale(for index: Int, progress: Double) -> Double {
        let span = 1 - Self.emptyScale
        switch phases[index].kind {
        case .inhale: return Self.emptyScale + span * progress
        case .exhale: return 1 - span * progress
        case .hold:
            // A hold keeps the size it arrived at: full after an inhale, empty after an exhale.
            let previous = phases[(index - 1 + phases.count) % phases.count]
            return previous.kind == .exhale ? Self.emptyScale : (previous.kind == .inhale ? 1 : Self.emptyScale)
        }
    }
}
