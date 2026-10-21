import SwiftUI

/// Retro "classified government scanner" look: dark CRT, neon green, red stamps.
enum Theme {
    static let background = Color(red: 0.02, green: 0.04, blue: 0.03)
    static let neon = Color(red: 0.22, green: 1.0, blue: 0.42)
    static let dimNeon = neon.opacity(0.55)
    static let alert = Color(red: 1.0, green: 0.18, blue: 0.22)
    /// Front-camera "UV glow" fill (DECISIONS.md S-1).
    static let uvGlow = Color(red: 0.62, green: 0.32, blue: 1.0)

    static func mono(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .monospaced).weight(weight)
    }
}

/// Faint horizontal CRT scan lines drawn over the whole screen.
struct ScanLines: View {
    var spacing: CGFloat = 3
    var opacity: Double = 0.08

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black.opacity(opacity * 4))
                )
                y += spacing
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Neon text glow.
    func crtGlow(_ color: Color = Theme.neon, radius: CGFloat = 6) -> some View {
        shadow(color: color.opacity(0.7), radius: radius)
    }

    /// Dark background plus scan lines, used by every screen.
    func crtScreen() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background.ignoresSafeArea())
            .overlay(ScanLines().ignoresSafeArea())
    }
}

/// Neon outlined button with monospace caps.
struct NeonButtonStyle: ButtonStyle {
    var color: Color = Theme.neon
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.mono(.headline, weight: .bold))
            .textCase(.uppercase)
            .foregroundStyle(filled ? Color.black : color)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity)
            .background(filled ? color : Color.black.opacity(0.35))
            .overlay(Rectangle().stroke(color, lineWidth: 2))
            .crtGlow(color, radius: configuration.isPressed ? 12 : 6)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// Small round icon button for toolbars.
struct IconButtonStyle: ButtonStyle {
    var active = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(active ? Color.black : Theme.neon)
            .frame(width: 44, height: 44)
            .background(Circle().fill(active ? Theme.neon : Color.black.opacity(0.55)))
            .overlay(Circle().stroke(Theme.neon.opacity(0.8), lineWidth: 1.5))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Red rubber "CLASSIFIED" stamp.
struct Stamp: View {
    var text = "CLASSIFIED"
    var color: Color = Theme.alert

    var body: some View {
        Text(text)
            .font(Theme.mono(.title3, weight: .heavy))
            .tracking(3)
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(-8))
            .crtGlow(color, radius: 3)
            .accessibilityLabel(text)
    }
}

/// Section header: "> SCANNER READINGS"
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text("> \(title)")
            .font(Theme.mono(.subheadline, weight: .bold))
            .foregroundStyle(Theme.neon)
            .crtGlow(radius: 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
