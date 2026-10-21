import MonsterCore
import SwiftUI
import UIKit

// Artwork for the Certificate of Monsterhood: paper, security-printing
// borders, the Bureau emblem, the wax seal, rubber stamps and per-monster
// flavour text. Everything is drawn in code (no bundled images) and laid out
// in fixed points, so the certificate looks identical on every device.

// MARK: - Palette and type

/// Printed-document colours and fonts. Fonts use `fixedSize` so Dynamic Type
/// never reflows the fixed-size artwork.
enum CertificateInk {
    static let paper = Color(red: 0.965, green: 0.925, blue: 0.83)
    static let paperEdge = Color(red: 0.80, green: 0.69, blue: 0.50)
    static let ink = Color(red: 0.10, green: 0.17, blue: 0.13)
    static let fadedInk = Color(red: 0.10, green: 0.17, blue: 0.13).opacity(0.72)
    static let security = Color(red: 0.13, green: 0.45, blue: 0.29)
    static let stampRed = Color(red: 0.76, green: 0.07, blue: 0.11)
    static let penBlue = Color(red: 0.11, green: 0.20, blue: 0.52)
    static let waxLight = Color(red: 0.86, green: 0.20, blue: 0.20)
    static let wax = Color(red: 0.62, green: 0.06, blue: 0.09)
    static let waxDark = Color(red: 0.36, green: 0.02, blue: 0.04)
    static let ribbon = Color(red: 0.08, green: 0.42, blue: 0.24)

    static func copperplate(_ size: CGFloat, bold: Bool = true) -> Font {
        .custom(bold ? "Copperplate-Bold" : "Copperplate", fixedSize: size)
    }
    static func didot(_ size: CGFloat) -> Font { .custom("Didot-Bold", fixedSize: size) }
    static func serifItalic(_ size: CGFloat) -> Font { .custom("Baskerville-SemiBoldItalic", fixedSize: size) }
    static func typewriter(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "AmericanTypewriter-Bold" : "AmericanTypewriter", fixedSize: size)
    }
    static func script(_ size: CGFloat) -> Font { .custom("SnellRoundhand-Black", fixedSize: size) }
    static func marker(_ size: CGFloat) -> Font { .custom("Noteworthy-Bold", fixedSize: size) }
    static func stamp(_ size: CGFloat) -> Font { .custom("AvenirNextCondensed-Heavy", fixedSize: size) }
    static func terminal(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .monospaced) }
}

// MARK: - Per-monster flavour

/// The jokes that change with the verdict.
nonisolated struct CertificateFlavor: Sendable {
    let clearance: String
    let validUntil: String
    let stamp: String
    let sealMotto: String

    init(_ monster: Monster) {
        switch monster {
        case .vampire:
            self.init("NOCTURNAL", "sunrise", "FANG-TASTIC")
        case .alien:
            self.init("COSMIC", "the mothership calls", "OUT OF\nTHIS WORLD")
        case .kaiju:
            self.init("SUPER-SIZED", "the next city-sized nap", "EXTRA LARGE")
        case .werewolf:
            self.init("LUNAR", "the next full moon", "HOWL-ITY\nASSURED")
        case .zombie:
            self.init("UNDEAD", "the snacks run out", "UNDEAD &\nUNBOTHERED")
        case .robot:
            self.init("ROOT ACCESS", "the next firmware update", "BEEP BOOP\nVERIFIED")
        case .ghost:
            self.init("SEE-THROUGH", "forever and ever and ever", "BOO-NA FIDE")
        case .human:
            self.init("VISITOR", "something weird happens", "DISAPPOINTINGLY\nNORMAL",
                      motto: "SADLY APPROVED ✦ B.S.M.A. ✦ ")
        }
    }

    private init(_ clearance: String, _ validUntil: String, _ stamp: String,
                 motto: String = "OFFICIALLY SPOOKY ✦ B.S.M.A. ✦ ") {
        self.clearance = clearance
        self.validUntil = validUntil
        self.stamp = stamp
        sealMotto = motto
    }
}

// MARK: - Deterministic noise

/// SplitMix64, so paper speckles and stamp wear are the same every render.
nonisolated struct ArtRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    init(text: String) {
        // Stable across launches (unlike `hashValue`).
        var seed: UInt64 = 1469598103934665603
        for scalar in text.unicodeScalars { seed = (seed ^ UInt64(scalar.value)) &* 1099511628211 }
        state = seed
    }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
    }

    mutating func next(_ range: ClosedRange<Double>) -> CGFloat {
        CGFloat(range.lowerBound + next() * (range.upperBound - range.lowerBound))
    }
}

// MARK: - Security printing

/// Interlaced sine waves, like the border of a banknote. Draws along the
/// longer side of its rect.
nonisolated struct GuillocheBand: Shape {
    var strands = 6
    var period: CGFloat = 44

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let horizontal = rect.width >= rect.height
        let length = horizontal ? rect.width : rect.height
        let thickness = horizontal ? rect.height : rect.width
        let amplitude = thickness * 0.40
        let middle = thickness / 2

        func point(_ along: CGFloat, _ across: CGFloat) -> CGPoint {
            horizontal
                ? CGPoint(x: rect.minX + along, y: rect.minY + across)
                : CGPoint(x: rect.minX + across, y: rect.minY + along)
        }

        for strand in 0..<strands {
            let phase = CGFloat(strand) * 2 * .pi / CGFloat(strands)
            var along: CGFloat = 0
            path.move(to: point(0, middle + amplitude * sin(phase)))
            while along < length {
                along = min(along + 2, length)
                let wave = sin(2 * .pi * along / period + phase)
                path.addLine(to: point(along, middle + amplitude * wave))
            }
        }
        // Edge rules.
        path.move(to: point(0, 0.5)); path.addLine(to: point(length, 0.5))
        path.move(to: point(0, thickness - 0.5)); path.addLine(to: point(length, thickness - 0.5))
        return path
    }
}

/// A woven rosette of overlapping polar roses.
nonisolated struct GuillocheRosette: Shape {
    var petals = 12
    var layers = 7
    var depth: CGFloat = 0.32

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let steps = 720
        for layer in 0..<layers {
            let phase = CGFloat(layer) * 2 * .pi / CGFloat(layers * petals)
            for step in 0...steps {
                let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
                let r = radius * (1 - depth + depth * cos(CGFloat(petals) * (angle + phase)))
                let p = CGPoint(x: center.x + r * cos(angle), y: center.y + r * sin(angle))
                step == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            path.closeSubpath()
        }
        return path
    }
}

/// Guilloche border with rosettes in the corners.
struct GuillocheFrame: View {
    var band: CGFloat = 30
    var inset: CGFloat = 12
    var color: Color = CertificateInk.security

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let corner = band * 2.3
            let start = inset + band / 2 + corner * 0.42
            let horizontalLength = max(0, size.width - 2 * start)
            let verticalLength = max(0, size.height - 2 * start)
            ZStack(alignment: .topLeading) {
                Group {
                    strip(width: horizontalLength, height: band)
                        .offset(x: start, y: inset)
                    strip(width: horizontalLength, height: band)
                        .offset(x: start, y: size.height - inset - band)
                    strip(width: band, height: verticalLength)
                        .offset(x: inset, y: start)
                    strip(width: band, height: verticalLength)
                        .offset(x: size.width - inset - band, y: start)
                }
                ForEach(0..<4, id: \.self) { index in
                    let x = index % 2 == 0 ? inset + band / 2 : size.width - inset - band / 2
                    let y = index < 2 ? inset + band / 2 : size.height - inset - band / 2
                    ZStack {
                        GuillocheRosette(petals: 10, layers: 6, depth: 0.35)
                            .stroke(color.opacity(0.85), lineWidth: 0.8)
                        Circle().stroke(color, lineWidth: 1.5).padding(corner * 0.18)
                        GuillocheRosette(petals: 6, layers: 4, depth: 0.4)
                            .stroke(color, lineWidth: 0.8)
                            .padding(corner * 0.27)
                    }
                    .frame(width: corner, height: corner)
                    .background(Circle().fill(CertificateInk.paper))
                    .offset(x: x - corner / 2, y: y - corner / 2)
                }
                // Inner double rule.
                Rectangle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: size.width - 2 * (inset + band + 10), height: size.height - 2 * (inset + band + 10))
                    .offset(x: inset + band + 10, y: inset + band + 10)
                Rectangle()
                    .stroke(color.opacity(0.7), lineWidth: 0.8)
                    .frame(width: size.width - 2 * (inset + band + 15), height: size.height - 2 * (inset + band + 15))
                    .offset(x: inset + band + 15, y: inset + band + 15)
            }
        }
        .accessibilityHidden(true)
    }

    private func strip(width: CGFloat, height: CGFloat) -> some View {
        GuillocheBand(strands: 6, period: 42)
            .stroke(color.opacity(0.85), lineWidth: 0.9)
            .frame(width: width, height: height)
    }
}

/// Old paper: warm vignette, fibres and speckles.
struct PaperTexture: View {
    var body: some View {
        ZStack {
            CertificateInk.paper
            RadialGradient(
                colors: [.clear, CertificateInk.paperEdge.opacity(0.55)],
                center: .center, startRadius: 280, endRadius: 820
            )
            Canvas { context, size in
                var random = ArtRandom(seed: 0xB5_A0_9)
                for _ in 0..<1400 {
                    let x = random.next(0...1) * size.width
                    let y = random.next(0...1) * size.height
                    let r = random.next(0.4...1.6)
                    let shade = Color(red: 0.45, green: 0.33, blue: 0.18).opacity(Double(random.next(0.05...0.22)))
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r, height: r)), with: .color(shade))
                }
                for _ in 0..<90 {
                    var fibre = Path()
                    let x = random.next(0...1) * size.width
                    let y = random.next(0...1) * size.height
                    fibre.move(to: CGPoint(x: x, y: y))
                    fibre.addQuadCurve(
                        to: CGPoint(x: x + random.next(-40...40), y: y + random.next(-40...40)),
                        control: CGPoint(x: x + random.next(-30...30), y: y + random.next(-30...30))
                    )
                    context.stroke(fibre, with: .color(Color(red: 0.5, green: 0.38, blue: 0.2).opacity(0.10)), lineWidth: 0.7)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Seals and stamps

/// Characters arranged evenly around a circle.
struct CircularText: View {
    let text: String
    let radius: CGFloat
    let font: Font
    let color: Color

    var body: some View {
        let characters = Array(text)
        ZStack {
            ForEach(characters.indices, id: \.self) { index in
                Text(String(characters[index]))
                    .font(font)
                    .foregroundStyle(color)
                    .offset(y: -radius)
                    .rotationEffect(.degrees(Double(index) * 360 / Double(characters.count)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A dog's paw print: one pad and four toes.
nonisolated struct PawPrint: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func oval(_ x: CGFloat, _ y: CGFloat, _ ow: CGFloat, _ oh: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * w, y: rect.minY + y * h, width: ow * w, height: oh * h)
        }
        var path = Path()
        path.addEllipse(in: oval(0.22, 0.46, 0.56, 0.48))
        path.addEllipse(in: oval(0.02, 0.26, 0.20, 0.26))
        path.addEllipse(in: oval(0.24, 0.04, 0.21, 0.29))
        path.addEllipse(in: oval(0.55, 0.04, 0.21, 0.29))
        path.addEllipse(in: oval(0.78, 0.26, 0.20, 0.26))
        return path
    }
}

/// The Bureau's round emblem, printed in security ink.
struct BureauEmblem: View {
    var size: CGFloat = 112

    var body: some View {
        ZStack {
            Circle().fill(CertificateInk.paper)
            GuillocheRosette(petals: 16, layers: 5, depth: 0.18)
                .stroke(CertificateInk.security.opacity(0.55), lineWidth: 0.6)
                .padding(size * 0.2)
            Circle().stroke(CertificateInk.ink, lineWidth: 3)
            Circle().stroke(CertificateInk.ink, lineWidth: 1).padding(size * 0.05)
            Circle().stroke(CertificateInk.ink, lineWidth: 1.5).padding(size * 0.19)
            CircularText(
                text: "BUREAU OF SECRET MONSTER AFFAIRS ✦ ",
                radius: size * 0.36,
                font: CertificateInk.copperplate(size * 0.085),
                color: CertificateInk.ink
            )
            VStack(spacing: size * 0.01) {
                PawPrint()
                    .fill(CertificateInk.ink)
                    .frame(width: size * 0.25, height: size * 0.23)
                Text(verbatim: "EST. MIDNIGHT")
                    .font(CertificateInk.copperplate(size * 0.055))
                    .foregroundStyle(CertificateInk.ink)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Blobby edge of poured wax.
nonisolated struct WaxBlob: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let steps = 240
        for step in 0...steps {
            let a = CGFloat(step) / CGFloat(steps) * 2 * .pi
            let wobble = 0.93 + 0.035 * sin(9 * a) + 0.025 * sin(17 * a + 1.3) + 0.015 * cos(5 * a + 0.4)
            let p = CGPoint(x: center.x + radius * wobble * cos(a), y: center.y + radius * wobble * sin(a))
            step == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        return path
    }
}

/// A ribbon tail with a V-notched end.
nonisolated struct RibbonTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.width * 0.45))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Red wax seal with green ribbons, pressed with Agent K-9's paw.
struct WaxSeal: View {
    var motto: String
    var size: CGFloat = 150

    var body: some View {
        ZStack {
            ForEach([-22.0, 22.0], id: \.self) { angle in
                RibbonTail()
                    .fill(CertificateInk.ribbon)
                    .overlay(
                        Rectangle()
                            .fill(Color.white.opacity(0.18))
                            .frame(width: size * 0.05)
                    )
                    .frame(width: size * 0.26, height: size * 0.62)
                    .offset(y: size * 0.36)
                    .rotationEffect(.degrees(angle), anchor: .center)
            }
            WaxBlob()
                .fill(RadialGradient(
                    colors: [CertificateInk.waxLight, CertificateInk.wax, CertificateInk.waxDark],
                    center: UnitPoint(x: 0.38, y: 0.34), startRadius: 2, endRadius: size * 0.62
                ))
                .shadow(color: .black.opacity(0.35), radius: 4, x: 1, y: 3)
            Circle()
                .stroke(CertificateInk.waxDark.opacity(0.8), lineWidth: 3)
                .padding(size * 0.15)
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .padding(size * 0.15 - 2)
            CircularText(
                text: motto,
                radius: size * 0.265,
                font: CertificateInk.copperplate(size * 0.07),
                color: CertificateInk.waxDark
            )
            .shadow(color: .white.opacity(0.25), radius: 0, x: -0.5, y: -0.5)
            PawPrint()
                .fill(CertificateInk.waxDark.opacity(0.9))
                .frame(width: size * 0.26, height: size * 0.24)
                .shadow(color: .white.opacity(0.3), radius: 0, x: -1, y: -1)
                .offset(y: -size * 0.02)
            Text(verbatim: "K-9")
                .font(CertificateInk.didot(size * 0.09))
                .foregroundStyle(CertificateInk.waxDark)
                .shadow(color: .white.opacity(0.3), radius: 0, x: -0.5, y: -0.5)
                .offset(y: size * 0.15)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A slightly worn rubber stamp.
struct RubberStamp: View {
    let text: String
    var color: Color = CertificateInk.stampRed
    var size: CGFloat = 30
    var angle: Double = -10

    var body: some View {
        Text(verbatim: text)
            .font(CertificateInk.stamp(size))
            .tracking(size * 0.08)
            .multilineTextAlignment(.center)
            .lineSpacing(-size * 0.15)
            .fixedSize()
            .padding(.horizontal, size * 0.5)
            .padding(.vertical, size * 0.18)
            .overlay(RoundedRectangle(cornerRadius: size * 0.18).stroke(lineWidth: size * 0.13))
            .overlay(RoundedRectangle(cornerRadius: size * 0.1).stroke(lineWidth: size * 0.04).padding(size * 0.16))
            .foregroundStyle(color)
            .mask(StampWear(seed: text))
            .opacity(0.86)
            .rotationEffect(.degrees(angle))
            .accessibilityHidden(true)
    }
}

/// Speckles where the rubber didn't pick up ink.
private struct StampWear: View {
    let seed: String

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            context.blendMode = .clear
            var random = ArtRandom(text: seed)
            let count = Int(size.width * size.height / 70)
            for _ in 0..<count {
                let r = random.next(0.5...2.4)
                let rect = CGRect(
                    x: random.next(0...1) * size.width,
                    y: random.next(0...1) * size.height,
                    width: r, height: r * random.next(0.6...1.4)
                )
                context.fill(Path(ellipseIn: rect), with: .color(.black))
            }
        }
    }
}

// MARK: - Exhibit A

/// The subject's photo as a taped-on instant print. Without a photo it shows
/// a redacted CRT panel instead.
struct PolaroidPhoto: View {
    let photo: UIImage?
    var photoSize = CGSize(width: 228, height: 234)

    var body: some View {
        VStack(spacing: 8) {
            Group {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                } else {
                    redacted
                }
            }
            .frame(width: photoSize.width, height: photoSize.height)
            .clipped()
            Text(verbatim: photo == nil ? "Exhibit A (classified)" : "Exhibit A")
                .font(CertificateInk.marker(24))
                .foregroundStyle(CertificateInk.penBlue)
                .frame(height: 34)
        }
        .padding(.top, 14)
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .background(Color(white: 0.985))
        .shadow(color: .black.opacity(0.28), radius: 6, x: 2, y: 4)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(red: 0.93, green: 0.89, blue: 0.74).opacity(0.78))
                .frame(width: 104, height: 30)
                .rotationEffect(.degrees(5))
                .offset(y: -15)
        }
        .rotationEffect(.degrees(-4))
    }

    private var redacted: some View {
        ZStack {
            Theme.background
            ScanLines(spacing: 4, opacity: 0.12)
            VStack(spacing: 10) {
                Text(verbatim: "PHOTO")
                Text(verbatim: "REDACTED")
                    .padding(.horizontal, 8)
                    .background(Theme.neon)
                    .foregroundStyle(Theme.background)
                Text(verbatim: "subject too powerful\nfor cameras")
                    .font(CertificateInk.terminal(15))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.dimNeon)
            }
            .font(CertificateInk.terminal(30))
            .foregroundStyle(Theme.neon)
            .crtGlow(radius: 4)
        }
    }
}

// MARK: - Green screen around the printout

/// The certificate is shown as a printout on the Bureau's CRT terminal.
struct TerminalBezel: View {
    let caseNumber: String

    var body: some View {
        ZStack {
            Theme.background
            ScanLines(spacing: 4, opacity: 0.1)
            RoundedRectangle(cornerRadius: 18)
                .stroke(Theme.neon, lineWidth: 3)
                .crtGlow(radius: 8)
                .padding(9)
            VStack {
                HStack {
                    Text(verbatim: "● B.S.M.A. SECURE PRINTOUT · TERMINAL K9")
                    Spacer()
                    Text(verbatim: "CASE \(caseNumber) · PAGE 1/1 ▮")
                }
                Spacer()
                HStack {
                    Text(verbatim: "END OF TRANSMISSION")
                    Spacer()
                    Text(verbatim: "PLEASE LAUGH RESPONSIBLY")
                }
            }
            .font(CertificateInk.terminal(15))
            .foregroundStyle(Theme.neon)
            .crtGlow(radius: 3)
            .padding(.horizontal, 34)
            .padding(.vertical, 14)
        }
        .accessibilityHidden(true)
    }
}
