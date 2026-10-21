import SwiftUI

/// "Burn the Evidence": the content chars, curls and burns away with rising
/// flames and embers, then calls `onFinished`. With Reduce Motion: a quick fade to black.
///
/// Set `isBurning` to true to start; set it back to false to restore the content.
/// The content keeps its identity (and state) throughout. The effect layers are
/// decorative: no hit testing, hidden from VoiceOver.
struct BurnEffect<Content: View>: View {
    private let isBurning: Bool
    private let onFinished: () -> Void
    private let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt: Date?
    @State private var finished = false
    @State private var blackout = 0.0

    init(isBurning: Bool, onFinished: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.isBurning = isBurning
        self.onFinished = onFinished
        self.content = content()
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: startedAt == nil || finished || reduceMotion)) { timeline in
            let elapsed = startedAt.map { timeline.date.timeIntervalSince($0) } ?? 0
            BurnFrame(progress: progress(elapsed: elapsed), time: elapsed, content: content)
        }
        .overlay {
            Color.black
                .opacity(blackout)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .allowsHitTesting(!isBurning)
        .accessibilityHidden(finished)
        .task(id: isBurning) { await run() }
    }

    private func progress(elapsed: Double) -> Double {
        if reduceMotion || startedAt == nil { return 0 }
        if finished { return 1 }
        return RevealFX.clamp01(elapsed / BurnTiming.duration)
    }

    private func run() async {
        guard isBurning else {
            startedAt = nil
            finished = false
            blackout = 0
            return
        }
        finished = false
        startedAt = .now
        if reduceMotion {
            withAnimation(.easeIn(duration: BurnTiming.reducedMotionDuration)) { blackout = 1 }
        }
        try? await Task.sleep(for: .seconds(reduceMotion ? BurnTiming.reducedMotionDuration + 0.05 : BurnTiming.duration))
        guard !Task.isCancelled else { return }
        finished = true
        onFinished()
    }
}

nonisolated enum BurnTiming {
    /// Seconds from striking the match to `onFinished`.
    static let duration = 2.7
    static let reducedMotionDuration = 0.35
}

/// The content at a given burn `progress` (0 = untouched, 1 = gone).
/// `time` is seconds since the burn started, for flicker.
struct BurnFrame<Content: View>: View {
    let progress: Double
    let time: Double
    let content: Content

    var body: some View {
        let p = progress
        let char = RevealFX.clamp01(p * 1.6)
        content
            .saturation(1 - 0.55 * char)
            .brightness(-0.1 * char)
            .colorMultiply(Color(red: 1, green: 1 - 0.2 * char, blue: 1 - 0.4 * char))
            .overlay {
                if p > 0 {
                    Canvas { context, size in
                        BurnPainter(progress: p, time: time, size: size).scorch(&context)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .mask {
                if p > 0 {
                    Canvas { context, size in
                        BurnPainter(progress: p, time: time, size: size).remaining(&context)
                    }
                } else {
                    Rectangle()
                }
            }
            .overlay {
                if p > 0 {
                    Canvas { context, size in
                        BurnPainter(progress: p, time: time, size: size).fire(&context)
                    } symbols: {
                        Text("🔥").font(.system(size: 40)).tag(BurnSymbol.flame)
                        Text("NOTHING TO SEE HERE")
                            .font(Theme.mono(.caption, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(Color(white: 0.85))
                            .tag(BurnSymbol.alibi)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .rotation3DEffect(
                .degrees(24 * p * p), axis: (x: 1, y: 0, z: 0),
                anchor: .top, perspective: 0.5
            )
            .scaleEffect(1 - 0.06 * p, anchor: .top)
    }
}

private nonisolated enum BurnSymbol: Hashable {
    case flame, alibi
}

private enum BurnPalette {
    static let charcoal = Color(red: 0.1, green: 0.05, blue: 0.02)
    static let ember = Color(red: 1.0, green: 0.45, blue: 0.08)
    static let hot = Color(red: 1.0, green: 0.85, blue: 0.35)
    static let ash = Color(red: 0.16, green: 0.13, blue: 0.11)
    static let charSoft = charcoal.opacity(0.6)
    static let charDeep = charcoal.opacity(0.9)
    static let toast = Gradient(colors: [charcoal.opacity(0), charcoal.opacity(0.35), charcoal.opacity(0.9)])
    static let smoke = Gradient(colors: [Color(white: 0.45).opacity(0.35), Color(white: 0.45).opacity(0)])
    static let glow = Gradient(colors: [ember.opacity(0), ember.opacity(0.35)])
}

/// Stateless burn drawing: the flame front is a wavy line rising from the
/// bottom; everything is a function of progress and time.
private struct BurnPainter {
    let p: Double
    let t: Double
    let w: CGFloat
    let h: CGFloat

    init(progress: Double, time: Double, size: CGSize) {
        p = progress
        t = time
        w = size.width
        h = size.height
    }

    /// Height of the flame front at `x`. Starts just below the bottom, ends above the top.
    private func front(_ x: Double, progress: Double, time: Double) -> Double {
        let base = (h + 40) - (h + 130) * progress
        let tilt = (x / max(w, 1) - 0.5) * 50 * (1 - progress)
        let wave = 13 * sin(x * 0.045 + time * 3.1) + 8 * sin(x * 0.12 - time * 4.7) + 6 * sin(x * 0.021 + 1.3)
        return base + tilt + wave
    }

    private func front(_ x: Double) -> Double { front(x, progress: p, time: t) }

    private func frontPath(closedAbove: Bool) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: -10, y: front(-10)))
        var x: CGFloat = -10
        while x < w + 10 {
            x = min(w + 10, x + 14)
            path.addLine(to: CGPoint(x: x, y: front(x)))
        }
        if closedAbove {
            path.addLine(to: CGPoint(x: w + 10, y: -400))
            path.addLine(to: CGPoint(x: -10, y: -400))
            path.closeSubpath()
        }
        return path
    }

    private var flameStrength: Double { RevealFX.prog(p, 0, 0.05) * (1 - RevealFX.prog(p, 0.9, 1.0)) }

    /// Mask: what hasn't burned yet.
    func remaining(_ ctx: inout GraphicsContext) {
        ctx.fill(frontPath(closedAbove: true), with: .color(.white))
    }

    /// Browning above the flame front (drawn under the mask, so it follows the edge).
    func scorch(_ ctx: inout GraphicsContext) {
        let mean = (h + 40) - (h + 130) * p
        ctx.fill(
            Path(CGRect(x: 0, y: mean - 140, width: w, height: 200)),
            with: .linearGradient(BurnPalette.toast, startPoint: CGPoint(x: 0, y: mean - 140), endPoint: CGPoint(x: 0, y: mean + 30))
        )
        let edge = frontPath(closedAbove: false)
        ctx.stroke(edge, with: .color(BurnPalette.charSoft), lineWidth: 46)
        ctx.stroke(edge, with: .color(BurnPalette.charDeep), lineWidth: 20)
    }

    /// Glowing edge, flames, embers, smoke and ash.
    func fire(_ ctx: inout GraphicsContext) {
        let strength = flameStrength
        guard strength > 0.004 else { return }
        let saved = ctx.opacity
        ctx.opacity = saved * strength

        // Heat glow just above the edge, then the burning edge itself.
        let mean = (h + 40) - (h + 130) * p
        ctx.fill(
            frontPath(closedAbove: true),
            with: .linearGradient(BurnPalette.glow, startPoint: CGPoint(x: 0, y: mean - 100), endPoint: CGPoint(x: 0, y: mean + 25))
        )
        let edge = frontPath(closedAbove: false)
        ctx.stroke(edge, with: .color(BurnPalette.ember), lineWidth: 7)
        ctx.stroke(edge, with: .color(BurnPalette.hot), lineWidth: 2.5)

        // Smoke drifts up behind the flames.
        for k in 0..<6 {
            let life = 1.6
            let phase = RevealFX.fract(t / life + RevealFX.rand(k, 201))
            let born = t - phase * life
            guard born > 0 else { continue }
            let x0 = RevealFX.rand(k &+ Int(born / life) &* 31, 202) * w
            ctx.revealBlob(
                x: x0 + sin(phase * 4 + Double(k)) * 18,
                y: front(x0, progress: born / BurnTiming.duration, time: born) - 20 - phase * life * 70,
                rx: 14 + phase * 42, ry: 14 + phase * 42,
                gradient: BurnPalette.smoke, opacity: 1 - phase
            )
        }

        // A row of flickering flames riding the edge.
        let flame = ctx.resolveSymbol(id: BurnSymbol.flame)
        let count = max(6, Int(w / 34))
        for k in 0..<count {
            let kd = Double(k)
            let x = (kd + 0.5) / Double(count) * w + sin(t * 2.1 + kd) * 5
            let flicker = 0.75 + 0.2 * sin(t * 13 + kd * 1.7) + 0.12 * sin(t * 21 + kd * 0.6)
            ctx.revealDraw(
                flame, x: x, y: front(x) + 10,
                scale: flicker * (0.8 + 0.4 * RevealFX.rand(k, 203)),
                scaleY: 1 + 0.12 * sin(t * 17 + kd),
                rotation: sin(t * 5 + kd) * 0.08,
                anchor: .bottom
            )
        }

        // Embers float up and wink out.
        for k in 0..<30 {
            let life = 1.1
            let phase = RevealFX.fract(t / life + RevealFX.rand(k, 204))
            let born = t - phase * life
            guard born > 0 else { continue }
            let x0 = RevealFX.rand(k &+ Int(born / life) &* 37, 205) * w
            let x = x0 + sin(phase * 6 + Double(k)) * 14
            let y = front(x0, progress: born / BurnTiming.duration, time: born) - phase * life * 150
            let radius = (1.6 + RevealFX.rand(k, 206) * 2.2) * (1 - 0.5 * phase)
            ctx.revealCircle(x: x, y: y, radius: radius * 3, color: BurnPalette.ember, opacity: 0.25 * (1 - phase))
            ctx.revealCircle(x: x, y: y, radius: radius, color: phase < 0.4 ? BurnPalette.hot : BurnPalette.ember, opacity: 1 - phase)
        }

        // Ash flakes flutter down into the burned-out space.
        let savedTransform = ctx.transform
        for k in 0..<10 {
            let life = 1.3
            let phase = RevealFX.fract(t / life + RevealFX.rand(k, 207))
            let born = t - phase * life
            guard born > 0 else { continue }
            let x0 = RevealFX.rand(k &+ Int(born / life) &* 41, 208) * w
            let y = front(x0, progress: born / BurnTiming.duration, time: born) + 12 + phase * life * 90
            ctx.transform = savedTransform
                .translatedBy(x: x0 + sin(phase * 5 + Double(k)) * 16, y: y)
                .rotated(by: phase * 6 + Double(k))
            ctx.opacity = saved * strength * (1 - phase)
            ctx.fill(Path(CGRect(x: -2, y: -3, width: 4, height: 6)), with: .color(BurnPalette.ash))
        }
        ctx.transform = savedTransform
        ctx.opacity = saved * strength

        // The scanner's official position on the matter.
        let alibi = RevealFX.prog(p, 0.4, 0.88)
        if alibi > 0, alibi < 1 {
            ctx.revealDraw(
                ctx.resolveSymbol(id: BurnSymbol.alibi),
                x: w / 2 + sin(t * 1.5) * 8, y: front(w / 2) - 60 - alibi * 70,
                rotation: -0.05, opacity: RevealFX.window(alibi, 0, 0.15, 0.75, 1)
            )
        }
        ctx.opacity = saved
    }
}

#if DEBUG
private struct BurnPlayground: View {
    @State private var burning = false
    @State private var burns = 0

    var body: some View {
        VStack(spacing: 16) {
            BurnEffect(isBurning: burning, onFinished: { burns += 1 }) {
                VStack(alignment: .leading, spacing: 12) {
                    Stamp()
                    SectionHeader(title: "CASE FILE 0042")
                    Text("SUBJECT IS A\nVAMPIRE")
                        .font(Theme.mono(.largeTitle, weight: .heavy))
                        .foregroundStyle(Theme.alert)
                    Text("Subject requested a garlic-free menu and avoided the window seat. Evidence is overwhelming and slightly embarrassing.")
                        .font(Theme.mono(.callout))
                        .foregroundStyle(Theme.neon)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .overlay(Rectangle().stroke(Theme.neon.opacity(0.7), lineWidth: 1.5))
            }
            Text("Evidence burned: \(burns)")
                .font(Theme.mono(.caption))
                .foregroundStyle(Theme.dimNeon)
            Button(burning ? "Restore evidence" : "Burn the Evidence") { burning.toggle() }
                .buttonStyle(NeonButtonStyle(color: burning ? Theme.neon : Theme.alert))
        }
        .padding(20)
        .crtScreen()
    }
}

#Preview("Burn the Evidence") {
    BurnPlayground()
        .preferredColorScheme(.dark)
}
#endif
