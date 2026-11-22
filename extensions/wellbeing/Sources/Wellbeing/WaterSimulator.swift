import Observation
import SwiftUI
import WellbeingCore

/// Owns the water physics and keeps the render loop honest: it only runs while the water is moving.
///
/// `isAtRest` is the one observed property. The view pauses its `TimelineView` when it is true, so a still
/// glass costs no CPU; anything that disturbs the water (adding a drink, the pointer sweeping across it)
/// wakes the loop again.
@MainActor
@Observable
final class WaterSimulator {
    private(set) var isAtRest = true

    @ObservationIgnored private(set) var physics = WaterPhysics(seed: UInt64(truncatingIfNeeded: Int(Date().timeIntervalSince1970 * 1000)))
    @ObservationIgnored private var lastFrame: Date?
    @ObservationIgnored private var previousRatio: Double?
    @ObservationIgnored private var lastPointer: (x: Double, time: Date)?

    /// Called whenever the day's total or the goal changes.
    func apply(total: Int, goal: Int, reduceMotion: Bool) {
        let ratio = Double(total) / Double(max(1, goal))
        defer { previousRatio = ratio }
        guard let previous = previousRatio, !reduceMotion else {
            physics.snap(level: min(1, ratio), overflowing: ratio > 1)
            if ratio >= 1 && ratio <= 1.0 + 1e-9 { physics.holdBrim() }
            wake()
            return
        }
        guard abs(ratio - previous) > 1e-9 else { return }
        if ratio > previous {
            physics.pour(strength: min(1, ratio - previous))
            physics.setLevel(min(1, ratio))
            if ratio > 1 {
                physics.startSpill(excess: ratio - max(previous, 1))
            } else if ratio >= 1 - 1e-9 {
                physics.holdBrim()
            }
        } else {
            physics.setLevel(min(1, ratio))
            if ratio <= 1 { physics.clearOverflow() }
        }
        wake()
    }

    /// Advances the physics to the frame time. Runs inside the Canvas renderer on every frame.
    func advance(to date: Date) {
        let dt = lastFrame.map { date.timeIntervalSince($0) } ?? (1.0 / 60)
        lastFrame = date
        physics.advance(dt: dt)
        if physics.isAtRest && !isAtRest {
            // Pause after this frame; mutating observed state during rendering isn't allowed.
            Task { @MainActor in
                self.isAtRest = true
                self.lastFrame = nil
            }
        }
    }

    /// The pointer moved over the glass at `x` (points, in the glass's own coordinates).
    func pointerMoved(x: Double, at time: Date) {
        defer { lastPointer = (x, time) }
        guard let last = lastPointer, time.timeIntervalSince(last.time) < 0.25 else { return }
        let dt = max(1.0 / 120, time.timeIntervalSince(last.time))
        let normalised = (x - (CupGeometry.cx - CupGeometry.topHalf)) / (2 * CupGeometry.topHalf)
        physics.slosh(x: min(1, max(0, normalised)), velocity: (x - last.x) / dt)
        if !physics.isAtRest { wake() }
    }

    func pointerLeft() { lastPointer = nil }

    private func wake() {
        lastFrame = nil
        isAtRest = false
    }
}
