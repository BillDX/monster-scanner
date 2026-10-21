import MonsterCore
import SwiftUI

// MARK: - Public API

/// Full-screen overlay played when the verdict card appears.
///
/// Every verdict gets its own short, silly show: about 2.5 s of drama at up to
/// 60 fps, then a quiet ambient tail at 30 fps, then the timeline pauses on a
/// still (empty) frame — see `settleTime(for:)`. Werewolf keeps a faint moon
/// and Human keeps its stamp. With Reduce Motion it is a gentle fade-only version.
/// Purely decorative: no hit testing, hidden from VoiceOver.
struct MonsterRevealEffect: View {
    let monster: Monster
    /// Changes when the reveal replays (e.g. Second Opinion); restart the animation when it changes.
    var trigger: Int = 0
    /// Where the verdict card sits, in unit coordinates of the overlay.
    /// Bats burst from here, the UFO beams onto it, the stamp lands on it.
    var focus: UnitPoint = RevealScript.defaultFocus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                StillReveal(monster: monster, focus: focus)
            } else {
                AnimatedReveal(monster: monster, focus: focus, seed: trigger)
            }
        }
        .id(RevealRestartKey(monster: monster, trigger: trigger))
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Seconds after the effect starts at which something lands hard (kaiju
    /// stomps, the human stamp). Use these to fire haptics in sync.
    static func impactTimes(for monster: Monster) -> [Double] { RevealScript.impacts(monster) }

    /// Seconds of full-intensity animation.
    static func peakDuration(for monster: Monster) -> Double { RevealScript.peak(monster) }

    /// Seconds until the effect has settled and stops redrawing.
    static func settleTime(for monster: Monster) -> Double { RevealScript.total(monster) }
}

extension View {
    /// Screen-shake for big moments: one sharp, decaying shake of about
    /// `intensity` points each time `trigger` changes (not on first appearance).
    /// Does nothing with Reduce Motion.
    func revealShake(trigger: Int, intensity: CGFloat) -> some View {
        modifier(RevealShakeModifier(
            trigger: trigger,
            hits: [ShakeHit(at: 0, x: intensity, y: intensity * 0.7, duration: 0.42, frequency: 17, decay: 6)]
        ))
    }

    /// The shake that goes with `MonsterRevealEffect`, timed to its beats:
    /// three stomps for kaiju, a bump when the human stamp lands, a glitchy
    /// jitter for robot, a slow wobble for zombie, a float for ghost and a jolt
    /// for the vampire burst. Change `trigger` at the moment the effect starts.
    func revealShake(for monster: Monster, trigger: Int) -> some View {
        modifier(RevealShakeModifier(trigger: trigger, hits: ShakeHit.pattern(for: monster)))
    }
}

// MARK: - Script (timings and jokes)

nonisolated enum RevealScript {
    static let defaultFocus = UnitPoint(x: 0.5, y: 0.36)
    static let kaijuStomps: [Double] = [0.05, 0.6, 1.15]
    static let stampLands = 1.55

    /// Loud part, drawn at up to 60 fps.
    static func peak(_ monster: Monster) -> Double {
        switch monster {
        case .vampire: 2.6
        case .alien: 3.1
        case .kaiju: 2.6
        case .werewolf: 2.6
        case .zombie: 2.8
        case .robot: 2.4
        case .ghost: 2.8
        case .human: 2.2
        }
    }

    /// After this the frame is still and the timeline pauses.
    static func total(_ monster: Monster) -> Double {
        switch monster {
        case .vampire: 9
        case .alien: 7.5
        case .kaiju: 10
        case .werewolf: 7
        case .zombie: 9
        case .robot: 10
        case .ghost: 9
        case .human: 5.6
        }
    }

    static func impacts(_ monster: Monster) -> [Double] {
        switch monster {
        case .kaiju: kaijuStomps
        case .human: [stampLands]
        default: []
        }
    }

    static func captionStart(_ monster: Monster) -> Double {
        monster == .human ? 2.0 : 0.75
    }

    /// The scanner's deadpan one-liner, typed out near the bottom of the screen.
    static func caption(_ monster: Monster) -> String {
        switch monster {
        case .vampire: "RECOMMENDED SUNSCREEN: SPF 1,000,000"
        case .alien: "COW STATUS: BORROWED"
        case .kaiju: "SEISMIC READING: 9.8 (RUDE)"
        case .werewolf: "MOON STATUS: EXTREMELY FULL"
        case .zombie: "CRAVING: BRAINS. OR BRUNCH."
        case .robot: "FEELINGS.EXE: LOADING… 12%"
        case .ghost: "BOO! (SORRY. TOO LOUD?)"
        case .human: "THAT'S IT. THAT'S THE RESULT."
        }
    }

    /// Effects that also draw a light layer blended with `.screen` over the content.
    static func hasGlowPass(_ monster: Monster) -> Bool {
        switch monster {
        case .alien, .werewolf, .robot, .ghost: true
        default: false
        }
    }

    /// Effects with solid things that sit on top of their own light (the UFO and its cow).
    static func hasTopPass(_ monster: Monster) -> Bool {
        monster == .alien
    }

    /// Whether anything is left on screen once the effect has settled
    /// (the werewolf's moon, the human's stamp). Otherwise the overlay goes away entirely.
    static func keepsFinalFrame(_ monster: Monster) -> Bool {
        monster == .werewolf || monster == .human
    }

    /// Ghost only: how much the screen goes soft (a material blur) at time `t`.
    static func ghostHaze(_ t: Double) -> Double {
        0.7 * RevealFX.window(t, 0, 0.5, 1.6, 2.4)
    }
}

// MARK: - Players

private nonisolated struct RevealRestartKey: Hashable {
    let monster: Monster
    let trigger: Int
}

/// Plays the effect: 60 fps for the peak, 30 fps for the ambient tail, then paused.
private struct AnimatedReveal: View {
    let monster: Monster
    let focus: UnitPoint
    let seed: Int

    private enum Stage { case peak, ambient, done }

    @State private var start = Date.now
    @State private var stage = Stage.peak

    var body: some View {
        let total = RevealScript.total(monster)
        Group {
            if stage == .done, !RevealScript.keepsFinalFrame(monster) {
                Color.clear
            } else {
                TimelineView(.animation(minimumInterval: stage == .peak ? 1.0 / 60 : 1.0 / 30, paused: stage == .done)) { timeline in
                    RevealFrame(
                        monster: monster,
                        time: stage == .done ? total : timeline.date.timeIntervalSince(start),
                        focus: focus,
                        seed: seed
                    )
                }
            }
        }
        .task {
            let peak = RevealScript.peak(monster)
            try? await Task.sleep(for: .seconds(peak))
            guard !Task.isCancelled else { return }
            stage = .ambient
            try? await Task.sleep(for: .seconds(total - peak))
            guard !Task.isCancelled else { return }
            stage = .done
        }
    }
}

/// One frame of a reveal effect at `time` seconds. Used by the player, and
/// handy for previews and snapshot checks.
struct RevealFrame: View {
    let monster: Monster
    let time: Double
    var focus: UnitPoint = RevealScript.defaultFocus
    var seed: Int = 0

    var body: some View {
        let t = min(max(time, 0), RevealScript.total(monster))
        ZStack {
            if monster == .ghost, RevealScript.ghostHaze(t) > 0.001 {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(RevealScript.ghostHaze(t))
            }
            Canvas { context, size in
                RevealPainter(monster: monster, t: t, size: size, focus: focus, seed: seed)
                    .paint(&context, pass: .base)
            } symbols: {
                RevealSymbols.views(for: monster)
            }
            if RevealScript.hasGlowPass(monster) {
                Canvas { context, size in
                    RevealPainter(monster: monster, t: t, size: size, focus: focus, seed: seed)
                        .paint(&context, pass: .glow)
                } symbols: {
                    RevealSymbols.views(for: monster)
                }
                .blendMode(.screen)
            }
            if RevealScript.hasTopPass(monster) {
                Canvas { context, size in
                    RevealPainter(monster: monster, t: t, size: size, focus: focus, seed: seed)
                        .paint(&context, pass: .top)
                } symbols: {
                    RevealSymbols.views(for: monster)
                }
            }
        }
    }
}

/// Reduce Motion: a still picture that fades in, then fades away (or, for
/// werewolf and human, rests quietly).
private struct StillReveal: View {
    let monster: Monster
    let focus: UnitPoint

    @State private var flourish = 0.0
    @State private var resting = 0.0

    var body: some View {
        RevealStillFrame(monster: monster, focus: focus, flourish: flourish, resting: resting)
            .task {
                withAnimation(.easeInOut(duration: 0.6)) {
                    flourish = 1
                    resting = 1
                }
                try? await Task.sleep(for: .seconds(2.8))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.8)) { flourish = 0 }
            }
    }
}

/// The Reduce Motion picture: a `flourish` layer that comes and goes and a
/// `resting` layer that stays (moon, stamp). Opacities are animatable.
struct RevealStillFrame: View {
    let monster: Monster
    var focus: UnitPoint = RevealScript.defaultFocus
    var flourish: Double = 1
    var resting: Double = 1

    var body: some View {
        ZStack {
            Canvas { context, size in
                RevealPainter(monster: monster, t: 0, size: size, focus: focus, seed: 0)
                    .paintStill(&context, layer: .resting, pass: .base)
            } symbols: {
                RevealSymbols.views(for: monster)
            }
            .opacity(resting)
            if RevealScript.hasGlowPass(monster) {
                Canvas { context, size in
                    RevealPainter(monster: monster, t: 0, size: size, focus: focus, seed: 0)
                        .paintStill(&context, layer: .resting, pass: .glow)
                } symbols: {
                    RevealSymbols.views(for: monster)
                }
                .blendMode(.screen)
                .opacity(resting)
            }
            Canvas { context, size in
                RevealPainter(monster: monster, t: 0, size: size, focus: focus, seed: 0)
                    .paintStill(&context, layer: .flourish, pass: .base)
            } symbols: {
                RevealSymbols.views(for: monster)
            }
            .opacity(flourish)
        }
    }
}

// MARK: - Shake

private nonisolated struct ShakeHit: Sendable {
    /// Seconds after the trigger.
    var at: Double
    /// Peak amplitude in points.
    var x: CGFloat
    var y: CGFloat
    var duration: Double = 0.45
    var frequency: Double = 16
    var decay: Double = 6

    static func pattern(for monster: Monster) -> [ShakeHit] {
        switch monster {
        case .kaiju:
            zip(RevealScript.kaijuStomps, [10.0, 13.0, 18.0]).map { time, amp in
                ShakeHit(at: time, x: amp * 0.45, y: amp, duration: 0.5, frequency: 13, decay: 6)
            }
        case .human:
            [ShakeHit(at: RevealScript.stampLands, x: 3, y: 6, duration: 0.3, frequency: 20, decay: 9)]
        case .robot:
            [0.08, 0.5, 0.95, 1.6].map { ShakeHit(at: $0, x: 7, y: 0, duration: 0.16, frequency: 32, decay: 4) }
        case .vampire:
            [ShakeHit(at: 0, x: 4, y: 3, duration: 0.35, frequency: 18, decay: 8)]
        case .zombie:
            [ShakeHit(at: 0.2, x: 5, y: 1.5, duration: 2.6, frequency: 0.85, decay: 0.3)]
        case .ghost:
            [ShakeHit(at: 0, x: 1.5, y: 7, duration: 2.8, frequency: 0.7, decay: 0.2)]
        case .alien, .werewolf:
            []
        }
    }

    static func offset(at clock: Double, hits: [ShakeHit]) -> CGSize {
        var dx = 0.0
        var dy = 0.0
        for hit in hits {
            let tau = clock - hit.at
            guard tau > 0, tau < hit.duration else { continue }
            let envelope = exp(-hit.decay * tau) * (1 - tau / hit.duration)
            let phase = 2 * Double.pi * hit.frequency * tau
            dx += Double(hit.x) * envelope * sin(phase)
            dy += Double(hit.y) * envelope * sin(phase * 0.77)
        }
        return CGSize(width: dx, height: dy)
    }
}

private struct RevealShakeModifier: ViewModifier {
    let trigger: Int
    let hits: [ShakeHit]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let hits = reduceMotion ? [] : hits
        let length = hits.map { $0.at + $0.duration }.max() ?? 0
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, clock in
            view.offset(ShakeHit.offset(at: clock, hits: hits))
        } keyframes: { _ in
            KeyframeTrack {
                MoveKeyframe(0.0)
                LinearKeyframe(length, duration: length)
            }
        }
    }
}

// MARK: - Shared drawing helpers (also used by BurnEffect)

nonisolated enum RevealFX {
    static func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }
    /// 0 before `a`, 1 after `b`, linear in between.
    static func prog(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp01((t - a) / (b - a)) }
    /// Fades in over `a…b`, out over `c…d`.
    static func window(_ t: Double, _ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
        prog(t, a, b) * (1 - prog(t, c, d))
    }
    static func lerp(_ a: Double, _ b: Double, _ x: Double) -> Double { a + (b - a) * x }
    static func fract(_ x: Double) -> Double { x - x.rounded(.down) }
    static func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
    static func easeIn(_ x: Double) -> Double { x * x * x }
    static func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
    static func easeOutBack(_ x: Double) -> Double {
        let c1 = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    /// Cheap stateless random number in 0..<1 (splitmix64), so particles need no storage.
    static func rand(_ i: Int, _ salt: Int) -> Double {
        var z = UInt64(truncatingIfNeeded: i &* 0x2545_F491 &+ salt &* 0x9E37_79B9 &+ 0x632B_E59B_D9B4_E019)
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) * 0x1.0p-53
    }

    /// Height of something dropped from `top` onto `floor`, with one bounce.
    static func drop(_ tau: Double, from top: Double, to floor: Double, gravity: Double, restitution: Double)
        -> (y: Double, landed: Double, settled: Double) {
        let fallTime = (2 * max(floor - top, 1) / gravity).squareRoot()
        let bounceSpeed = gravity * fallTime * restitution
        let bounceTime = 2 * bounceSpeed / gravity
        if tau < fallTime { return (top + 0.5 * gravity * tau * tau, fallTime, fallTime + bounceTime) }
        let b = tau - fallTime
        if b < bounceTime { return (floor - (bounceSpeed * b - 0.5 * gravity * b * b), fallTime, fallTime + bounceTime) }
        return (floor, fallTime, fallTime + bounceTime)
    }

    static let unitCircle = Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2))
}

extension GraphicsContext {
    /// Draws a Canvas symbol at a point with scale, rotation and opacity,
    /// restoring the context afterwards (no context copies).
    mutating func revealDraw(
        _ symbol: ResolvedSymbol?, x: CGFloat, y: CGFloat,
        scale: CGFloat = 1, scaleY: CGFloat = 1, rotation: Double = 0,
        opacity: Double = 1, flip: Bool = false, anchor: UnitPoint = .center
    ) {
        guard let symbol, opacity > 0.004, scale > 0.01 else { return }
        let savedTransform = transform
        let savedOpacity = self.opacity
        transform = savedTransform
            .translatedBy(x: x, y: y)
            .rotated(by: rotation)
            .scaledBy(x: flip ? -scale : scale, y: scale * scaleY)
        self.opacity = savedOpacity * opacity
        draw(symbol, at: .zero, anchor: anchor)
        transform = savedTransform
        self.opacity = savedOpacity
    }

    /// A soft radial blob (fog, dust, mist, glow) stretched to `rx` × `ry`.
    mutating func revealBlob(x: CGFloat, y: CGFloat, rx: CGFloat, ry: CGFloat, gradient: Gradient, opacity: Double) {
        guard opacity > 0.004, rx > 0.5, ry > 0.5 else { return }
        let savedTransform = transform
        let savedOpacity = self.opacity
        transform = savedTransform.translatedBy(x: x, y: y).scaledBy(x: rx, y: ry)
        self.opacity = savedOpacity * opacity
        fill(RevealFX.unitCircle, with: .radialGradient(gradient, center: .zero, startRadius: 0, endRadius: 1))
        transform = savedTransform
        self.opacity = savedOpacity
    }

    mutating func revealCircle(x: CGFloat, y: CGFloat, radius: CGFloat, color: Color, opacity: Double) {
        guard opacity > 0.004 else { return }
        let savedOpacity = self.opacity
        self.opacity = savedOpacity * opacity
        fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
        self.opacity = savedOpacity
    }
}

// MARK: - Symbols

private nonisolated enum RevealSymbol: Hashable {
    case bat, ufo, sparkle, cow, moo
    case building(Int), dino, tinyStomp, stompWord(Int)
    case paw, awoo
    case brain, hand
    case robotText(Int)
    case ghost, boo
    case popper, pfft, cricket, chirp, stamp
    case caption
}

private enum RevealSymbols {
    static let robotLines = ["BEEP", "BOOP", "BEEP BOOP", "01001000 01001001", "DOES NOT COMPUTE", "*WHIRR*"]
    static let stompWords = ["STOMP", "STOMP!", "STOMP!!"]

    @ViewBuilder
    static func views(for monster: Monster) -> some View {
        switch monster {
        case .vampire:
            emoji("🦇", 44).tag(RevealSymbol.bat)
        case .alien:
            emoji("🛸", 96).tag(RevealSymbol.ufo)
            emoji("✨", 26).tag(RevealSymbol.sparkle)
            emoji("🐄", 40).tag(RevealSymbol.cow)
            bubble("moo?").tag(RevealSymbol.moo)
        case .kaiju:
            emoji("🏢", 44).tag(RevealSymbol.building(0))
            emoji("🏠", 40).tag(RevealSymbol.building(1))
            emoji("🏬", 44).tag(RevealSymbol.building(2))
            emoji("🏪", 40).tag(RevealSymbol.building(3))
            emoji("🏡", 40).tag(RevealSymbol.building(4))
            emoji("🦖", 34).tag(RevealSymbol.dino)
            ForEach(stompWords.indices, id: \.self) { index in
                Text(stompWords[index])
                    .font(.system(size: 44, weight: .black, design: .monospaced))
                    .foregroundStyle(RevealPalette.yellow)
                    .shadow(color: Theme.alert, radius: 0, x: 3, y: 3)
                    .tag(RevealSymbol.stompWord(index))
            }
            whisper("stomp.").tag(RevealSymbol.tinyStomp)
        case .werewolf:
            emoji("🐾", 30).tag(RevealSymbol.paw)
            Text("AWOOOOO!")
                .font(Theme.mono(.title2, weight: .heavy))
                .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.75))
                .tag(RevealSymbol.awoo)
        case .zombie:
            emoji("🧠", 40).tag(RevealSymbol.brain)
            emoji("🖐️", 46).tag(RevealSymbol.hand)
        case .robot:
            ForEach(robotLines.indices, id: \.self) { index in
                Text(robotLines[index])
                    .font(Theme.mono(index < 3 ? .title2 : .headline, weight: .heavy))
                    .foregroundStyle(Theme.neon)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.75))
                    .overlay(Rectangle().stroke(Theme.neon.opacity(0.7), lineWidth: 1))
                    .tag(RevealSymbol.robotText(index))
            }
        case .ghost:
            emoji("👻", 56).tag(RevealSymbol.ghost)
            bubble("boo?").tag(RevealSymbol.boo)
        case .human:
            emoji("🎉", 40).tag(RevealSymbol.popper)
            bubble("pfft.").tag(RevealSymbol.pfft)
            emoji("🦗", 26).tag(RevealSymbol.cricket)
            whisper("chirp").tag(RevealSymbol.chirp)
            Stamp(text: "CERTIFIED HUMAN").tag(RevealSymbol.stamp)
        }
        Text("> " + RevealScript.caption(monster))
            .font(Theme.mono(.footnote, weight: .bold))
            .foregroundStyle(Theme.neon)
            .lineLimit(1)
            .fixedSize()
            .tag(RevealSymbol.caption)
    }

    private static func emoji(_ glyph: String, _ size: CGFloat) -> some View {
        Text(glyph).font(.system(size: size))
    }

    /// A tiny white speech bubble for asides ("moo?", "boo?", "pfft.").
    private static func bubble(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(.caption, weight: .bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.92)))
    }

    private static func whisper(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(.caption, weight: .bold))
            .foregroundStyle(Theme.dimNeon)
    }
}

// MARK: - Palette

private enum RevealPalette {
    static let crimson = Color(red: 0.32, green: 0, blue: 0.06)
    static let night = Color(red: 0.01, green: 0.02, blue: 0.10)
    static let fog = Color(red: 0.40, green: 0.82, blue: 0.30)
    static let dust = Color(red: 0.62, green: 0.56, blue: 0.46)
    static let cyan = Color(red: 0.15, green: 0.9, blue: 1.0)
    static let magenta = Color(red: 1.0, green: 0.15, blue: 0.35)
    static let yellow = Color(red: 1.0, green: 0.88, blue: 0.2)
    static let crater = Color(red: 0.72, green: 0.68, blue: 0.52)
    static let neonFaint = Theme.neon.opacity(0.14)
    static let neonHalo = Theme.neon.opacity(0.3)
    static let captionFill = Color.black.opacity(0.85)
    static let confetti: [Color] = [Theme.neon, Theme.alert, Theme.uvGlow, yellow, cyan]

    static let crimsonVignette = Gradient(stops: [
        .init(color: crimson.opacity(0), location: 0.45),
        .init(color: crimson.opacity(0.9), location: 1),
    ])
    static let greenVignette = Gradient(stops: [
        .init(color: fog.opacity(0), location: 0.5),
        .init(color: Color(red: 0.05, green: 0.25, blue: 0.04).opacity(0.8), location: 1),
    ])
    static let fogBlob = Gradient(colors: [fog.opacity(0.55), fog.opacity(0.22), fog.opacity(0)])
    static let dustBlob = Gradient(colors: [dust.opacity(0.7), dust.opacity(0)])
    static let mistBlob = Gradient(colors: [Color.white.opacity(0.24), Color.white.opacity(0)])
    static let moonHalo = Gradient(stops: [
        .init(color: Color(red: 1, green: 0.95, blue: 0.75).opacity(0.55), location: 0.35),
        .init(color: Color(red: 1, green: 0.9, blue: 0.6).opacity(0.16), location: 0.6),
        .init(color: Color(red: 1, green: 0.9, blue: 0.6).opacity(0), location: 1),
    ])
    static let moonFace = Gradient(colors: [
        Color(red: 1, green: 0.98, blue: 0.88), Color(red: 0.93, green: 0.88, blue: 0.68),
    ])
    static let beam = Gradient(colors: [Theme.neon.opacity(0.65), Theme.neon.opacity(0.1)])
    static let refreshBar = Gradient(colors: [Theme.neon.opacity(0), Theme.neon.opacity(0.14), Theme.neon.opacity(0)])
}

/// Unit gear (radius 1) with a hole; drawn with even-odd fill.
private let revealGearPath: Path = {
    var path = Path()
    let teeth = 10
    let step = 2 * Double.pi / Double(teeth)
    var points: [CGPoint] = []
    for k in 0..<teeth {
        let a = Double(k) * step
        for (offset, radius) in [(-0.5, 0.78), (-0.24, 0.78), (-0.15, 1.0), (0.15, 1.0), (0.24, 0.78)] {
            let angle = a + offset * step
            points.append(CGPoint(x: cos(angle) * radius, y: sin(angle) * radius))
        }
    }
    path.addLines(points)
    path.closeSubpath()
    path.addEllipse(in: CGRect(x: -0.3, y: -0.3, width: 0.6, height: 0.6))
    return path
}()

// MARK: - Painter

/// Draws one frame of one effect. Stateless: everything is a function of `t`,
/// with particle randomness from a hash, so nothing is allocated per particle.
private struct RevealPainter {
    /// `base` is drawn normally, `glow` is blended with `.screen` (light), `top` sits above both.
    enum Pass { case base, glow, top }
    enum StillLayer { case flourish, resting }

    let monster: Monster
    let t: Double
    let w: CGFloat
    let h: CGFloat
    let focus: CGPoint
    let seed: Int

    init(monster: Monster, t: Double, size: CGSize, focus: UnitPoint, seed: Int) {
        self.monster = monster
        self.t = t
        self.w = size.width
        self.h = size.height
        self.focus = CGPoint(x: focus.x * size.width, y: focus.y * size.height)
        self.seed = seed
    }

    private var total: Double { RevealScript.total(monster) }

    private func rand(_ i: Int, _ salt: Int) -> Double {
        RevealFX.rand(i, salt &+ seed &* 7919)
    }

    func paint(_ ctx: inout GraphicsContext, pass: Pass) {
        switch monster {
        case .vampire: vampire(&ctx, pass)
        case .alien: alien(&ctx, pass)
        case .kaiju: kaiju(&ctx, pass)
        case .werewolf: werewolf(&ctx, pass)
        case .zombie: zombie(&ctx, pass)
        case .robot: robot(&ctx, pass)
        case .ghost: ghost(&ctx, pass)
        case .human: human(&ctx, pass)
        }
        if pass == .base {
            caption(&ctx, local: t - RevealScript.captionStart(monster), cursor: true)
        }
    }

    // MARK: Common bits

    private func fillScreen(_ ctx: inout GraphicsContext, _ color: Color, opacity: Double) {
        guard opacity > 0.004 else { return }
        let saved = ctx.opacity
        ctx.opacity = saved * opacity
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: h)), with: .color(color))
        ctx.opacity = saved
    }

    private func vignette(_ ctx: inout GraphicsContext, _ gradient: Gradient, opacity: Double) {
        guard opacity > 0.004 else { return }
        let saved = ctx.opacity
        ctx.opacity = saved * opacity
        ctx.fill(
            Path(CGRect(x: 0, y: 0, width: w, height: h)),
            with: .radialGradient(gradient, center: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endRadius: hypot(w, h) / 2)
        )
        ctx.opacity = saved
    }

    /// "> SEISMIC READING: 9.8 (RUDE)" typed into a little terminal box.
    private func caption(_ ctx: inout GraphicsContext, local: Double, cursor: Bool) {
        guard local > 0, local < 3.4, let text = ctx.resolveSymbol(id: RevealSymbol.caption) else { return }
        let opacity = RevealFX.prog(local, 0, 0.12) * (1 - RevealFX.prog(local, 3.0, 3.4))
        let size = text.size
        let center = CGPoint(x: w / 2 - 4, y: h * 0.86)
        let box = CGRect(
            x: center.x - size.width / 2 - 12, y: center.y - size.height / 2 - 6,
            width: size.width + 32, height: size.height + 12
        )
        let saved = ctx.opacity
        ctx.opacity = saved * opacity
        ctx.fill(Path(box), with: .color(RevealPalette.captionFill))
        ctx.stroke(Path(box), with: .color(Theme.neon), lineWidth: 1.5)
        let characters = Double(RevealScript.caption(monster).count + 2)
        let typed = (RevealFX.prog(local, 0.1, 1.0) * characters).rounded(.down) / characters
        let textLeft = center.x - size.width / 2
        var clipped = ctx
        clipped.clip(to: Path(CGRect(x: textLeft, y: box.minY, width: size.width * typed, height: box.height)))
        clipped.draw(text, at: center, anchor: .center)
        if cursor, typed < 1 || Int(local * 2.5) % 2 == 0 {
            let caret = CGRect(x: textLeft + size.width * typed + 1, y: center.y - size.height * 0.4, width: 7, height: size.height * 0.8)
            ctx.fill(Path(caret), with: .color(Theme.neon))
        }
        ctx.opacity = saved
    }

    // MARK: Vampire — bat burst, red flash, lazy circling stragglers

    private func vampire(_ ctx: inout GraphicsContext, _ pass: Pass) {
        guard pass == .base else { return }
        let flash = t < 0.05 ? t / 0.05 : 1 - RevealFX.prog(t, 0.05, 0.5)
        fillScreen(&ctx, Theme.alert, opacity: 0.42 * flash)
        vignette(&ctx, RevealPalette.crimsonVignette, opacity: RevealFX.window(t, 0, 0.3, 2.2, 3.4))

        let bat = ctx.resolveSymbol(id: RevealSymbol.bat)
        let count = 34
        for i in 0..<count {
            let delay = rand(i, 1) * 0.35
            let life = 1.3 + rand(i, 2) * 0.6
            let a = (t - delay) / life
            guard a > 0, a < 1 else { continue }
            let angle = (Double(i) + rand(i, 3) * 0.9) / Double(count) * 2 * .pi
            let reach = (0.6 + rand(i, 4) * 0.5) * Double(max(w, h))
            let distance = 26 * RevealFX.easeOut(min(1, a * 5)) + reach * a * a
            let swoop = sin(a * .pi) * (rand(i, 5) - 0.5) * 240
            let dx = cos(angle)
            let dy = sin(angle)
            ctx.revealDraw(
                bat,
                x: focus.x + dx * distance - dy * swoop,
                y: focus.y + dy * distance + dx * swoop - 70 * a,
                scale: (0.3 + 1.3 * a) * (0.75 + 0.5 * rand(i, 6)),
                scaleY: 0.5 + 0.5 * abs(sin(t * 26 + Double(i))),
                rotation: dx * 0.3,
                opacity: min(1, a * 12),
                flip: dx > 0
            )
        }

        for k in 0..<3 {
            let kd = Double(k)
            let opacity = RevealFX.prog(t, 1.6 + kd * 0.35, 2.2 + kd * 0.35) * (1 - RevealFX.prog(t, total - 1.8, total - 0.3))
            guard opacity > 0 else { continue }
            let angle = t * (0.85 + 0.22 * kd) + kd * 2.2
            let depth = 0.5 + 0.5 * sin(angle)
            ctx.revealDraw(
                bat,
                x: focus.x + cos(angle) * w * (0.40 + 0.03 * kd),
                y: focus.y - h * 0.02 + sin(angle) * h * (0.20 + 0.02 * kd),
                scale: 0.45 + 0.2 * depth,
                scaleY: 0.55 + 0.45 * abs(sin(t * 11 + kd)),
                rotation: -cos(angle) * 0.2,
                opacity: opacity,
                flip: sin(angle) < 0
            )
        }
    }

    // MARK: Alien — UFO, tractor beam, an abducted cow, zip!

    private func ufoPose(_ time: Double) -> (x: CGFloat, y: CGFloat, tilt: Double) {
        let hoverY = max(focus.y - h * 0.24, 96)
        let arrive = RevealFX.easeOutBack(RevealFX.prog(time, 0, 0.9))
        let leave = RevealFX.easeIn(RevealFX.prog(time, 2.55, 3.05))
        let x = w / 2 + sin(time * 1.7) * 10 + leave * w * 0.85
        let y = RevealFX.lerp(-90, hoverY, arrive) + sin(time * 3.1) * 5 - leave * (hoverY + 170)
        return (x, y, sin(time * 2.3) * 0.07 - leave * 0.45)
    }

    private func alien(_ ctx: inout GraphicsContext, _ pass: Pass) {
        let ufo = ufoPose(t)
        let beam = RevealFX.easeOut(RevealFX.prog(t, 0.75, 1.05)) * (1 - RevealFX.easeIn(RevealFX.prog(t, 2.2, 2.5)))
        let top = ufo.y + 26
        let bottom = top + (focus.y + h * 0.13 - top) * beam
        let topHalf: CGFloat = 22
        let bottomHalf = topHalf + (w * 0.31 - topHalf) * beam
        let beamX = ufo.x

        switch pass {
        case .glow:
            if beam > 0.01 {
                let pulse = 0.78 + 0.22 * sin(t * 15)
                fillScreen(&ctx, Theme.neon, opacity: 0.09 * beam * pulse)
                var cone = Path()
                cone.move(to: CGPoint(x: beamX - topHalf, y: top))
                cone.addLine(to: CGPoint(x: beamX + topHalf, y: top))
                cone.addLine(to: CGPoint(x: beamX + bottomHalf, y: bottom))
                cone.addLine(to: CGPoint(x: beamX - bottomHalf, y: bottom))
                cone.closeSubpath()
                let saved = ctx.opacity
                ctx.opacity = saved * beam * pulse
                ctx.fill(cone, with: .linearGradient(
                    RevealPalette.beam, startPoint: CGPoint(x: beamX, y: top), endPoint: CGPoint(x: beamX, y: bottom)
                ))
                ctx.opacity = saved
                for k in 0..<4 {
                    let phase = RevealFX.fract(t * 1.1 + Double(k) / 4)
                    let y = bottom - phase * (bottom - top)
                    let half = RevealFX.lerp(bottomHalf, topHalf, phase)
                    ctx.opacity = saved * beam * (1 - phase) * 0.8
                    ctx.stroke(
                        Path(ellipseIn: CGRect(x: beamX - half, y: y - half * 0.12, width: half * 2, height: half * 0.24)),
                        with: .color(Theme.neon), lineWidth: 2
                    )
                }
                ctx.opacity = saved
                let sparkle = ctx.resolveSymbol(id: RevealSymbol.sparkle)
                for k in 0..<10 {
                    let phase = RevealFX.fract(t * 0.55 + rand(k, 11))
                    let y = bottom - phase * (bottom - top)
                    let half = RevealFX.lerp(bottomHalf, topHalf, phase)
                    ctx.revealDraw(
                        sparkle,
                        x: beamX + (rand(k, 12) * 2 - 1) * half * 0.8, y: y,
                        scale: 0.45 + 0.45 * abs(sin(t * 5 + Double(k))),
                        rotation: t * 2 + Double(k),
                        opacity: beam * sin(phase * .pi)
                    )
                }
            }
            // Leftover twinkles around the card.
            let sparkle = ctx.resolveSymbol(id: RevealSymbol.sparkle)
            for k in 0..<7 {
                let kd = Double(k)
                let opacity = RevealFX.window(t, 2.6 + kd * 0.15, 3.0 + kd * 0.15, total - 1.6, total - 0.2)
                guard opacity > 0 else { continue }
                let angle = kd / 7 * 2 * .pi + 0.4
                let twinkle = 0.5 + 0.5 * sin(t * 2.6 + kd * 1.7)
                ctx.revealDraw(
                    sparkle,
                    x: focus.x + cos(angle) * w * 0.42, y: focus.y + sin(angle) * h * 0.21,
                    scale: 0.35 + 0.35 * twinkle, opacity: opacity * twinkle * twinkle
                )
            }
        case .base:
            break
        case .top:
            let abduct = RevealFX.prog(t, 1.05, 2.25)
            if abduct > 0, abduct < 1 {
                let y = RevealFX.lerp(focus.y + h * 0.13 - 22, top + 18, RevealFX.easeInOut(abduct))
                let x = beamX + sin(abduct * 7) * 12
                let opacity = min(1, abduct * 8) * (abduct > 0.88 ? (1 - abduct) / 0.12 : 1)
                ctx.revealDraw(
                    ctx.resolveSymbol(id: RevealSymbol.cow), x: x, y: y,
                    scale: 1.3 - 0.75 * abduct, rotation: abduct * .pi * 1.5, opacity: opacity
                )
                ctx.revealDraw(
                    ctx.resolveSymbol(id: RevealSymbol.moo), x: x + 42, y: y - 24,
                    opacity: RevealFX.window(abduct, 0.1, 0.18, 0.5, 0.6)
                )
            }
            let saucer = ctx.resolveSymbol(id: RevealSymbol.ufo)
            if t > 2.55 {
                for k in 1...3 {
                    let ghost = ufoPose(t - Double(k) * 0.035)
                    ctx.revealDraw(saucer, x: ghost.x, y: ghost.y, rotation: ghost.tilt, opacity: 0.3 / Double(k))
                }
            }
            ctx.revealDraw(saucer, x: ufo.x, y: ufo.y, rotation: ufo.tilt)
        }
    }

    // MARK: Kaiju — stomp, stomp, STOMP; toy buildings tumble; a tiny dino strolls by

    /// (unit x, unit y, tilt, scale) for each comic-book STOMP.
    private static let stompWordSpots: [(CGFloat, CGFloat, Double, CGFloat)] = [
        (0.28, 0.58, -0.15, 0.8), (0.72, 0.64, 0.12, 0.95), (0.5, 0.71, -0.06, 1.25),
    ]

    private func kaiju(_ ctx: inout GraphicsContext, _ pass: Pass) {
        guard pass == .base else { return }
        for (k, stomp) in RevealScript.kaijuStomps.enumerated() {
            let dt = t - stomp
            guard dt > 0, dt < 0.65 else { continue }
            let (x, y, tilt, scale) = Self.stompWordSpots[k]
            let settle = RevealFX.easeOut(RevealFX.prog(dt, 0, 0.12))
            ctx.revealDraw(
                ctx.resolveSymbol(id: RevealSymbol.stompWord(k)),
                x: x * w + sin(dt * 90) * 3 * (1 - RevealFX.prog(dt, 0, 0.3)), y: y * h,
                scale: scale * (1 + 0.6 * (1 - settle)), rotation: tilt,
                opacity: RevealFX.prog(dt, 0, 0.04) * (1 - RevealFX.prog(dt, 0.45, 0.65))
            )
        }
        for (k, stomp) in RevealScript.kaijuStomps.enumerated() {
            let dt = t - stomp
            guard dt >= 0, dt < 1 else { continue }
            let strength = 0.6 + 0.2 * Double(k)
            if dt < 0.2 { fillScreen(&ctx, .black, opacity: 0.3 * strength * (1 - dt / 0.2)) }
            let a = RevealFX.easeOut(dt)
            for j in 0..<6 {
                let n = j + k * 10
                let radius = (22 + 62 * a) * strength * (0.8 + 0.4 * rand(n, 22))
                ctx.revealBlob(
                    x: (Double(j) + 0.5) / 6 * w + (rand(n, 21) - 0.5) * 40,
                    y: h - 8 - 36 * a,
                    rx: radius * 1.3, ry: radius * 0.8,
                    gradient: RevealPalette.dustBlob, opacity: 0.8 * (1 - dt)
                )
            }
        }

        let fade = 1 - RevealFX.prog(t, 3.3, 4.0)
        if fade > 0 {
            for i in 0..<10 {
                let tau = t - (0.12 + Double(i) * 0.15 + rand(i, 31) * 0.08)
                guard tau > 0 else { continue }
                let x = (0.07 + 0.86 * rand(i, 32)) * w
                let floor = h - 34 - rand(i, 33) * 28
                let fall = RevealFX.drop(tau, from: -44, to: floor, gravity: 2600, restitution: 0.32)
                ctx.revealDraw(
                    ctx.resolveSymbol(id: RevealSymbol.building(i % 5)),
                    x: x, y: fall.y,
                    scale: 0.95 + 0.4 * rand(i, 35),
                    rotation: (rand(i, 34) - 0.5) * 9 * min(tau, fall.settled),
                    opacity: fade
                )
                let sinceLanding = tau - fall.landed
                if sinceLanding > 0, sinceLanding < 0.5 {
                    let r = 10 + 26 * RevealFX.easeOut(sinceLanding / 0.5)
                    ctx.revealBlob(
                        x: x, y: floor + 14, rx: r * 1.4, ry: r * 0.6,
                        gradient: RevealPalette.dustBlob, opacity: 0.7 * (1 - sinceLanding / 0.5)
                    )
                }
            }
        }

        let walk = RevealFX.prog(t, 3.0, total - 0.4)
        if walk > 0, walk < 1 {
            let steps = walk * 18
            let stepPhase = RevealFX.fract(steps)
            let x = RevealFX.lerp(-30, w + 30, walk)
            let y = h * 0.935 - abs(sin(stepPhase * .pi)) * 7
            let opacity = RevealFX.window(walk, 0, 0.04, 0.96, 1)
            ctx.revealDraw(
                ctx.resolveSymbol(id: RevealSymbol.dino), x: x, y: y,
                rotation: sin(steps * .pi) * 0.08, opacity: opacity, flip: true
            )
            if Int(steps) % 2 == 0, stepPhase < 0.45 {
                ctx.revealDraw(
                    ctx.resolveSymbol(id: RevealSymbol.tinyStomp), x: x + 6, y: y - 30,
                    opacity: opacity * (1 - stepPhase / 0.45)
                )
            }
        }
    }

    // MARK: Werewolf — night falls, the full moon rises, paw prints, a howl

    /// Craters as (unit x, unit y, unit radius) of the moon.
    private static let craters: [(CGFloat, CGFloat, CGFloat)] = [
        (-0.36, -0.2, 0.19), (0.26, 0.3, 0.23), (0.42, -0.36, 0.12), (-0.12, 0.48, 0.1), (0.06, -0.04, 0.09), (-0.52, 0.26, 0.08),
    ]

    private func moon(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, radius r: CGFloat, glow: Double, opacity: Double) {
        guard opacity > 0.004 else { return }
        ctx.revealBlob(x: x, y: y, rx: r * 2.4, ry: r * 2.4, gradient: RevealPalette.moonHalo, opacity: opacity * glow)
        let saved = ctx.opacity
        ctx.opacity = saved * opacity
        ctx.fill(
            Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
            with: .radialGradient(
                RevealPalette.moonFace, center: CGPoint(x: x - r * 0.3, y: y - r * 0.3), startRadius: 0, endRadius: r * 1.5
            )
        )
        ctx.opacity = saved
        for (cx, cy, cr) in Self.craters {
            ctx.revealCircle(x: x + cx * r, y: y + cy * r, radius: cr * r, color: RevealPalette.crater, opacity: opacity * 0.55)
        }
    }

    /// Where the moon ends up, in unit coordinates (radius as a fraction of the width):
    /// up and to the right, so it doesn't sit on the verdict emoji.
    private static let moonSpot = (x: 0.72, y: 0.17, radius: 0.2)

    private func werewolf(_ ctx: inout GraphicsContext, _ pass: Pass) {
        let rise = RevealFX.easeOut(RevealFX.prog(t, 0.15, 2.1))
        let settle = RevealFX.easeInOut(RevealFX.prog(t, 3.0, 5.0))
        let radius = w * Self.moonSpot.radius
        let moonX = RevealFX.lerp(0.88, Self.moonSpot.x, rise) * w
        let moonY = RevealFX.lerp(0.55, Self.moonSpot.y, rise) * h

        switch pass {
        case .base:
            fillScreen(&ctx, RevealPalette.night, opacity: 0.5 * RevealFX.easeOut(RevealFX.prog(t, 0, 1.0)) * (1 - 0.64 * settle))
            let paw = ctx.resolveSymbol(id: RevealSymbol.paw)
            let start = CGPoint(x: -20, y: h * 0.80)
            let end = CGPoint(x: w + 20, y: h * 0.69)
            let heading = atan2(end.y - start.y, end.x - start.x)
            let count = 11
            for k in 0..<count {
                let dt = t - (0.85 + Double(k) * 0.15)
                guard dt > 0 else { continue }
                let opacity = 1 - RevealFX.prog(dt, 1.1, 1.7)
                guard opacity > 0 else { continue }
                let u = Double(k) / Double(count - 1)
                let side: Double = k % 2 == 0 ? -1 : 1
                ctx.revealDraw(
                    paw,
                    x: start.x + (end.x - start.x) * u - sin(heading) * 10 * side,
                    y: start.y + (end.y - start.y) * u + cos(heading) * 10 * side,
                    scale: 1.1 * RevealFX.easeOutBack(RevealFX.prog(dt, 0, 0.14)),
                    rotation: heading + .pi / 4,
                    opacity: opacity
                )
            }
            let howl = t - 1.7
            if howl > 0, howl < 1.4 {
                ctx.revealDraw(
                    ctx.resolveSymbol(id: RevealSymbol.awoo),
                    x: moonX - radius * 0.1, y: moonY + radius * 1.35,
                    scale: 0.7 + 0.4 * RevealFX.easeOut(howl / 1.4), rotation: -0.12,
                    opacity: RevealFX.window(howl, 0, 0.15, 1.0, 1.4)
                )
            }
        case .glow:
            for k in 0..<16 {
                let appear = 0.3 + rand(k, 44) * 0.8
                let twinkle = 0.55 + 0.45 * sin(t * (1.5 + rand(k, 43) * 2) + Double(k))
                ctx.revealCircle(
                    x: rand(k, 41) * w, y: (0.04 + rand(k, 42) * 0.5) * h,
                    radius: 0.8 + rand(k, 45) * 1.4, color: .white,
                    opacity: RevealFX.prog(t, appear, appear + 0.5) * twinkle * (1 - 0.45 * settle)
                )
            }
            moon(
                &ctx, x: moonX, y: moonY, radius: radius,
                glow: 0.85 + 0.15 * sin(t * 1.4),
                opacity: 0.92 * RevealFX.prog(t, 0.1, 0.6) * (1 - 0.5 * settle)
            )
        case .top:
            break
        }
    }

    // MARK: Zombie — green fog rolls in, hands wave hello, brains bob

    private func fog(_ ctx: inout GraphicsContext, back: Bool, level: Double, opacity: Double) {
        for k in 0..<10 where (k % 2 == 0) == back {
            let kd = Double(k)
            ctx.revealBlob(
                x: (kd / 9 * 1.3 - 0.15) * w + sin(t * 0.35 + kd * 1.3) * 38,
                y: h * 1.08 - level * h * (0.24 + 0.1 * rand(k, 51)),
                rx: w * (0.30 + 0.12 * rand(k, 52)), ry: h * (0.10 + 0.04 * rand(k, 53)),
                gradient: RevealPalette.fogBlob, opacity: opacity * (back ? 0.95 : 0.8)
            )
        }
    }

    private static let handSpots: [CGFloat] = [0.18, 0.52, 0.84]
    private static let brainSpots: [CGFloat] = [0.36, 0.68, 0.10]

    private func zombie(_ ctx: inout GraphicsContext, _ pass: Pass) {
        guard pass == .base else { return }
        let settle = RevealFX.easeInOut(RevealFX.prog(t, 3.0, 5.5))
        let level = RevealFX.easeOut(RevealFX.prog(t, 0, 1.7)) * (1 - 0.45 * settle)
        let fogOpacity = (1 - 0.35 * settle) * (1 - RevealFX.prog(t, total - 2.5, total - 0.2))
        vignette(&ctx, RevealPalette.greenVignette, opacity: 0.8 * RevealFX.window(t, 0, 0.8, 2.6, 4.5))
        fog(&ctx, back: true, level: level, opacity: fogOpacity)

        let hand = ctx.resolveSymbol(id: RevealSymbol.hand)
        for (k, x) in Self.handSpots.enumerated() {
            let kd = Double(k)
            let start = 0.5 + 0.28 * kd
            let up = RevealFX.easeOutBack(RevealFX.prog(t, start, start + 0.7))
            let down = RevealFX.easeInOut(RevealFX.prog(t, 3.4 + 0.35 * kd, 4.4 + 0.35 * kd))
            guard up > 0, down < 1 else { continue }
            ctx.revealDraw(
                hand,
                x: x * w,
                y: RevealFX.lerp(h + 60, h * (0.83 + 0.025 * kd), up) + down * 140 + sin(t * 2.2 + kd) * 5,
                rotation: sin(t * 7 + kd * 1.4) * 0.32 * (1 - down),
                anchor: .bottom
            )
        }

        let brain = ctx.resolveSymbol(id: RevealSymbol.brain)
        let brainsFade = 1 - RevealFX.prog(t, total - 3.0, total - 1.2)
        for (k, x) in Self.brainSpots.enumerated() {
            let kd = Double(k)
            let start = 1.0 + 0.25 * kd
            let up = RevealFX.easeOut(RevealFX.prog(t, start, start + 1.0))
            guard up > 0 else { continue }
            ctx.revealDraw(
                brain,
                x: x * w + sin(t * 0.9 + kd) * 8,
                y: RevealFX.lerp(h + 40, h * (0.74 - 0.03 * kd), up) + sin(t * 1.7 + kd * 2) * 9,
                rotation: sin(t * 1.2 + kd) * 0.22,
                opacity: brainsFade
            )
        }
        fog(&ctx, back: false, level: level, opacity: fogOpacity)
    }

    // MARK: Robot — RGB glitch, neon gears, BEEP BOOP

    /// (time, angular speed) keys for the robot gears: spin up, then power down to a stop.
    private static let gearSpeeds: [(Double, Double)] = {
        let total = RevealScript.total(.robot)
        return [(0, 0), (0.35, 4.2), (2.4, 4.2), (4.0, 1.0), (total - 2.2, 1.0), (total - 1.0, 0)]
    }()

    /// Gear angle for a radius-50 gear (integral of the speed keys).
    private func gearSpin(_ time: Double) -> Double {
        let keys = Self.gearSpeeds
        var angle = 0.0
        for index in 1..<keys.count {
            let (t0, w0) = keys[index - 1]
            let (t1, w1) = keys[index]
            guard time > t0 else { break }
            let span = min(time, t1) - t0
            let wNow = w0 + (w1 - w0) * span / (t1 - t0)
            angle += (w0 + wNow) / 2 * span
        }
        return angle
    }

    private func gear(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, radius r: CGFloat, rotation: Double, opacity: Double) {
        guard opacity > 0.004, r > 1 else { return }
        let savedTransform = ctx.transform
        let savedOpacity = ctx.opacity
        ctx.transform = savedTransform.translatedBy(x: x, y: y).rotated(by: rotation).scaledBy(x: r, y: r)
        ctx.opacity = savedOpacity * opacity
        ctx.fill(revealGearPath, with: .color(RevealPalette.neonFaint), style: FillStyle(eoFill: true))
        ctx.stroke(revealGearPath, with: .color(RevealPalette.neonHalo), lineWidth: 6 / r)
        ctx.stroke(revealGearPath, with: .color(Theme.neon), lineWidth: 2 / r)
        ctx.transform = savedTransform
        ctx.opacity = savedOpacity
    }

    /// Gears hugging the screen edges: two meshing pairs plus two loners.
    /// (unit x, unit y, extra dx, extra dy, radius, spin direction)
    private static let gearLayout: [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat, Double)] = [
        (0.02, 0.2, 0, 0, 50, 1),
        (0.02, 0.2, cos(0.55) * 76, sin(0.55) * 76, 28, -1),
        (0.99, 0.86, 0, 0, 62, -1),
        (0.99, 0.86, cos(.pi + 0.6) * 92, sin(.pi + 0.6) * 92, 32, 1),
        (0.03, 0.95, 0, 0, 40, 1),
        (0.985, 0.33, 0, 0, 30, -1),
    ]

    private func robotGears(_ ctx: inout GraphicsContext, spin: Double, opacity: Double, popIn: Bool) {
        for (k, item) in Self.gearLayout.enumerated() {
            let (ux, uy, dx, dy, radius, direction) = item
            let pop = popIn ? RevealFX.easeOutBack(RevealFX.prog(t, 0.1 + Double(k) * 0.07, 0.45 + Double(k) * 0.07)) : 1
            gear(
                &ctx, x: ux * w + dx, y: uy * h + dy, radius: radius * pop,
                rotation: spin * direction * 50 / radius + Double(k), opacity: opacity
            )
        }
    }

    /// (start, text line, unit x, unit y, tilt) for the BEEP BOOP pop-ups.
    private static let robotBlips: [(Double, Int, CGFloat, CGFloat, Double)] = [
        (0.2, 0, 0.26, 0.25, -0.12), (0.5, 1, 0.74, 0.31, 0.1), (0.85, 2, 0.5, 0.6, -0.05),
        (1.25, 3, 0.5, 0.67, 0), (1.6, 4, 0.5, 0.74, 0.04), (1.95, 5, 0.3, 0.52, -0.1),
    ]

    private func robot(_ ctx: inout GraphicsContext, _ pass: Pass) {
        let frame = Int(t * 16)
        let glitch = t < 2.3 ? 1 - 0.75 * RevealFX.prog(t, 0.2, 2.3) : 0
        let ambientBlip = t > 3 && t < total - 2 && RevealFX.fract((t - 3) / 2.7) < 0.045

        switch pass {
        case .glow:
            for i in 0..<6 {
                let n = frame &* 7 &+ i
                guard rand(n, 61) < glitch || (ambientBlip && i == 0) else { continue }
                let y = rand(n, 62) * h
                let height = 3 + rand(n, 63) * 22
                let shift = (rand(n, 64) - 0.5) * 34
                let saved = ctx.opacity
                ctx.opacity = saved * 0.32
                ctx.fill(Path(CGRect(x: shift, y: y, width: w, height: height)), with: .color(RevealPalette.magenta))
                ctx.fill(Path(CGRect(x: -shift, y: y + 2, width: w, height: height)), with: .color(RevealPalette.cyan))
                ctx.opacity = saved * 0.45
                ctx.fill(Path(CGRect(x: 0, y: y + height / 2, width: w, height: 1)), with: .color(.white))
                ctx.opacity = saved
            }
            if t < 2.4 {
                let barY = (RevealFX.fract(t * 0.7) * 1.3 - 0.15) * h
                let saved = ctx.opacity
                ctx.opacity = saved * (1 - RevealFX.prog(t, 1.8, 2.4))
                ctx.fill(
                    Path(CGRect(x: 0, y: barY - 40, width: w, height: 80)),
                    with: .linearGradient(RevealPalette.refreshBar, startPoint: CGPoint(x: 0, y: barY - 40), endPoint: CGPoint(x: 0, y: barY + 40))
                )
                ctx.opacity = saved
            }
        case .base:
            for i in 0..<4 {
                let n = frame &* 13 &+ i
                guard rand(n, 65) < glitch * 0.7 else { continue }
                let saved = ctx.opacity
                ctx.opacity = saved * 0.55
                ctx.fill(Path(CGRect(x: 0, y: rand(n, 66) * h, width: w, height: 2 + rand(n, 67) * 10)), with: .color(.black))
                ctx.opacity = saved
            }
            let gearOpacity = RevealFX.prog(t, 0.1, 0.3) * (1 - 0.5 * RevealFX.prog(t, 2.4, 3.4)) * (1 - RevealFX.prog(t, total - 1.0, total - 0.2))
            robotGears(&ctx, spin: gearSpin(t), opacity: gearOpacity * 0.9, popIn: true)

            for (start, line, x, y, tilt) in Self.robotBlips {
                let dt = t - start
                guard dt > 0, dt < 0.8 else { continue }
                let pop = RevealFX.easeOutBack(RevealFX.prog(dt, 0, 0.12))
                let flicker = dt < 0.55 ? 1 : (Int(dt * 40) % 2 == 0 ? 0.85 : 0.15) * (1 - RevealFX.prog(dt, 0.55, 0.8))
                ctx.revealDraw(
                    ctx.resolveSymbol(id: RevealSymbol.robotText(line)),
                    x: x * w, y: y * h, scale: 0.6 + 0.4 * pop, rotation: tilt, opacity: flicker
                )
            }
            if t > 3, t < total - 2.2 {
                let cycle = Int((t - 3) / 3.1)
                let dt = (t - 3) - Double(cycle) * 3.1
                if dt < 0.8 {
                    let left = cycle % 2 == 0
                    ctx.revealDraw(
                        ctx.resolveSymbol(id: RevealSymbol.robotText(cycle % 2)),
                        x: w * (left ? 0.24 : 0.74), y: h * (left ? 0.29 : 0.79),
                        scale: 0.6 + 0.15 * RevealFX.easeOutBack(RevealFX.prog(dt, 0, 0.12)),
                        opacity: 0.8 * (1 - RevealFX.prog(dt, 0.55, 0.8))
                    )
                }
            }
        case .top:
            break
        }
    }

    // MARK: Ghost — soft focus, mist, ghosts drift up (one says boo, quietly)

    private func mist(_ ctx: inout GraphicsContext, opacity: Double) {
        for k in 0..<7 {
            let direction: Double = k % 2 == 0 ? 1 : -1
            ctx.revealBlob(
                x: (RevealFX.fract(rand(k, 71) + t * 0.025 * direction) * 1.5 - 0.25) * w,
                y: (0.12 + 0.8 * rand(k, 72)) * h - t * 6,
                rx: w * (0.28 + 0.12 * rand(k, 73)), ry: h * (0.09 + 0.04 * rand(k, 74)),
                gradient: RevealPalette.mistBlob, opacity: opacity
            )
        }
    }

    private func ghost(_ ctx: inout GraphicsContext, _ pass: Pass) {
        switch pass {
        case .top:
            break
        case .glow:
            mist(&ctx, opacity: 0.8 * RevealFX.window(t, 0, 0.7, 2.0, 3.2) + 0.35 * RevealFX.window(t, 2.0, 3.2, total - 2, total))
        case .base:
            let ghost = ctx.resolveSymbol(id: RevealSymbol.ghost)
            for k in 0..<9 {
                let kd = Double(k)
                let a = (t - (0.05 + kd * 0.16)) / (2.6 + rand(k, 81) * 0.8)
                guard a > 0, a < 1 else { continue }
                let scale = 0.6 + 0.7 * rand(k, 83)
                let x = (0.1 + 0.8 * rand(k, 82)) * w + sin(t * 1.8 + kd) * 26
                let y = h + 50 - h * 0.95 * (0.8 * a + 0.2 * a * a)
                ctx.revealDraw(
                    ghost, x: x, y: y, scale: scale, rotation: cos(t * 1.8 + kd) * 0.16,
                    opacity: min(1, a * 6) * (1 - RevealFX.prog(a, 0.6, 1.0)) * 0.85, flip: k % 2 == 1
                )
                if k == 4 {
                    ctx.revealDraw(
                        ctx.resolveSymbol(id: RevealSymbol.boo), x: x + 40 * scale, y: y - 36 * scale,
                        opacity: RevealFX.window(a, 0.18, 0.23, 0.5, 0.56)
                    )
                }
            }
            guard t > 2.4 else { return }
            for k in 0..<2 {
                let kd = Double(k)
                let phase = RevealFX.fract((t - 2.4) / 5.5 + kd * 0.5)
                ctx.revealDraw(
                    ghost,
                    x: (k == 0 ? 0.08 : 0.92) * w + sin(t * 1.3 + kd) * 10,
                    y: h + 40 - phase * (h + 80),
                    scale: 0.55, rotation: sin(t * 1.3) * 0.1,
                    opacity: 0.4 * sin(phase * .pi) * RevealFX.window(t, 2.4, 3.2, total - 1.8, total - 0.3),
                    flip: k == 1
                )
            }
        }
    }

    // MARK: Human — a sad little confetti fizzle, then CERTIFIED HUMAN. *crickets*

    private var stampCenter: CGPoint { CGPoint(x: w / 2, y: focus.y + h * 0.08) }

    private func human(_ ctx: inout GraphicsContext, _ pass: Pass) {
        guard pass == .base else { return }
        let popperX = w * 0.26
        let popperY = focus.y + h * 0.12
        ctx.revealDraw(
            ctx.resolveSymbol(id: RevealSymbol.popper), x: popperX, y: popperY,
            scale: RevealFX.easeOutBack(RevealFX.prog(t, 0, 0.22)),
            rotation: RevealFX.lerp(-0.2, 1.1, RevealFX.easeInOut(RevealFX.prog(t, 0.55, 1.15))),
            opacity: 1 - RevealFX.prog(t, 1.1, 1.4)
        )
        ctx.revealDraw(
            ctx.resolveSymbol(id: RevealSymbol.pfft), x: popperX + 38, y: popperY - 40,
            opacity: RevealFX.window(t, 0.3, 0.4, 1.0, 1.25)
        )

        let tau = t - 0.12
        if tau > 0, tau < 1.4 {
            let opacity = 1 - RevealFX.prog(tau, 0.75, 1.3)
            let savedTransform = ctx.transform
            let savedOpacity = ctx.opacity
            for k in 0..<18 {
                let vx = 25 + rand(k, 91) * 120
                let vy = -(130 + rand(k, 92) * 190)
                let x = popperX + 14 + vx * tau
                let y = popperY - 20 + vy * tau + 450 * tau * tau
                ctx.transform = savedTransform
                    .translatedBy(x: x, y: y)
                    .rotated(by: tau * (rand(k, 93) - 0.5) * 14)
                    .scaledBy(x: 1, y: max(0.15, abs(cos(tau * 11 + Double(k)))))
                ctx.opacity = savedOpacity * opacity
                ctx.fill(Path(CGRect(x: -2.5, y: -4.5, width: 5, height: 9)), with: .color(RevealPalette.confetti[k % 5]))
            }
            ctx.transform = savedTransform
            ctx.opacity = savedOpacity
        }

        stamp(&ctx, time: t)

        let hop = RevealFX.prog(t, 2.3, 4.9)
        if hop > 0, hop < 1 {
            let hops = hop * 6
            let phase = RevealFX.fract(hops)
            let x = RevealFX.lerp(w + 24, -24, hop)
            let y = h * 0.93 - sin(phase * .pi) * 24
            ctx.revealDraw(ctx.resolveSymbol(id: RevealSymbol.cricket), x: x, y: y, rotation: phase < 0.5 ? 0.2 : -0.15)
            if phase < 0.3, hops > 0.5 {
                ctx.revealDraw(ctx.resolveSymbol(id: RevealSymbol.chirp), x: x, y: y - 30, opacity: 1 - phase / 0.3)
            }
        }
    }

    private func stamp(_ ctx: inout GraphicsContext, time: Double) {
        let land = RevealScript.stampLands
        guard time > land - 0.2 else { return }
        let after = time - land
        var scale = RevealFX.lerp(3.0, 1.3, RevealFX.easeIn(RevealFX.prog(time, land - 0.2, land)))
        if after > 0 { scale *= 1 - 0.07 * sin(RevealFX.prog(after, 0, 0.16) * .pi) }
        let center = stampCenter
        ctx.revealDraw(
            ctx.resolveSymbol(id: RevealSymbol.stamp), x: center.x, y: center.y,
            scale: scale, rotation: -0.12, opacity: 0.95 * RevealFX.prog(time, land - 0.2, land - 0.1)
        )
        guard after > 0, after < 0.6 else { return }
        let spread = RevealFX.easeOut(RevealFX.prog(after, 0, 0.45))
        for k in 0..<12 {
            let angle = Double(k) / 12 * 2 * .pi + rand(k, 95) * 0.4
            ctx.revealCircle(
                x: center.x + cos(angle) * (w * 0.36 + 40 * spread),
                y: center.y + sin(angle) * (30 + 30 * spread),
                radius: 2 + rand(k, 96) * 2.5, color: Theme.alert,
                opacity: 1 - RevealFX.prog(after, 0.25, 0.6)
            )
        }
    }

    // MARK: Reduce Motion stills

    func paintStill(_ ctx: inout GraphicsContext, layer: StillLayer, pass: Pass) {
        switch (monster, layer, pass) {
        case (.vampire, .flourish, .base):
            vignette(&ctx, RevealPalette.crimsonVignette, opacity: 0.7)
            let bat = ctx.resolveSymbol(id: RevealSymbol.bat)
            for (x, y, s, flip) in [(0.12, 0.2, 0.7, false), (0.88, 0.24, 0.6, true), (0.1, 0.72, 0.55, false), (0.9, 0.68, 0.65, true)] {
                ctx.revealDraw(bat, x: x * w, y: y * h, scale: s, flip: flip)
            }
        case (.alien, .flourish, .base):
            let hoverY = max(focus.y - h * 0.24, 96)
            var cone = Path()
            cone.move(to: CGPoint(x: w / 2 - 22, y: hoverY + 26))
            cone.addLine(to: CGPoint(x: w / 2 + 22, y: hoverY + 26))
            cone.addLine(to: CGPoint(x: w / 2 + w * 0.31, y: focus.y + h * 0.13))
            cone.addLine(to: CGPoint(x: w / 2 - w * 0.31, y: focus.y + h * 0.13))
            cone.closeSubpath()
            let saved = ctx.opacity
            ctx.opacity = saved * 0.3
            ctx.fill(cone, with: .linearGradient(
                RevealPalette.beam, startPoint: CGPoint(x: 0, y: hoverY), endPoint: CGPoint(x: 0, y: focus.y + h * 0.13)
            ))
            ctx.opacity = saved
            ctx.revealDraw(ctx.resolveSymbol(id: RevealSymbol.ufo), x: w / 2, y: hoverY)
            let sparkle = ctx.resolveSymbol(id: RevealSymbol.sparkle)
            for (x, y) in [(0.2, 0.3), (0.82, 0.42), (0.3, 0.55), (0.74, 0.2)] {
                ctx.revealDraw(sparkle, x: x * w, y: y * h, scale: 0.6)
            }
        case (.kaiju, .flourish, .base):
            for (k, x) in [0.14, 0.38, 0.63, 0.86].enumerated() {
                ctx.revealBlob(x: x * w, y: h - 22, rx: 60, ry: 26, gradient: RevealPalette.dustBlob, opacity: 0.6)
                ctx.revealDraw(
                    ctx.resolveSymbol(id: RevealSymbol.building(k)), x: x * w, y: h - 44,
                    scale: 0.9, rotation: [0.4, -1.2, 1.57, -0.3][k]
                )
            }
        case (.werewolf, .resting, .base):
            fillScreen(&ctx, RevealPalette.night, opacity: 0.2)
        case (.werewolf, .resting, .glow):
            for k in 0..<16 {
                ctx.revealCircle(
                    x: rand(k, 41) * w, y: (0.04 + rand(k, 42) * 0.5) * h,
                    radius: 0.8 + rand(k, 45) * 1.4, color: .white, opacity: 0.6
                )
            }
            moon(&ctx, x: Self.moonSpot.x * w, y: Self.moonSpot.y * h, radius: Self.moonSpot.radius * w, glow: 0.9, opacity: 0.45)
        case (.werewolf, .flourish, .base):
            let paw = ctx.resolveSymbol(id: RevealSymbol.paw)
            for k in 0..<4 {
                let u = 0.2 + Double(k) * 0.2
                ctx.revealDraw(paw, x: u * w, y: h * (0.8 - 0.11 * u) + (k % 2 == 0 ? -10 : 10), rotation: 0.6, opacity: 0.85)
            }
        case (.zombie, .flourish, .base):
            vignette(&ctx, RevealPalette.greenVignette, opacity: 0.6)
            fog(&ctx, back: true, level: 0.7, opacity: 0.8)
            ctx.revealDraw(ctx.resolveSymbol(id: RevealSymbol.hand), x: w * 0.22, y: h * 0.85, rotation: -0.2, anchor: .bottom)
            ctx.revealDraw(ctx.resolveSymbol(id: RevealSymbol.hand), x: w * 0.8, y: h * 0.86, rotation: 0.25, anchor: .bottom)
            ctx.revealDraw(ctx.resolveSymbol(id: RevealSymbol.brain), x: w * 0.52, y: h * 0.76)
            fog(&ctx, back: false, level: 0.7, opacity: 0.7)
        case (.robot, .flourish, .base):
            robotGears(&ctx, spin: 0, opacity: 0.7, popIn: false)
            ctx.revealDraw(ctx.resolveSymbol(id: RevealSymbol.robotText(2)), x: w / 2, y: h * 0.62, rotation: -0.05)
        case (.ghost, .flourish, .base):
            mist(&ctx, opacity: 0.8)
            let ghost = ctx.resolveSymbol(id: RevealSymbol.ghost)
            for (x, y, s) in [(0.16, 0.62, 0.9), (0.84, 0.48, 0.7), (0.62, 0.8, 1.1)] {
                ctx.revealDraw(ghost, x: x * w, y: y * h, scale: s, opacity: 0.75)
            }
        case (.human, .resting, .base):
            let center = stampCenter
            ctx.revealDraw(ctx.resolveSymbol(id: RevealSymbol.stamp), x: center.x, y: center.y, scale: 1.3, rotation: -0.12, opacity: 0.95)
        default:
            break
        }
        if layer == .flourish, pass == .base {
            caption(&ctx, local: 1.5, cursor: false)
        }
    }
}

// MARK: - Preview

#if DEBUG
/// Rough stand-in for RevealView's verdict card, so effects can be judged in context.
private struct PreviewVerdictCard: View {
    let monster: Monster

    var body: some View {
        VStack(spacing: 22) {
            HStack {
                Stamp()
                Spacer()
            }
            VStack(spacing: 10) {
                Text(monster == .human ? "SUBJECT IS" : "SUBJECT IS A")
                    .font(Theme.mono(.subheadline, weight: .bold))
                    .foregroundStyle(Theme.dimNeon)
                Text(monster.emoji).font(.system(size: 110))
                Text(monster.verdictTitle)
                    .font(Theme.mono(.largeTitle, weight: .heavy))
                    .foregroundStyle(monster == .human ? Theme.neon : Theme.alert)
                    .minimumScaleFactor(0.5)
                    .crtGlow(monster == .human ? Theme.neon : Theme.alert, radius: 8)
                Text("CONFIDENCE 97.3%")
                    .font(Theme.mono(.title3, weight: .bold))
                    .foregroundStyle(Theme.neon)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .overlay(Rectangle().stroke(Theme.neon.opacity(0.7), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(title: "DOSSIER · AGENT K-9")
                Text("Subject was observed near a snack table at 21:04. Agent K-9 recommends a firm handshake and a second opinion.")
                    .font(Theme.mono(.callout))
                    .foregroundStyle(Theme.neon)
            }
            Spacer()
        }
        .padding(20)
    }
}

private struct RevealEffectsPlayground: View {
    @State private var monster = Monster.vampire
    @State private var trigger = 0
    @State private var autoCycle = true

    var body: some View {
        ZStack {
            PreviewVerdictCard(monster: monster)
            MonsterRevealEffect(monster: monster, trigger: trigger)
        }
        .revealShake(for: monster, trigger: trigger)
        .crtScreen()
        .safeAreaInset(edge: .bottom) { controls }
        .task(id: autoCycle) {
            guard autoCycle else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                let all = Monster.allCases
                monster = all[((all.firstIndex(of: monster) ?? 0) + 1) % all.count]
                trigger += 1
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(Monster.allCases, id: \.self) { candidate in
                        Button(candidate.emoji) {
                            autoCycle = false
                            monster = candidate
                            trigger += 1
                        }
                        .buttonStyle(IconButtonStyle(active: candidate == monster))
                    }
                }
                .padding(.horizontal, 12)
            }
            HStack {
                Button("Replay") { trigger += 1 }
                    .buttonStyle(NeonButtonStyle())
                Button(autoCycle ? "Stop cycling" : "Auto-cycle") { autoCycle.toggle() }
                    .buttonStyle(NeonButtonStyle(filled: autoCycle))
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.8))
    }
}

#Preview("Reveal effects") {
    RevealEffectsPlayground()
        .preferredColorScheme(.dark)
}

#Preview("Reveal frames") {
    ScrollView(.horizontal) {
        HStack(spacing: 2) {
            ForEach([0.3, 0.9, 1.6, 2.4, 4.0], id: \.self) { time in
                ZStack {
                    PreviewVerdictCard(monster: .kaiju)
                    RevealFrame(monster: .kaiju, time: time)
                }
                .frame(width: 393, height: 852)
                .crtScreen()
                .overlay(alignment: .topTrailing) {
                    Text(String(format: "t=%.1fs", time)).font(Theme.mono(.caption)).foregroundStyle(.white).padding(4)
                }
            }
        }
    }
    .preferredColorScheme(.dark)
}
#endif
