import Foundation

/// A small, seedable random generator so simulations are reproducible in tests.
public struct SplitMix64: Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func unit() -> Double { Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0) }
    public mutating func range(_ lower: Double, _ upper: Double) -> Double { lower + (upper - lower) * unit() }
}

public struct WaterBubble: Sendable, Equatable {
    public var baseX: Double, x: Double, y: Double
    public var radius: Double, rise: Double
    public var wobbleAmplitude: Double, wobbleFrequency: Double, phase: Double
}

public struct SpillParticle: Sendable, Equatable {
    public enum Kind: Sendable { case film, stream, drop, splash }
    public var kind: Kind
    public var side: Double
    public var x: Double, y: Double, vx: Double, vy: Double
    public var radius: Double
    /// Distance left to cling to the outer wall (film), or to fall as a smooth stream before breaking up.
    public var remaining: Double
    public var age = 0.0
    public var life = 0.0
}

public struct PuddleRing: Sendable, Equatable {
    public var x: Double
    public var age = 0.0
    public var life: Double
    public var maxWidth: Double
}

/// Shallow-water physics for the glass: 100 coupled spring-mass nodes along the surface, an eased fill
/// level, rising bubbles, and a spill that clings to the glass, breaks into drops and splashes on the table.
///
/// Pure value-type simulation advanced in fixed 1/60 s steps, so it behaves the same at 60 or 120 Hz.
public struct WaterPhysics: Sendable {
    public static let nodeCount = 100

    // Tuning
    static let stiffness = 0.03          // Hooke's law restoring constant
    static let damping = 0.96            // velocity retained each step
    static let spread = 0.25             // momentum exchanged between neighbours per pass
    static let passes = 8
    static let fixedStep = 1.0 / 60.0
    static let gravity = 300.0           // pt/s²
    static let maxParticles = 260
    static let restKinetic = 0.001

    /// Displayed fill, 0...1.
    public private(set) var level = 0.0
    public private(set) var heights = [Double](repeating: 0, count: nodeCount)
    public private(set) var velocities = [Double](repeating: 0, count: nodeCount)
    public private(set) var bubbles: [WaterBubble] = []
    public private(set) var particles: [SpillParticle] = []
    public private(set) var rings: [PuddleRing] = []
    /// 0...1, how much the surface bulges above the rim (surface tension).
    public private(set) var dome = 0.0
    /// 0...1, how big the puddle on the table is.
    public private(set) var puddle = 0.0
    public private(set) var spillRemaining = 0.0
    public private(set) var spillDuration = 0.0
    public private(set) var spillIntensity = 0.0
    /// Seconds of simulated time; frozen while the water is at rest.
    public private(set) var clock = 0.0
    public private(set) var isAtRest = true

    private var levelFrom = 0.0, levelTo = 0.0, levelElapsed = 0.0, levelAnimating = false
    private let levelDuration = 0.7
    private var pourRemaining = 0.0, pourStrength = 0.0
    private var domeTarget = 0.0, puddleTarget = 0.0
    private var accumulator = 0.0
    private var emitCarry = [0.0, 0.0]
    private var rng: SplitMix64

    public init(seed: UInt64 = 1) { rng = SplitMix64(seed: seed) }

    // MARK: Queries

    public var kineticEnergy: Double { velocities.reduce(0) { $0 + 0.5 * $1 * $1 } }
    public var isBrimming: Bool { domeTarget > 0 }

    /// Surface displacement (points, up is positive) at u in -1...1 across the glass.
    public func height(atU u: Double) -> Double {
        let pos = (min(1, max(-1, u)) + 1) / 2 * Double(Self.nodeCount - 1)
        let i = Int(pos), j = min(i + 1, Self.nodeCount - 1), f = pos - Double(i)
        return heights[i] * (1 - f) + heights[j] * f
    }

    /// Screen y of the water surface (centre line) at horizontal position x.
    public func surfaceY(atX x: Double) -> Double {
        let yw = CupGeometry.waterlineY(level)
        let u = (x - CupGeometry.cx) / max(1, CupGeometry.cavityHalf(yw))
        return yw - height(atU: u)
    }

    // MARK: Commands

    /// Jumps to a state with no animation (used when the tab first appears).
    public mutating func snap(level newLevel: Double, overflowing: Bool) {
        level = min(1, max(0, newLevel)); levelFrom = level; levelTo = level; levelAnimating = false
        heights = [Double](repeating: 0, count: Self.nodeCount)
        velocities = heights
        bubbles = []; particles = []; rings = []
        domeTarget = overflowing ? 0.45 : 0; dome = domeTarget
        puddleTarget = overflowing ? 0.4 : 0; puddle = puddleTarget
        spillRemaining = 0; pourRemaining = 0
        isAtRest = true
    }

    /// Eases the fill to `target` over 700 ms.
    public mutating func setLevel(_ target: Double) {
        levelFrom = level; levelTo = min(1, max(0, target)); levelElapsed = 0; levelAnimating = true
        isAtRest = false
    }

    /// Water is being added: a stream hits the centre of the surface and bubbles are carried down.
    public mutating func pour(strength: Double) {
        pourRemaining = levelDuration
        pourStrength = min(1.5, max(0.3, 0.3 + strength * 2))
        let yw = CupGeometry.waterlineY(max(level, levelTo))
        let floor = CupGeometry.cavityBottomY
        if floor - yw > 8 {
            let count = 20 + Int(rng.range(0, 11))
            for _ in 0..<count {
                let spread = CupGeometry.cavityHalf(yw) * 0.55
                let x = CupGeometry.cx + rng.range(-spread, spread)
                bubbles.append(WaterBubble(
                    baseX: x, x: x, y: yw + rng.range(2, min(14, floor - yw - 2)), radius: rng.range(1.0, 3.5),
                    rise: rng.range(14, 34), wobbleAmplitude: rng.range(0.5, 1.3),
                    wobbleFrequency: rng.range(3, 7), phase: rng.range(0, .pi * 2)))
            }
        }
        isAtRest = false
    }

    /// The glass overflowed: spill for a time and with a force proportional to the excess (a fraction of the goal).
    public mutating func startSpill(excess: Double) {
        spillDuration = min(7.5, max(1.4, 1.4 + excess * 10))
        spillRemaining = spillDuration
        spillIntensity = min(1, max(0.4, 0.4 + excess * 3))
        domeTarget = 1
        puddleTarget = min(1, puddleTarget + 0.25 + excess * 2)
        isAtRest = false
    }

    /// Exactly full: the water stands at the brim with a slight meniscus, without spilling.
    public mutating func holdBrim() {
        domeTarget = max(domeTarget, 0.45)
        isAtRest = false
    }

    /// Back under the goal: the dome and puddle go away.
    public mutating func clearOverflow() {
        spillRemaining = 0
        domeTarget = 0; puddleTarget = 0
        isAtRest = false
    }

    /// A cursor sweeping across the glass at horizontal position `x` (0...1) with horizontal speed `velocity` (pt/s).
    public mutating func slosh(x: Double, velocity: Double) {
        guard level > 0.02 else { return }
        let impulse = min(2.2, max(-2.2, velocity / 140))
        guard abs(impulse) > 0.02 else { return }
        for i in 0..<Self.nodeCount {
            let d = (Double(i) / Double(Self.nodeCount - 1) - x) / 0.16
            velocities[i] += impulse * d * exp(-d * d) * 0.9
        }
        isAtRest = false
    }

    // MARK: Stepping

    public mutating func advance(dt: Double) {
        guard !isAtRest else { return }
        accumulator += min(max(dt, 0), 0.1)
        while accumulator >= Self.fixedStep {
            step()
            accumulator -= Self.fixedStep
            if isAtRest { accumulator = 0; break }
        }
    }

    private mutating func step() {
        let dt = Self.fixedStep
        let n = Self.nodeCount
        clock += dt

        if levelAnimating {
            levelElapsed += dt
            let t = min(1, levelElapsed / levelDuration)
            level = levelFrom + (levelTo - levelFrom) * (1 - pow(1 - t, 3))
            if t >= 1 { levelAnimating = false; level = levelTo }
        }

        if pourRemaining > 0 {
            pourRemaining = max(0, pourRemaining - dt)
            let centre = n / 2, fade = 0.3 + pourRemaining / levelDuration
            for i in max(0, centre - 9)...min(n - 1, centre + 9) {
                velocities[i] -= pourStrength * 0.35 * fade * (1 - Double(abs(i - centre)) / 10)
            }
        }

        // Hooke's law with damping.
        for i in 0..<n {
            velocities[i] += -Self.stiffness * heights[i]
            velocities[i] *= Self.damping
            heights[i] = min(6, max(-6, heights[i] + velocities[i]))
        }
        // Traveling ripples: neighbours exchange momentum, several passes per step.
        var leftDelta = [Double](repeating: 0, count: n), rightDelta = leftDelta
        for _ in 0..<Self.passes {
            for i in 0..<n {
                if i > 0 { leftDelta[i] = Self.spread * (heights[i] - heights[i - 1]); velocities[i - 1] += leftDelta[i] }
                if i < n - 1 { rightDelta[i] = Self.spread * (heights[i] - heights[i + 1]); velocities[i + 1] += rightDelta[i] }
            }
            for i in 0..<n {
                if i > 0 { heights[i - 1] += leftDelta[i] }
                if i < n - 1 { heights[i + 1] += rightDelta[i] }
            }
        }

        stepBubbles(dt)
        if spillRemaining > 0 {
            spillRemaining = max(0, spillRemaining - dt)
            emitSpill(dt)
            if spillRemaining == 0 { domeTarget = 0.45 }
        }
        stepParticles(dt)
        stepRings(dt)
        dome += (domeTarget - dome) * min(1, 6 * dt)
        puddle += (puddleTarget - puddle) * min(1, 2 * dt)

        updateRest()
    }

    private mutating func stepBubbles(_ dt: Double) {
        guard !bubbles.isEmpty else { return }
        var kept: [WaterBubble] = []
        kept.reserveCapacity(bubbles.count)
        for var b in bubbles {
            b.rise *= 1 + 0.25 * dt
            b.y -= b.rise * dt
            b.phase += b.wobbleFrequency * dt
            b.x = b.baseX + sin(b.phase) * b.wobbleAmplitude
            // A bubble pops the instant it crosses the (moving) surface.
            if b.y - b.radius * 0.3 > surfaceY(atX: b.x) { kept.append(b) }
        }
        bubbles = kept
    }

    private mutating func emitSpill(_ dt: Double) {
        let taper = spillRemaining > 1 ? 1.0 : max(0, spillRemaining)
        for (k, side) in [-1.0, 1.0].enumerated() {
            // The lowest wave crest near each front rim point spills the most.
            let crest = height(atU: side * 0.82)
            emitCarry[k] += spillIntensity * 48 * taper * max(0.3, 0.75 + crest * 0.3) * dt
            while emitCarry[k] >= 1, particles.count < Self.maxParticles {
                emitCarry[k] -= 1
                particles.append(SpillParticle(
                    kind: .film, side: side,
                    x: CupGeometry.cx + side * (CupGeometry.topHalf * 0.82 + rng.range(-1, 1)),
                    y: CupGeometry.topY + CupGeometry.rimRY * 0.57, vx: 0, vy: rng.range(8, 16),
                    radius: rng.range(0.9, 1.3), remaining: rng.range(10, 24)))
            }
            if emitCarry[k] > 4 { emitCarry[k] = 0 }
        }
    }

    private mutating func stepParticles(_ dt: Double) {
        guard !particles.isEmpty else { return }
        var kept: [SpillParticle] = []
        var splashes: [SpillParticle] = []
        kept.reserveCapacity(particles.count)
        for var p in particles {
            p.age += dt
            switch p.kind {
            case .film:
                // Clings to the outer wall, accelerating slowly.
                p.vy += 70 * dt
                p.y += p.vy * dt
                let wallX = CupGeometry.cx + p.side * (CupGeometry.half(p.y) + 0.9)
                p.x += (wallX - p.x) * min(1, 14 * dt)
                p.remaining -= p.vy * dt
                if p.remaining <= 0 {
                    p.kind = .stream
                    p.vx = p.side * rng.range(2, 6)
                    p.remaining = rng.range(16, 30)
                }
            case .stream, .drop:
                p.vy += Self.gravity * dt
                p.x += p.vx * dt; p.y += p.vy * dt
                if p.kind == .stream {
                    p.remaining -= p.vy * dt
                    // Rayleigh–Plateau: a long thin stream pinches off into separate drops.
                    if p.remaining <= 0 { p.kind = .drop; p.radius = rng.range(1.1, 2.0) }
                }
            case .splash:
                p.vy += Self.gravity * dt
                p.x += p.vx * dt; p.y += p.vy * dt
                if p.age > p.life { continue }
            }
            if p.kind != .film, p.y >= CupGeometry.groundY {
                if p.kind != .splash { splashes += impact(at: p.x) }
                continue
            }
            kept.append(p)
        }
        particles = kept + splashes.prefix(max(0, Self.maxParticles - kept.count))
    }

    /// A drop hit the table: a ring spreads, the puddle grows, and a few micro droplets jump.
    private mutating func impact(at x: Double) -> [SpillParticle] {
        if rings.count < 12 { rings.append(PuddleRing(x: x, life: 0.9, maxWidth: rng.range(18, 34))) }
        puddleTarget = min(1, puddleTarget + 0.004)
        return (0..<Int(rng.range(2, 5))).map { _ in
            SpillParticle(kind: .splash, side: 0, x: x, y: CupGeometry.groundY - 0.5, vx: rng.range(-26, 26),
                          vy: -rng.range(28, 62), radius: rng.range(0.6, 1.1), remaining: 0, life: 0.5)
        }
    }

    private mutating func stepRings(_ dt: Double) {
        guard !rings.isEmpty else { return }
        rings = rings.compactMap { var r = $0; r.age += dt; return r.age < r.life ? r : nil }
    }

    private mutating func updateRest() {
        let maxHeight = heights.reduce(0) { max($0, abs($1)) }
        let settled = kineticEnergy < Self.restKinetic && maxHeight < 0.01
        let idle = !levelAnimating && pourRemaining <= 0 && spillRemaining <= 0
            && bubbles.isEmpty && particles.isEmpty && rings.isEmpty
            && abs(dome - domeTarget) < 0.005 && abs(puddle - puddleTarget) < 0.005
        guard settled && idle else { return }
        heights = [Double](repeating: 0, count: Self.nodeCount)
        velocities = heights
        dome = domeTarget; puddle = puddleTarget
        isAtRest = true
    }
}
