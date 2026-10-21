import CoreGraphics
import Testing
@testable import MonsterCore

@Suite("Colour sampling (Classic Mode)")
struct ColorSamplerTests {
    /// Draws a solid swatch with Core Graphics, then reads it back through the
    /// same path the app uses (CGImage → PixelImage → sampler).
    static func swatch(_ rgb: RGB, size: Int = 64) -> PixelImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(colorSpace: space, components: [rgb.r, rgb.g, rgb.b, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        return PixelImage(cgImage: context.makeImage()!)!
    }

    static let whole = UnitRect(x: 0, y: 0, width: 1, height: 1)

    static let shirtSwatches: [(String, RGB, ColorFamily)] = [
        ("red", RGB(r: 0.9, g: 0.1, b: 0.1), .red),
        ("orange", RGB(r: 1, g: 0.55, b: 0.1), .orange),
        ("yellow", RGB(r: 0.95, g: 0.85, b: 0.1), .yellow),
        ("forest green", RGB(r: 0.1, g: 0.5, b: 0.2), .green),
        ("navy", RGB(r: 0.1, g: 0.15, b: 0.5), .blue),
        ("purple", RGB(r: 0.5, g: 0.2, b: 0.7), .purple),
        ("pink", RGB(r: 1, g: 0.4, b: 0.7), .pink),
        ("brown", RGB(r: 0.45, g: 0.28, b: 0.12), .brown),
        ("beige", RGB(r: 0.9, g: 0.82, b: 0.68), .beige),
        ("black", RGB(r: 0.05, g: 0.05, b: 0.08), .black),
        ("white", RGB(r: 0.95, g: 0.95, b: 0.95), .white),
        ("grey", RGB(r: 0.5, g: 0.5, b: 0.5), .gray),
    ]

    @Test("Solid shirt swatches classify correctly", arguments: shirtSwatches)
    func shirtSwatch(_ name: String, _ rgb: RGB, _ expected: ColorFamily) throws {
        let reading = try #require(ColorSampler.dominantColor(in: Self.swatch(rgb), region: Self.whole))
        #expect(reading.family == expected, "\(name) read as \(reading.family)")
        #expect(reading.share > 0.99)
    }

    @Test("Hue is reported for chromatic colours")
    func hue() throws {
        let navy = try #require(ColorSampler.dominantColor(in: Self.swatch(RGB(r: 0.1, g: 0.15, b: 0.5)), region: Self.whole))
        let hue = try #require(navy.hueDegrees)
        #expect(abs(hue - 232.5) < 2)
        let black = try #require(ColorSampler.dominantColor(in: Self.swatch(RGB(r: 0, g: 0, b: 0)), region: Self.whole))
        #expect(black.hueDegrees == nil)
    }

    static let hairSwatches: [(String, RGB, HairColor)] = [
        ("black", RGB(r: 0.08, g: 0.06, b: 0.05), .black),
        ("brown", RGB(r: 0.35, g: 0.22, b: 0.12), .brown),
        ("blonde", RGB(r: 0.85, g: 0.72, b: 0.45), .blonde),
        ("red", RGB(r: 0.65, g: 0.25, b: 0.12), .red),
        ("gray", RGB(r: 0.6, g: 0.6, b: 0.6), .gray),
        ("white", RGB(r: 0.9, g: 0.9, b: 0.88), .white),
        ("dyed blue", RGB(r: 0.2, g: 0.4, b: 0.9), .dyedOther),
    ]

    @Test("Solid hair swatches classify correctly", arguments: hairSwatches)
    func hairSwatch(_ name: String, _ rgb: RGB, _ expected: HairColor) {
        #expect(ColorSampler.dominantHair(in: Self.swatch(rgb), region: Self.whole) == expected)
    }

    @Test("The dominant colour wins in a two-colour image")
    func dominant() throws {
        // Top 25% red, bottom 75% blue.
        let size = 64
        var bytes: [UInt8] = []
        for y in 0..<size {
            for _ in 0..<size {
                bytes += y < size / 4 ? [230, 25, 25, 255] : [25, 40, 200, 255]
            }
        }
        let image = PixelImage(width: size, height: size, bytes: bytes)
        #expect(ColorSampler.dominantColor(in: image, region: Self.whole)?.family == .blue)
        let top = UnitRect(x: 0, y: 0, width: 1, height: 0.2)
        #expect(ColorSampler.dominantColor(in: image, region: top)?.family == .red)
    }

    @Test("Cropping keeps the right pixels")
    func crop() throws {
        let size = 64
        var bytes: [UInt8] = []
        for y in 0..<size { for _ in 0..<size { bytes += y < size / 2 ? [230, 25, 25, 255] : [25, 40, 200, 255] } }
        let image = PixelImage(width: size, height: size, bytes: bytes)
        let bottom = try #require(image.cropped(to: UnitRect(x: 0.25, y: 0.5, width: 0.5, height: 0.5)))
        #expect(bottom.width == 32 && bottom.height == 32)
        #expect(ColorSampler.dominantColor(in: bottom, region: Self.whole)?.family == .blue)
        #expect(image.cropped(to: UnitRect(x: 2, y: 2, width: 1, height: 1)) == nil)
    }

    @Test("Off-frame regions return nothing")
    func offFrame() {
        let image = Self.swatch(RGB(r: 0.5, g: 0.5, b: 0.5))
        #expect(ColorSampler.dominantColor(in: image, region: UnitRect(x: 0, y: 1.1, width: 1, height: 0.3)) == nil)
        #expect(ColorSampler.dominantHair(in: image, region: UnitRect(x: -0.5, y: -0.5, width: 0.4, height: 0.4)) == nil)
    }

    @Test("Brightness and blur measurements")
    func brightnessAndBlur() {
        let grey = Self.swatch(RGB(r: 0.5, g: 0.5, b: 0.5))
        #expect(abs(grey.meanLuminance - 0.5) < 0.01)
        #expect(grey.laplacianVariance < 1)

        // A 1-pixel checkerboard is as sharp as it gets.
        let size = 32
        var bytes: [UInt8] = []
        for y in 0..<size {
            for x in 0..<size {
                let v: UInt8 = (x + y).isMultiple(of: 2) ? 255 : 0
                bytes += [v, v, v, 255]
            }
        }
        let checker = PixelImage(width: size, height: size, bytes: bytes)
        #expect(checker.laplacianVariance > Measurements.sharpAbove)
    }

    @Test("Free-text colour names map to families")
    func colourNames() {
        #expect(ColorFamily(name: "navy blue") == .blue)
        #expect(ColorFamily(name: "olive green") == .green)
        #expect(ColorFamily(name: "Charcoal") == .gray)
        #expect(ColorFamily(name: "Dark Grey") == .gray)
        #expect(ColorFamily(name: "light blue") == .blue)
        #expect(ColorFamily(name: "blue-green") == .green)
        #expect(ColorFamily(name: "maroon") == .red)
        #expect(ColorFamily(name: "silver") == .silver)
        #expect(ColorFamily(name: "sparkly nonsense") == .unknown)
        #expect(ColorFamily(name: "") == .unknown)
    }

    @Test("Background hints map to a setting")
    func settings() {
        #expect(Setting(hint: "city park at night") == .outdoors)
        #expect(Setting(hint: "Kitchen") == .indoors)
        #expect(Setting(hint: "unknown") == .unknown)
        #expect(Setting(hint: "cityscape") == .outdoors)
        #expect(Setting(hint: "interior room") == .indoors)
    }
}
