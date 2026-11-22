import Foundation
import Testing
@testable import WellbeingCore

private func run(_ p: inout WaterPhysics, seconds: Double, dt: Double = 1.0 / 60) {
    var t = 0.0
    while t < seconds { p.advance(dt: dt); t += dt }
}

@Suite struct WaterPhysicsTests {
    @Test func startsAtRestWithOneHundredNodes() {
        let p = WaterPhysics(seed: 1)
        #expect(WaterPhysics.nodeCount == 100)
        #expect(p.heights.count == 100 && p.velocities.count == 100)
        #expect(p.isAtRest)
        #expect(p.kineticEnergy == 0)
    }

    @Test func fillEasesOutOverSevenHundredMilliseconds() {
        var p = WaterPhysics(seed: 1)
        p.snap(level: 0.2, overflowing: false)
        p.setLevel(0.8)
        #expect(!p.isAtRest)
        run(&p, seconds: 0.35)
        // Ease-out: well past the halfway point at half the time.
        #expect(p.level > 0.5 + 0.2 && p.level < 0.8)
        var last = p.level
        for _ in 0..<60 { p.advance(dt: 1.0 / 60); #expect(p.level >= last - 1e-9); last = p.level }
        #expect(abs(p.level - 0.8) < 1e-9)
    }

    @Test func rippleTravelsOutwardFromACentralImpulse() {
        var p = WaterPhysics(seed: 1)
        p.snap(level: 0.6, overflowing: false)
        p.pour(strength: 0.2)
        p.setLevel(0.6)
        run(&p, seconds: 0.15)
        #expect(p.heights[50] != 0)
        #expect(p.heights[30] != 0 || p.velocities[30] != 0)   // momentum has spread sideways
        run(&p, seconds: 0.3)
        let edgeMotion = abs(p.heights[3]) + abs(p.velocities[3]) + abs(p.heights[96]) + abs(p.velocities[96])
        #expect(edgeMotion > 0)                                // and reached the walls
    }

    @Test func wavesDecayAndTheSimulationComesToRest() {
        var p = WaterPhysics(seed: 1)
        p.snap(level: 0.7, overflowing: false)
        p.slosh(x: 0.2, velocity: 300)
        #expect(!p.isAtRest)
        #expect(p.kineticEnergy > 0.01)
        var rested = false
        var t = 0.0
        while t < 12 && !rested { p.advance(dt: 1.0 / 60); t += 1.0 / 60; rested = p.isAtRest }
        #expect(rested)
        #expect(p.heights.allSatisfy { $0 == 0 })
        #expect(p.kineticEnergy == 0)
    }

    @Test func advancingWhileAtRestDoesNothing() {
        var p = WaterPhysics(seed: 1)
        p.snap(level: 0.5, overflowing: false)
        let before = p.clock
        run(&p, seconds: 2)
        #expect(p.clock == before)
        #expect(p.isAtRest)
    }

    @Test func sloshIsDirectionalAndIgnoresEmptyGlass() {
        var empty = WaterPhysics(seed: 1)
        empty.slosh(x: 0.5, velocity: 400)
        #expect(empty.isAtRest)

        var p = WaterPhysics(seed: 1)
        p.snap(level: 0.8, overflowing: false)
        p.slosh(x: 0.5, velocity: 300)
        let right = p.velocities[60], left = p.velocities[40]
        #expect(right * left < 0)                       // a dipole: one side up, the other down
        var q = WaterPhysics(seed: 1)
        q.snap(level: 0.8, overflowing: false)
        q.slosh(x: 0.5, velocity: -300)
        #expect(q.velocities[60] * right < 0)           // reversing the sweep reverses it
    }

    @Test func frameRateDoesNotChangeTheResult() {
        var a = WaterPhysics(seed: 3), b = WaterPhysics(seed: 3)
        for p in [0, 1] {
            _ = p
        }
        a.snap(level: 0.6, overflowing: false); b.snap(level: 0.6, overflowing: false)
        a.slosh(x: 0.3, velocity: 200); b.slosh(x: 0.3, velocity: 200)
        run(&a, seconds: 1, dt: 1.0 / 60)
        run(&b, seconds: 1, dt: 1.0 / 120)
        for i in stride(from: 0, to: 100, by: 11) { #expect(abs(a.heights[i] - b.heights[i]) < 1e-6) }
    }

    @Test func pouringSpawnsTwentyToThirtyBubblesThatPopAtTheSurface() {
        var p = WaterPhysics(seed: 5)
        p.snap(level: 0.5, overflowing: false)
        p.pour(strength: 0.1)
        p.setLevel(0.6)
        #expect((20...30).contains(p.bubbles.count))
        #expect(p.bubbles.allSatisfy { (1.0...3.5).contains($0.radius) && $0.rise > 0 })
        var peak = 0
        for _ in 0..<(60 * 4) {
            p.advance(dt: 1.0 / 60)
            peak = max(peak, p.bubbles.count)
            for b in p.bubbles { #expect(b.y > p.surfaceY(atX: b.x) - 0.5) }   // none above the surface
        }
        #expect(peak > 0)
        #expect(p.bubbles.isEmpty)
    }

    @Test func noBubblesInAnAlmostEmptyGlass() {
        var p = WaterPhysics(seed: 5)
        p.snap(level: 0.0, overflowing: false)
        p.pour(strength: 0.05)
        p.setLevel(0.02)
        #expect(p.bubbles.isEmpty)
    }
}

@Suite struct SpillTests {
    @Test func spillScalesWithTheExcess() {
        var small = WaterPhysics(seed: 1), big = WaterPhysics(seed: 1)
        small.snap(level: 1, overflowing: false); big.snap(level: 1, overflowing: false)
        small.startSpill(excess: 0.05); big.startSpill(excess: 0.4)
        #expect(small.spillDuration < big.spillDuration)
        #expect(small.spillIntensity < big.spillIntensity)
        #expect(big.spillDuration <= 7.5 && small.spillDuration >= 1.4)
    }

    @Test func streamsClingThenBreakIntoDropsAndSplash() {
        var p = WaterPhysics(seed: 2)
        p.snap(level: 1, overflowing: false)
        p.startSpill(excess: 0.25)
        var kinds = Set<String>()
        var sawRing = false
        for _ in 0..<(60 * 6) {
            p.advance(dt: 1.0 / 60)
            for q in p.particles { kinds.insert("\(q.kind)") }
            sawRing = sawRing || !p.rings.isEmpty
            // Every spilling particle is outside the glass or on its way down: never above the rim.
            #expect(p.particles.allSatisfy { $0.y >= CupGeometry.topY - 1 })
            #expect(p.particles.count <= 260)
        }
        #expect(kinds.isSuperset(of: ["film", "stream", "drop", "splash"]), "saw \(kinds)")
        #expect(sawRing)
        #expect(p.puddle > 0)
    }

    @Test func spillEmitsFromBothFrontEdges() {
        var p = WaterPhysics(seed: 2)
        p.snap(level: 1, overflowing: false)
        p.startSpill(excess: 0.3)
        run(&p, seconds: 0.5)
        let films = p.particles.filter { $0.kind == .film || $0.kind == .stream }
        #expect(films.contains { $0.x < CupGeometry.cx } && films.contains { $0.x > CupGeometry.cx })
    }

    @Test func taperThenSettlesToATremblingFullBrimAndRests() {
        var p = WaterPhysics(seed: 4)
        p.snap(level: 1, overflowing: false)
        p.startSpill(excess: 0.1)
        #expect(p.dome == 0)
        run(&p, seconds: 0.4)
        #expect(p.dome > 0.2)                          // surface tension bulge builds before it breaks
        var t = 0.0
        while t < 15 && !p.isAtRest { p.advance(dt: 1.0 / 60); t += 1.0 / 60 }
        #expect(p.isAtRest)
        #expect(p.particles.isEmpty && p.rings.isEmpty)
        #expect(abs(p.dome - 0.45) < 0.01)             // a full brim with a small meniscus
        #expect(p.puddle > 0.2)                        // the puddle stays while you're over the goal
        #expect(p.spillRemaining == 0)
    }

    @Test func goingBackUnderTheGoalClearsTheDomeAndPuddle() {
        var p = WaterPhysics(seed: 4)
        p.snap(level: 1, overflowing: true)
        #expect(p.isAtRest && p.dome > 0 && p.puddle > 0)
        p.clearOverflow()
        run(&p, seconds: 8)
        #expect(p.isAtRest)
        #expect(p.dome < 0.01 && p.puddle < 0.01)
    }

    @Test func sameSeedSameSpill() {
        func spill() -> [Double] {
            var p = WaterPhysics(seed: 9)
            p.snap(level: 1, overflowing: false)
            p.startSpill(excess: 0.2)
            run(&p, seconds: 1)
            return p.particles.map(\.y)
        }
        #expect(spill() == spill())
    }

    @Test func geometryIsConsistent() {
        #expect(CupGeometry.waterlineY(1) < CupGeometry.waterlineY(0.5))
        #expect(CupGeometry.waterlineY(0) == CupGeometry.cavityBottomY)
        #expect(CupGeometry.cavityHalf(CupGeometry.topY) == CupGeometry.topHalf - CupGeometry.wall)
        #expect(CupGeometry.groundY > CupGeometry.bottomY + CupGeometry.bottomRY)
        #expect(CupGeometry.cavityBottomY < CupGeometry.bottomY - 8)   // a thick solid base
    }
}

@Suite struct DayResetTests {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

    @Test func resetClearsOnlyThatDaysWater() {
        var data = WellbeingData()
        let today = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 12))!
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        data.addWater(500, at: today, calendar: cal)
        data.addWater(700, at: yesterday, calendar: cal)
        data.addMindful(seconds: 120, at: today, calendar: cal)
        data.resetWater(on: today, calendar: cal)
        #expect(data.day(for: today, calendar: cal).waterML == 0)
        #expect(data.day(for: today, calendar: cal).mindfulSeconds == 120)   // mindfulness is kept
        #expect(data.day(for: yesterday, calendar: cal).waterML == 700)
    }
}
