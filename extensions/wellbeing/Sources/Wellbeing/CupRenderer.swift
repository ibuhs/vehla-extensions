import SwiftUI
import WellbeingCore

/// Draws the glass of water in one Canvas pass: optical glass, a perspective water surface with
/// capillary meniscus, caustics, bubbles, and the spill. All procedural; no image assets.
enum CupRenderer {
    private typealias G = CupGeometry

    // Water colours: luminous near the surface, deeper toward the glass base.
    private static let surfaceLight = Color(red: 0.80, green: 0.96, blue: 1.00)
    private static let shallow = Color(red: 0.60, green: 0.86, blue: 0.99)
    private static let mid = Color(red: 0.44, green: 0.74, blue: 0.96)
    private static let deep = Color(red: 0.26, green: 0.50, blue: 0.86)
    private static let spray = Color(red: 0.66, green: 0.87, blue: 1.0)

    static func draw(_ ctx: inout GraphicsContext, size: CGSize, physics p: WaterPhysics) {
        let scale = min(size.width / G.width, size.height / G.height)
        ctx.translateBy(x: (size.width - G.width * scale) / 2, y: 0)
        ctx.scaleBy(x: scale, y: scale)
        drawGround(&ctx, p)
        drawGlassBack(&ctx)
        drawWater(&ctx, p)
        drawDome(&ctx, p)
        drawGlassFront(&ctx)
        drawSpill(&ctx, p)
    }

    // MARK: Paths

    private static func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

    /// A tapered tub with an elliptical rim and an elliptical bottom edge.
    private static func tub(topHalf th: Double, topRY: Double, bottomHalf bh: Double, bottomY by: Double,
                            bottomRY bry: Double) -> Path {
        var p = Path()
        p.move(to: pt(G.cx - th, G.topY))
        p.addLine(to: pt(G.cx - bh, by))
        p.addCurve(to: pt(G.cx + bh, by), control1: pt(G.cx - bh, by + bry * G.kappa), control2: pt(G.cx + bh, by + bry * G.kappa))
        p.addLine(to: pt(G.cx + th, G.topY))
        p.addCurve(to: pt(G.cx - th, G.topY), control1: pt(G.cx + th, G.topY - topRY * G.kappa), control2: pt(G.cx - th, G.topY - topRY * G.kappa))
        p.closeSubpath()
        return p
    }

    private static var outline: Path {
        tub(topHalf: G.topHalf, topRY: G.rimRY, bottomHalf: G.bottomHalf, bottomY: G.bottomY, bottomRY: G.bottomRY)
    }

    private static var cavity: Path {
        let th = G.cavityHalf(G.topY), by = G.cavityBottomY, bh = G.cavityHalf(by)
        return tub(topHalf: th, topRY: G.rimRY(forHalf: th), bottomHalf: bh, bottomY: by, bottomRY: G.bottomRY * bh / G.bottomHalf)
    }

    private static func rimArc(front: Bool, inset: Double = 0) -> Path {
        let h = G.topHalf - inset, ry = G.rimRY(forHalf: h), s = front ? 1.0 : -1.0
        var p = Path()
        p.move(to: pt(G.cx - h, G.topY))
        p.addCurve(to: pt(G.cx + h, G.topY), control1: pt(G.cx - h, G.topY + s * ry * G.kappa), control2: pt(G.cx + h, G.topY + s * ry * G.kappa))
        return p
    }

    private static func gradient(_ stops: [(Color, Double)]) -> Gradient {
        Gradient(stops: stops.map { Gradient.Stop(color: $0.0, location: $0.1) })
    }

    // MARK: Ground

    private static func drawGround(_ ctx: inout GraphicsContext, _ p: WaterPhysics) {
        // A soft contact glow so the glass sits on the surface.
        let glow = CGRect(x: G.cx - 27, y: G.groundY - 3, width: 54, height: 6)
        ctx.fill(Path(ellipseIn: glow), with: .radialGradient(
            Gradient(colors: [.white.opacity(0.10), .clear]), center: pt(G.cx, G.groundY), startRadius: 0, endRadius: 27))

        if p.puddle > 0.01 {
            let width = 22 + 52 * p.puddle
            let rect = CGRect(x: G.cx - width / 2, y: G.groundY - 2.4, width: width, height: 4.8)
            ctx.fill(Path(ellipseIn: rect), with: .linearGradient(
                gradient([(spray.opacity(0.10), 0), (spray.opacity(0.50), 0.5), (spray.opacity(0.10), 1)]),
                startPoint: pt(rect.minX, rect.midY), endPoint: pt(rect.maxX, rect.midY)))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.16)), lineWidth: 0.5)
        }
        for ring in p.rings {
            let t = ring.age / ring.life
            let w = 5 + ring.maxWidth * t
            let rect = CGRect(x: ring.x - w / 2, y: G.groundY - w * 0.09, width: w, height: w * 0.18)
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.5 * (1 - t))), lineWidth: 0.8)
        }
    }

    // MARK: Glass

    private static func drawGlassBack(_ ctx: inout GraphicsContext) {
        ctx.stroke(rimArc(front: false), with: .color(.white.opacity(0.26)), lineWidth: 1)
        ctx.stroke(rimArc(front: false, inset: G.wall), with: .color(.white.opacity(0.12)), lineWidth: 0.6)
        // Glass is brighter toward its edges, where you look through more of it.
        ctx.fill(outline, with: .linearGradient(
            gradient([(.white.opacity(0.13), 0), (.white.opacity(0.03), 0.3), (.white.opacity(0.02), 0.68), (.white.opacity(0.11), 1)]),
            startPoint: pt(G.cx - G.topHalf, 0), endPoint: pt(G.cx + G.topHalf, 0)))
    }

    private static func drawGlassFront(_ ctx: inout GraphicsContext) {
        let by = G.cavityBottomY
        // The solid punt: the ring between the outside and the hollow, which bends light differently.
        var ring = outline
        ring.addPath(cavity)
        ctx.fill(ring, with: .linearGradient(
            gradient([(.white.opacity(0.07), 0), (.white.opacity(0.22), 0.55), (.white.opacity(0.12), 1)]),
            startPoint: pt(0, by), endPoint: pt(0, G.bottomY + G.bottomRY)), style: FillStyle(eoFill: true))
        // The thick base acts like a lens: a bright caustic with a dark rim.
        let lens = CGRect(x: G.cx - G.bottomHalf * 0.62, y: by + 1.4, width: G.bottomHalf * 1.24, height: G.base * 0.62)
        var punt = ctx
        punt.clip(to: ring, style: FillStyle(eoFill: true))
        punt.fill(Path(ellipseIn: lens), with: .radialGradient(
            gradient([(.white.opacity(0.34), 0), (.white.opacity(0.08), 0.7), (.black.opacity(0.18), 1)]),
            center: pt(G.cx, lens.midY), startRadius: 0, endRadius: lens.width / 2))
        punt.stroke(Path(ellipseIn: lens), with: .color(.white.opacity(0.14)), lineWidth: 0.5)

        // Fresnel: edges brighten, with a soft halo so the silhouette holds over any background.
        var halo = ctx
        halo.blendMode = .plusLighter
        halo.stroke(outline, with: .color(.white.opacity(0.07)), lineWidth: 3.2)
        ctx.stroke(outline, with: .linearGradient(
            gradient([(.white.opacity(0.78), 0), (.white.opacity(0.30), 0.35), (.white.opacity(0.26), 0.65), (.white.opacity(0.62), 1)]),
            startPoint: pt(G.cx - G.topHalf, 0), endPoint: pt(G.cx + G.topHalf, 0)), lineWidth: 1.1)
        ctx.stroke(cavity, with: .color(.white.opacity(0.16)), lineWidth: 0.8)

        // Double lip on the near rim: outer and inner edge.
        ctx.stroke(rimArc(front: true), with: .color(.white.opacity(0.88)), lineWidth: 1.4)
        ctx.stroke(rimArc(front: true, inset: G.wall), with: .color(.white.opacity(0.34)), lineWidth: 0.7)

        // Studio key-light streaks.
        func streak(_ side: Double, _ y0: Double, _ y1: Double, inset: Double, width: Double, alpha: Double) {
            let x0 = G.cx + side * (G.half(y0) - inset), x1 = G.cx + side * (G.half(y1) - inset)
            var p = Path()
            p.move(to: pt(x0, y0))
            p.addQuadCurve(to: pt(x1, y1), control: pt((x0 + x1) / 2 - side * 1.5, (y0 + y1) / 2))
            var s = ctx
            s.blendMode = .plusLighter
            s.stroke(p, with: .linearGradient(gradient([(.white.opacity(alpha), 0), (.white.opacity(alpha * 0.12), 1)]),
                                              startPoint: pt(x0, y0), endPoint: pt(x1, y1)),
                     style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
        streak(-1, G.topY + 9, G.cavityBottomY - 5, inset: 6.2, width: 2.4, alpha: 0.55)
        streak(-1, G.cavityBottomY - 1, G.bottomY - 2, inset: 8.5, width: 1.5, alpha: 0.32)
        streak(1, G.topY + 13, G.topY + 38, inset: 5.4, width: 1.4, alpha: 0.28)
    }

    // MARK: Water

    private struct Surface {
        let yw: Double, halfWidth: Double, ry: Double
        var front: [CGPoint] = [], back: [CGPoint] = []
    }

    private static func surface(_ p: WaterPhysics) -> Surface {
        let n = WaterPhysics.nodeCount
        let yw = G.waterlineY(p.level), ih = G.cavityHalf(yw)
        var s = Surface(yw: yw, halfWidth: ih, ry: G.rimRY(forHalf: ih))
        for i in 0..<n {
            let u = -1 + 2 * Double(i) / Double(n - 1)
            let e = (max(0, 1 - u * u)).squareRoot()
            // Capillary meniscus: the outer four nodes curl up where water meets glass.
            let edge = min(i, n - 1 - i)
            let lift = edge < 4 ? 2.6 * pow(1 - Double(edge) / 4, 2) : 0
            let h = p.heights[i]
            let x = G.cx + u * ih
            s.front.append(pt(x, yw + s.ry * e - h - lift))
            s.back.append(pt(x, yw - s.ry * e - h * 0.8 - lift))   // depth offset: the far edge moves a little less
        }
        return s
    }

    private static func drawWater(_ ctx: inout GraphicsContext, _ p: WaterPhysics) {
        guard p.level > 0.004 else { return }
        let s = surface(p)
        let cb = G.cavityBottomY, bh = G.cavityHalf(cb), bry = G.bottomRY * bh / G.bottomHalf

        var body = Path()
        body.move(to: s.front[0])
        for point in s.front.dropFirst() { body.addLine(to: point) }
        body.addLine(to: pt(G.cx + bh, cb))
        body.addCurve(to: pt(G.cx - bh, cb), control1: pt(G.cx + bh, cb + bry * G.kappa), control2: pt(G.cx - bh, cb + bry * G.kappa))
        body.closeSubpath()

        ctx.drawLayer { layer in
            layer.clip(to: cavity)
            let top = s.yw - s.ry, bottom = cb + bry
            // Absorption: luminous near the sunlit surface, deeper toward the base.
            layer.fill(body, with: .linearGradient(
                gradient([(shallow.opacity(0.93), 0), (mid.opacity(0.93), 0.5), (deep.opacity(0.96), 1)]),
                startPoint: pt(0, top), endPoint: pt(0, bottom)))
            // Light falls off toward the walls (a water-filled cylinder acts like a lens).
            layer.fill(body, with: .linearGradient(
                gradient([(.black.opacity(0.26), 0), (.clear, 0.27), (.white.opacity(0.10), 0.42), (.clear, 0.66), (.black.opacity(0.30), 1)]),
                startPoint: pt(G.cx - s.halfWidth - 2, 0), endPoint: pt(G.cx + s.halfWidth + 2, 0)))

            layer.drawLayer { inner in
                inner.clip(to: body)
                var light = inner
                light.blendMode = .plusLighter
                light.fill(Path(CGRect(x: G.cx - 40, y: top, width: 80, height: bottom - top + 4)), with: .radialGradient(
                    Gradient(colors: [.white.opacity(0.20), .clear]), center: pt(G.cx - 9, s.yw + 10), startRadius: 0, endRadius: 36))
                drawCaustics(&light, p, s, bottom: cb)
                // Where the water rests on the thick base, light bounces back up.
                let band = CGRect(x: G.cx - bh * 0.92, y: cb - 3.4, width: bh * 1.84, height: 6.8)
                light.fill(Path(ellipseIn: band), with: .linearGradient(
                    gradient([(.white.opacity(0), 0), (.white.opacity(0.46), 0.5), (.white.opacity(0), 1)]),
                    startPoint: pt(band.minX, 0), endPoint: pt(band.maxX, 0)))
                light.stroke(Path(ellipseIn: band.insetBy(dx: 1, dy: 1.4)), with: .color(.white.opacity(0.30)), lineWidth: 0.6)
                drawBubbles(&inner, p)
            }

            // Foreshortened surface: a ribbon from the far (back) contour to the near (front) contour.
            var ribbon = Path()
            ribbon.move(to: s.back[0])
            for point in s.back.dropFirst() { ribbon.addLine(to: point) }
            for point in s.front.reversed() { ribbon.addLine(to: point) }
            ribbon.closeSubpath()
            layer.fill(ribbon, with: .linearGradient(
                gradient([(surfaceLight.opacity(0.95), 0), (shallow.opacity(0.88), 1)]),
                startPoint: pt(0, s.yw - s.ry), endPoint: pt(0, s.yw + s.ry)))
            var back = Path(); back.move(to: s.back[0]); for point in s.back.dropFirst() { back.addLine(to: point) }
            layer.stroke(back, with: .color(.white.opacity(0.22)), lineWidth: 0.7)

            var front = Path(); front.move(to: s.front[0]); for point in s.front.dropFirst() { front.addLine(to: point) }
            var glint = layer
            glint.blendMode = .plusLighter
            glint.stroke(front, with: .color(.white.opacity(0.14)), lineWidth: 2.4)
            layer.stroke(front, with: .color(.white.opacity(0.78)), lineWidth: 1)
            // Specular glints on the wave crests.
            for i in 2..<(WaterPhysics.nodeCount - 2) {
                let h = p.heights[i]
                guard h > 0.3, h >= p.heights[i - 1], h >= p.heights[i + 1] else { continue }
                var crest = Path()
                crest.move(to: pt(s.front[i].x - 2.6, s.front[i].y + 0.3))
                crest.addLine(to: pt(s.front[i].x + 2.6, s.front[i].y - 0.3))
                glint.stroke(crest, with: .color(.white.opacity(min(1, h * 1.1))),
                             style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
        }
    }

    /// Procedural light interference in the lower water column.
    private static func drawCaustics(_ ctx: inout GraphicsContext, _ p: WaterPhysics, _ s: Surface, bottom: Double) {
        let top = s.yw + s.ry + 3
        guard bottom - top > 12 else { return }
        let t = p.clock
        for row in 0..<6 {
            for col in 0..<10 {
                let fx = (Double(col) + 0.5) / 10, fy = (Double(row) + 0.5) / 6
                let v = sin(fx * 11 + t * 1.3) + sin(fy * 9 - t * 1.1 + fx * 3) + sin((fx + fy) * 13 + t * 0.8)
                let b = max(0, v - 1.25) / 1.75
                guard b > 0.04 else { continue }
                let x = G.cx - s.halfWidth + 2 * s.halfWidth * fx
                let y = top + (bottom - top) * (0.3 + 0.7 * fy)
                ctx.fill(Path(ellipseIn: CGRect(x: x - 3.4, y: y - 1.6, width: 6.8, height: 3.2)),
                         with: .color(.white.opacity(0.34 * b)))
            }
        }
    }

    private static func drawBubbles(_ ctx: inout GraphicsContext, _ p: WaterPhysics) {
        for b in p.bubbles {
            let rect = CGRect(x: b.x - b.radius, y: b.y - b.radius, width: b.radius * 2, height: b.radius * 2)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [.white.opacity(0.05), .white.opacity(0.30)]),
                center: pt(b.x, b.y), startRadius: 0, endRadius: b.radius))
            ctx.stroke(Path(ellipseIn: rect), with: .color(.white.opacity(0.62)), lineWidth: 0.5)
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - b.radius * 0.55, y: b.y - b.radius * 0.6, width: b.radius * 0.5, height: b.radius * 0.4)),
                     with: .color(.white.opacity(0.85)))
        }
    }

    // MARK: Dome

    /// Surface tension holding the water just above the rim.
    private static func drawDome(_ ctx: inout GraphicsContext, _ p: WaterPhysics) {
        guard p.dome > 0.02, p.level > 0.97 else { return }
        let h = G.cavityHalf(G.topY) + 0.5, ry = G.rimRY(forHalf: h)
        let rise = ry + 1.5 * p.dome
        var dome = Path()
        dome.move(to: pt(G.cx - h, G.topY))
        dome.addCurve(to: pt(G.cx + h, G.topY), control1: pt(G.cx - h * 0.92, G.topY - rise * G.kappa), control2: pt(G.cx + h * 0.92, G.topY - rise * G.kappa))
        dome.addCurve(to: pt(G.cx - h, G.topY), control1: pt(G.cx + h, G.topY + ry * G.kappa), control2: pt(G.cx - h, G.topY + ry * G.kappa))
        dome.closeSubpath()
        ctx.fill(dome, with: .linearGradient(gradient([(surfaceLight.opacity(0.95), 0), (shallow.opacity(0.9), 1)]),
                                             startPoint: pt(0, G.topY - rise), endPoint: pt(0, G.topY + ry)))
        var upper = Path()
        upper.move(to: pt(G.cx - h, G.topY))
        upper.addCurve(to: pt(G.cx + h, G.topY), control1: pt(G.cx - h * 0.92, G.topY - rise * G.kappa), control2: pt(G.cx + h * 0.92, G.topY - rise * G.kappa))
        var glint = ctx
        glint.blendMode = .plusLighter
        glint.stroke(upper, with: .color(.white.opacity(0.55)), lineWidth: 1)
    }

    // MARK: Spill

    private static func drawSpill(_ ctx: inout GraphicsContext, _ p: WaterPhysics) {
        for q in p.particles {
            let fade = q.kind == .splash ? max(0, 1 - q.age / max(0.01, q.life)) : 1
            switch q.kind {
            case .film:
                // A thin sheet hugging the outer wall.
                let length = 6 + q.vy * 0.07
                var path = Path()
                path.move(to: pt(q.x, q.y - length))
                path.addLine(to: pt(q.x, q.y))
                ctx.stroke(path, with: .linearGradient(gradient([(spray.opacity(0), 0), (spray.opacity(0.75), 1)]),
                                                       startPoint: pt(q.x, q.y - length), endPoint: pt(q.x, q.y)),
                           style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            case .stream:
                // A smooth laminar stream, drawn along its velocity.
                let k = 0.028
                var path = Path()
                path.move(to: pt(q.x - q.vx * k, q.y - q.vy * k))
                path.addLine(to: pt(q.x, q.y))
                ctx.stroke(path, with: .color(spray.opacity(0.92)), style: StrokeStyle(lineWidth: 2.1, lineCap: .round))
            case .drop:
                // Pinched-off teardrop, stretched along its velocity.
                let speed = (q.vx * q.vx + q.vy * q.vy).squareRoot()
                let stretch = 1 + min(2.2, speed / 150)
                var layer = ctx
                layer.translateBy(x: q.x, y: q.y)
                layer.rotate(by: .radians(atan2(q.vy, q.vx) - .pi / 2))
                let rect = CGRect(x: -q.radius, y: -q.radius * stretch, width: q.radius * 2, height: q.radius * 2 * stretch)
                layer.fill(Path(ellipseIn: rect), with: .color(spray.opacity(0.95)))
                layer.fill(Path(ellipseIn: CGRect(x: -q.radius * 0.35, y: -q.radius * stretch * 0.7, width: q.radius * 0.45, height: q.radius * 0.8)),
                           with: .color(.white.opacity(0.7)))
            case .splash:
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - q.radius, y: q.y - q.radius, width: q.radius * 2, height: q.radius * 2)),
                         with: .color(spray.opacity(0.85 * fade)))
            }
        }
    }
}
