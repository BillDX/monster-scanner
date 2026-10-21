import Foundation

/// A coarse colour bucket used by clues ("black or red shirt" etc.).
public enum ColorFamily: String, Codable, CaseIterable, Sendable {
    case black, white, gray, silver, red, orange, yellow, green, blue, purple, pink, brown, beige
    case unknown

    /// Maps a free-text colour name ("navy blue", "olive", "charcoal") to a family.
    /// The last recognised colour word wins, so "light blue" → blue and
    /// "blue-green" → green.
    public init(name: String) {
        let words = name.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        var found: ColorFamily?
        for word in words {
            if let family = Self.synonyms[word] { found = family }
        }
        self = found ?? .unknown
    }

    private static let synonyms: [String: ColorFamily] = [
        "black": .black, "jet": .black, "ebony": .black, "onyx": .black,
        "white": .white, "ivory": .white, "cream": .white, "snow": .white,
        "gray": .gray, "grey": .gray, "charcoal": .gray, "slate": .gray, "ash": .gray, "graphite": .gray,
        "silver": .silver, "metallic": .silver, "chrome": .silver,
        "red": .red, "crimson": .red, "maroon": .red, "burgundy": .red, "scarlet": .red, "wine": .red, "cherry": .red,
        "orange": .orange, "rust": .orange, "coral": .orange, "peach": .orange, "tangerine": .orange,
        "yellow": .yellow, "gold": .yellow, "golden": .yellow, "mustard": .yellow, "lemon": .yellow,
        "green": .green, "olive": .green, "lime": .green, "mint": .green, "khaki": .green, "emerald": .green,
        "forest": .green, "sage": .green, "teal": .green,
        "blue": .blue, "navy": .blue, "denim": .blue, "cyan": .blue, "turquoise": .blue, "azure": .blue,
        "cobalt": .blue, "indigo": .blue, "sky": .blue,
        "purple": .purple, "violet": .purple, "lavender": .purple, "lilac": .purple, "plum": .purple, "mauve": .purple,
        "pink": .pink, "magenta": .pink, "fuchsia": .pink, "rose": .pink, "salmon": .pink,
        "brown": .brown, "tan": .brown, "chocolate": .brown, "coffee": .brown, "camel": .brown, "mocha": .brown,
        "beige": .beige, "sand": .beige, "taupe": .beige, "nude": .beige, "oatmeal": .beige,
    ]

    /// Classifies one sampled pixel colour.
    public init(rgb: RGB) {
        let hsv = rgb.hsv
        if hsv.v < 0.18 {
            self = .black
        } else if hsv.s < 0.12 && hsv.v > 0.82 {
            self = .white
        } else if hsv.s < 0.15 {
            self = .gray
        } else {
            let h = hsv.h
            if (15..<50).contains(h) && hsv.s < 0.35 && hsv.v > 0.65 {
                self = .beige
            } else if (10..<45).contains(h) && hsv.v < 0.6 {
                self = .brown
            } else if h < 12 || h >= 345 {
                self = .red
            } else if h < 40 {
                self = .orange
            } else if h < 66 {
                self = .yellow
            } else if h < 170 {
                self = .green
            } else if h < 255 {
                self = .blue
            } else if h < 290 {
                self = .purple
            } else {
                self = .pink
            }
        }
    }

    public var displayName: String {
        self == .unknown ? "unknown" : rawValue
    }
}

extension HairColor {
    /// Classic Mode only: classifies a sampled hair pixel. Crude by design;
    /// the result is only shown in the readout (DECISIONS.md S-2).
    public init(rgb: RGB) {
        let hsv = rgb.hsv
        if hsv.v < 0.2 {
            self = .black
        } else if hsv.s < 0.18 {
            self = hsv.v > 0.75 ? .white : .gray
        } else if (65..<330).contains(hsv.h) && hsv.s > 0.35 {
            self = .dyedOther
        } else if (hsv.h < 22 || hsv.h >= 330) && hsv.s > 0.45 {
            self = .red
        } else if hsv.v > 0.62 && hsv.s < 0.65 {
            self = .blonde
        } else {
            self = .brown
        }
    }
}

/// An sRGB colour with components in 0...1.
public struct RGB: Sendable, Equatable, Codable {
    public var r: Double
    public var g: Double
    public var b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(r8: UInt8, g8: UInt8, b8: UInt8) {
        self.init(r: Double(r8) / 255, g: Double(g8) / 255, b: Double(b8) / 255)
    }

    /// Hue in degrees 0..<360, saturation and value in 0...1.
    public var hsv: (h: Double, s: Double, v: Double) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        let v = maxC
        let s = maxC == 0 ? 0 : delta / maxC
        var h: Double = 0
        if delta > 0 {
            if maxC == r {
                h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                h = 60 * ((b - r) / delta + 2)
            } else {
                h = 60 * ((r - g) / delta + 4)
            }
        }
        if h < 0 { h += 360 }
        return (h, s, v)
    }

    /// Rec. 709 relative luminance (on gamma-encoded values; good enough for a toy).
    public var luminance: Double {
        0.2126 * r + 0.7152 * g + 0.0722 * b
    }
}
