import SwiftUI

/// Retro "classified government scanner" look: dark CRT, neon green, red stamps.
enum Theme {
    static let background = Color(red: 0.02, green: 0.04, blue: 0.03)
    static let neon = Color(red: 0.22, green: 1.0, blue: 0.42)
    static let dimNeon = neon.opacity(0.55)
    static let alert = Color(red: 1.0, green: 0.18, blue: 0.22)

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
