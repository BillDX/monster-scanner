import CoreGraphics
import Foundation

/// A rectangle in normalised image coordinates (0...1), origin top-left.
public struct UnitRect: Sendable, Equatable, Codable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var area: Double { max(0, width) * max(0, height) }

    /// The part of this rect inside the unit square.
    public var clampedToUnit: UnitRect {
        let x0 = min(max(x, 0), 1), y0 = min(max(y, 0), 1)
        let x1 = min(max(maxX, 0), 1), y1 = min(max(maxY, 0), 1)
        return UnitRect(x: x0, y: y0, width: max(0, x1 - x0), height: max(0, y1 - y0))
    }
}

/// An 8-bit RGBA image held in memory. Built from a CGImage that has already
/// been downscaled and had its metadata dropped. Its bytes seed the verdict.
public struct PixelImage: Sendable, Equatable {
    public let width: Int
    public let height: Int
    /// Row-major RGBA, 4 bytes per pixel, premultiplied alpha (opaque photos).
    public let bytes: [UInt8]

    public init(width: Int, height: Int, bytes: [UInt8]) {
        precondition(bytes.count == width * height * 4, "RGBA byte count mismatch")
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// Draws `image` into a fixed sRGB RGBA8 buffer so the bytes are the same
    /// on every device for the same picture.
    public init?(cgImage image: CGImage) {
        let width = image.width, height = image.height
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, bytes: buffer)
    }

    /// Solid colour swatch, for tests and previews.
    public static func solid(_ rgb: RGB, width: Int = 32, height: Int = 32) -> PixelImage {
        let pixel: [UInt8] = [
            UInt8((rgb.r * 255).rounded()), UInt8((rgb.g * 255).rounded()),
            UInt8((rgb.b * 255).rounded()), 255,
        ]
        let bytes = [UInt8]((0..<(width * height)).lazy.flatMap { _ in pixel })
        return PixelImage(width: width, height: height, bytes: bytes)
    }

    /// A copy of the pixels inside `region`, or nil if it is under 3×3 pixels.
    public func cropped(to region: UnitRect) -> PixelImage? {
        let r = region.clampedToUnit
        let x0 = Int(r.x * Double(width)), x1 = Int(r.maxX * Double(width))
        let y0 = Int(r.y * Double(height)), y1 = Int(r.maxY * Double(height))
        guard x1 - x0 >= 3, y1 - y0 >= 3 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity((x1 - x0) * (y1 - y0) * 4)
        for y in y0..<y1 {
            let start = (y * width + x0) * 4
            out.append(contentsOf: bytes[start..<(start + (x1 - x0) * 4)])
        }
        return PixelImage(width: x1 - x0, height: y1 - y0, bytes: out)
    }

    @inline(__always)
    public func pixel(x: Int, y: Int) -> RGB {
        let i = (y * width + x) * 4
        return RGB(r8: bytes[i], g8: bytes[i + 1], b8: bytes[i + 2])
    }

    /// Pixels inside `region`, visiting at most about `maxSamples` of them.
    public func samples(in region: UnitRect, maxSamples: Int = 4_000) -> [RGB] {
        let r = region.clampedToUnit
        let x0 = Int(r.x * Double(width)), x1 = Int(r.maxX * Double(width))
        let y0 = Int(r.y * Double(height)), y1 = Int(r.maxY * Double(height))
        guard x1 > x0, y1 > y0 else { return [] }
        let count = (x1 - x0) * (y1 - y0)
        let step = max(1, Int(Double(count / max(maxSamples, 1)).squareRoot()))
        var out: [RGB] = []
        out.reserveCapacity(min(count, maxSamples * 2))
        for y in stride(from: y0, to: y1, by: step) {
            for x in stride(from: x0, to: x1, by: step) {
                out.append(pixel(x: x, y: y))
            }
        }
        return out
    }

    /// Mean luminance of the whole image, 0...1.
    public var meanLuminance: Double {
        var total = 0.0
        var i = 0
        while i < bytes.count {
            total += 0.2126 * Double(bytes[i]) + 0.7152 * Double(bytes[i + 1]) + 0.0722 * Double(bytes[i + 2])
            i += 4
        }
        return total / Double(width * height) / 255
    }

    /// Variance of the 4-neighbour Laplacian on the grey image (0–255 scale).
    /// A standard sharpness score: low values mean blur.
    public var laplacianVariance: Double {
        guard width >= 3, height >= 3 else { return 0 }
        var grey = [Double](repeating: 0, count: width * height)
        for p in 0..<(width * height) {
            let i = p * 4
            grey[p] = 0.2126 * Double(bytes[i]) + 0.7152 * Double(bytes[i + 1]) + 0.0722 * Double(bytes[i + 2])
        }
        var sum = 0.0, sumSquares = 0.0
        var n = 0.0
        for y in 1..<(height - 1) {
            let row = y * width
            for x in 1..<(width - 1) {
                let c = row + x
                let lap = grey[c - 1] + grey[c + 1] + grey[c - width] + grey[c + width] - 4 * grey[c]
                sum += lap
                sumSquares += lap * lap
                n += 1
            }
        }
        let mean = sum / n
        return sumSquares / n - mean * mean
    }
}

/// Classic Mode colour sampling: the most common colour bucket in a region.
public enum ColorSampler {
    public struct Reading: Sendable, Equatable {
        public var family: ColorFamily
        /// Mean hue of the pixels in the winning bucket (nil for black/white/grey).
        public var hueDegrees: Double?
        /// Share of sampled pixels in the winning bucket, 0...1.
        public var share: Double
    }

    /// Dominant colour family in `region`, or nil if the region is off-frame.
    public static func dominantColor(in image: PixelImage, region: UnitRect) -> Reading? {
        let pixels = image.samples(in: region)
        guard pixels.count >= 16 else { return nil }
        var counts: [ColorFamily: Int] = [:]
        var hueSums: [ColorFamily: (x: Double, y: Double)] = [:]
        for pixel in pixels {
            let family = ColorFamily(rgb: pixel)
            counts[family, default: 0] += 1
            let h = pixel.hsv.h * .pi / 180
            let sum = hueSums[family, default: (0, 0)]
            hueSums[family] = (sum.x + cos(h), sum.y + sin(h))
        }
        // Ties break by the enum order so results are deterministic.
        let winner = ColorFamily.allCases
            .compactMap { family in counts[family].map { (family, $0) } }
            .max { $0.1 < $1.1 }!
        let achromatic: Set<ColorFamily> = [.black, .white, .gray, .silver]
        var hue: Double?
        if !achromatic.contains(winner.0), let s = hueSums[winner.0] {
            var degrees = atan2(s.y, s.x) * 180 / .pi
            if degrees < 0 { degrees += 360 }
            hue = degrees
        }
        return Reading(family: winner.0, hueDegrees: hue, share: Double(winner.1) / Double(pixels.count))
    }

    /// Most common hair bucket in `region`, or nil if off-frame.
    public static func dominantHair(in image: PixelImage, region: UnitRect) -> HairColor? {
        let pixels = image.samples(in: region)
        guard pixels.count >= 16 else { return nil }
        var counts: [HairColor: Int] = [:]
        for pixel in pixels { counts[HairColor(rgb: pixel), default: 0] += 1 }
        return HairColor.allCases
            .compactMap { hair in counts[hair].map { (hair, $0) } }
            .max { $0.1 < $1.1 }?.0
    }
}
