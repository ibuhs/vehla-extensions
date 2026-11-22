import SwiftUI
import WellbeingCore

/// Draws the breathing exercise: a glass track a comet travels around once per cycle, with a glass orb that
/// swells and shrinks inside it and a few motes drifting with the breath. Monochrome white to suit the Notch.
enum BreathRenderer {
    static let size = CGSize(width: 92, height: 92)
    private static let inset = 8.0
    private static let span = 76.0
    private static let centre = CGPoint(x: 46, y: 46)
    private static let orbRadius = 23.0

    private static func map(_ p: (x: Double, y: Double)) -> CGPoint {
        CGPoint(x: inset + p.x * span, y: inset + p.y * span)
    }

    private static func path(_ track: BreathTrack, from t0: Double, to t1: Double) -> Path {
        var path = Path()
        let points = track.samples(from: t0, to: t1)
        guard let first = points.first else { return path }
        path.move(to: map(first))
        for p in points.dropFirst() { path.addLine(to: map(p)) }
        return path
    }

    private static func smooth(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }

    /// `state` is nil when no session is running: the track and orb are drawn at rest.
    static func draw(_ ctx: inout GraphicsContext, size canvas: CGSize, pattern: BreathPattern,
                     state: BreathState?, time: TimeInterval) {
        let scale = min(canvas.width / size.width, canvas.height / size.height)
        ctx.translateBy(x: (canvas.width - size.width * scale) / 2, y: (canvas.height - size.height * scale) / 2)
        ctx.scaleBy(x: scale, y: scale)

        let track = BreathTrack.forPattern(pattern)
        let breath = orbScale(state)
        drawTrack(&ctx, track: track, pattern: pattern, state: state)
        drawMotes(&ctx, breath: breath, time: time)
        drawOrb(&ctx, scale: breath, state: state, time: time)
        if let state { drawComet(&ctx, track: track, state: state) }
        else { drawRestingDot(&ctx, track: track) }
    }

    /// Eased fill of the orb: slow at the start and end of each breath, like a real one.
    private static func orbScale(_ state: BreathState?) -> Double {
        guard let state else { return BreathPattern.emptyScale }
        let span = 1 - BreathPattern.emptyScale
        switch state.phase.kind {
        case .inhale: return BreathPattern.emptyScale + span * smooth(state.progress)
        case .exhale: return 1 - span * smooth(state.progress)
        case .hold: return state.scale
        }
    }

    // MARK: Track

    private static func drawTrack(_ ctx: inout GraphicsContext, track: BreathTrack, pattern: BreathPattern, state: BreathState?) {
        let full = path(track, from: 0, to: 1)
        var halo = ctx
        halo.blendMode = .plusLighter
        halo.stroke(full, with: .color(.white.opacity(0.05)), lineWidth: 5)
        ctx.stroke(full, with: .color(.white.opacity(0.15)), lineWidth: 1.4)

        // A tick where each phase begins.
        var start = 0.0
        for phase in pattern.phases {
            ctx.fill(Path(ellipseIn: dot(map(track.point(at: start)), 1.7)), with: .color(.white.opacity(0.4)))
            start += phase.seconds / pattern.cycleSeconds
        }
        guard let state else { return }

        // Sides already breathed this cycle stay lit; the current one fills as you go.
        if state.phaseStart > 0.001 {
            ctx.stroke(path(track, from: 0, to: state.phaseStart), with: .color(.white.opacity(0.36)),
                       style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        let current = path(track, from: state.phaseStart, to: max(state.phaseStart + 0.0005, state.cycleProgress))
        halo.stroke(current, with: .color(.white.opacity(0.20)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        ctx.stroke(current, with: .color(.white.opacity(0.92)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    private static func dot(_ c: CGPoint, _ r: Double) -> CGRect { CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2) }

    private static func drawComet(_ ctx: inout GraphicsContext, track: BreathTrack, state: BreathState) {
        var glow = ctx
        glow.blendMode = .plusLighter
        // A fading trail behind the head.
        for k in stride(from: 16, through: 1, by: -1) {
            let t = state.cycleProgress - Double(k) * 0.0065
            let f = 1 - Double(k) / 17
            glow.fill(Path(ellipseIn: dot(map(track.point(at: t)), 0.9 + 2.2 * f)), with: .color(.white.opacity(0.30 * f * f)))
        }
        let head = map(track.point(at: state.cycleProgress))
        glow.fill(Path(ellipseIn: dot(head, 9)), with: .radialGradient(
            Gradient(colors: [.white.opacity(0.55), .clear]), center: head, startRadius: 0, endRadius: 9))
        ctx.fill(Path(ellipseIn: dot(head, 3.1)), with: .color(.white))
        ctx.fill(Path(ellipseIn: dot(CGPoint(x: head.x - 0.8, y: head.y - 0.9), 1.2)), with: .color(.white))
    }

    private static func drawRestingDot(_ ctx: inout GraphicsContext, track: BreathTrack) {
        let head = map(track.point(at: 0))
        ctx.fill(Path(ellipseIn: dot(head, 2.6)), with: .color(.white.opacity(0.7)))
    }

    // MARK: Motes

    /// Specks that drift in a slow orbit and swell outward and inward with the breath.
    private static func drawMotes(_ ctx: inout GraphicsContext, breath: Double, time: TimeInterval) {
        let swell = (breath - BreathPattern.emptyScale) / (1 - BreathPattern.emptyScale)
        for i in 0..<14 {
            let seed = Double(i)
            let angle = seed * 2.399963 + time * (0.10 + 0.05 * Double(i % 3))
            let distance = (0.78 + 0.22 * Double((i * 7) % 5) / 4) * (30 + 8 * swell)
            let x = centre.x + cos(angle) * distance, y = centre.y + sin(angle) * distance * 0.92
            let twinkle = 0.55 + 0.45 * sin(time * 1.4 + seed * 1.7)
            ctx.fill(Path(ellipseIn: dot(CGPoint(x: x, y: y), 0.7 + 0.35 * Double(i % 3))),
                     with: .color(.white.opacity((0.10 + 0.20 * swell) * twinkle)))
        }
    }

    // MARK: Orb

    private static func drawOrb(_ ctx: inout GraphicsContext, scale: Double, state: BreathState?, time: TimeInterval) {
        let r = orbRadius * scale
        let rect = CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2)
        let orb = Path(ellipseIn: rect)

        var glow = ctx
        glow.blendMode = .plusLighter
        glow.fill(Path(ellipseIn: dot(centre, r * 1.9)), with: .radialGradient(
            Gradient(colors: [.white.opacity(0.16), .clear]), center: centre, startRadius: r * 0.8, endRadius: r * 1.9))

        // Rings that ripple out on the in-breath and gather back in on the out-breath.
        if let state, state.phase.kind != .hold {
            for k in 0..<2 {
                let phase = (state.progress + Double(k) * 0.5).truncatingRemainder(dividingBy: 1)
                let travel = state.phase.kind == .inhale ? phase : 1 - phase
                let ringRadius = r * (1.04 + 0.5 * travel)
                glow.stroke(Path(ellipseIn: dot(centre, ringRadius)),
                            with: .color(.white.opacity(0.22 * (1 - phase))), lineWidth: 0.8)
            }
        } else if state != nil {
            glow.stroke(Path(ellipseIn: dot(centre, r * (1.08 + 0.012 * sin(time * 3)))), with: .color(.white.opacity(0.13)), lineWidth: 0.8)
        }

        // Glass body.
        ctx.fill(orb, with: .radialGradient(
            Gradient(stops: [.init(color: .white.opacity(0.52), location: 0), .init(color: .white.opacity(0.22), location: 0.55),
                             .init(color: .white.opacity(0.07), location: 1)]),
            center: CGPoint(x: centre.x - r * 0.3, y: centre.y - r * 0.35), startRadius: 0, endRadius: r * 1.3))
        ctx.drawLayer { layer in
            layer.clip(to: orb)
            var light = layer
            light.blendMode = .plusLighter
            // Light bouncing back from the far side of the glass.
            light.fill(Path(rect), with: .radialGradient(
                Gradient(colors: [.white.opacity(0.20), .clear]),
                center: CGPoint(x: centre.x + r * 0.38, y: centre.y + r * 0.46), startRadius: 0, endRadius: r * 0.85))
            layer.stroke(Path(ellipseIn: dot(centre, r * 0.62)), with: .color(.white.opacity(0.08)), lineWidth: 0.8)
        }
        ctx.stroke(orb, with: .linearGradient(
            Gradient(colors: [.white.opacity(0.9), .white.opacity(0.4), .white.opacity(0.14)]),
            startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)), lineWidth: 1.2)

        // Specular highlight.
        var spec = ctx
        spec.translateBy(x: centre.x - r * 0.36, y: centre.y - r * 0.46)
        spec.rotate(by: .degrees(-32))
        spec.fill(Path(ellipseIn: CGRect(x: -r * 0.3, y: -r * 0.14, width: r * 0.6, height: r * 0.28)), with: .linearGradient(
            Gradient(colors: [.white.opacity(0.75), .white.opacity(0.05)]),
            startPoint: CGPoint(x: -r * 0.3, y: 0), endPoint: CGPoint(x: r * 0.3, y: 0)))
    }
}
