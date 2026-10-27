import SwiftUI

/// A glass track with a glowing gradient fill, a slider-style thumb riding its
/// leading edge, and a soft shine that sweeps across while work is underway.
struct GlassProgressBar: View {
    var value: Double
    var height: CGFloat = 8

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var clamped: Double { min(max(value, 0), 1) }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let thumb = height * 2
            let fill = max(height, width * clamped)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                    .frame(height: height)

                Capsule()
                    .fill(LinearGradient(colors: [Brand.sky, Brand.blue, Brand.violet],
                                         startPoint: .leading, endPoint: .trailing))
                    .overlay {
                        if !reduceMotion, clamped < 1 { Shine().clipShape(Capsule()) }
                    }
                    .frame(width: fill, height: height)
                    .shadow(color: Brand.sky.opacity(0.55), radius: height * 0.9)

                Thumb(size: thumb, pulsing: !reduceMotion && clamped < 1)
                    .offset(x: min(max(fill - thumb / 2, 0), width - thumb))
            }
            .frame(width: width, height: thumb)
            .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.82), value: clamped)
        }
        .frame(height: height * 2)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(clamped * 100)) percent")
    }

    /// A band of light sweeping left to right.
    private struct Shine: View {
        var body: some View {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let period = 1.6
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
                GeometryReader { geo in
                    let band = max(24, geo.size.width * 0.35)
                    LinearGradient(colors: [.clear, .white.opacity(0.55), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: band)
                        .offset(x: -band + phase * (geo.size.width + band))
                        .blendMode(.plusLighter)
                }
            }
        }
    }

    /// The slider knob: white glass with a glowing core that gently breathes.
    private struct Thumb: View {
        let size: CGFloat
        let pulsing: Bool
        @State private var breathe = false

        var body: some View {
            Circle()
                .fill(.white)
                .overlay(Circle().fill(Brand.sky).frame(width: size * 0.38, height: size * 0.38))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                .frame(width: size, height: size)
                .shadow(color: Brand.sky.opacity(breathe ? 0.95 : 0.45), radius: breathe ? 9 : 5)
                .scaleEffect(breathe ? 1.08 : 1)
                .onAppear {
                    guard pulsing else { return }
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { breathe = true }
                }
        }
    }
}
