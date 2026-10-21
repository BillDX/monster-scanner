import CoreGraphics
import Foundation

/// Image helpers for the model input. No llama dependency (shared with the
/// Mac probe via symlink).
nonisolated enum ImageBytes {
    /// Scales `image` so its long edge is at most `maxPixels` and returns
    /// tightly packed RGB bytes (3 per pixel), sRGB, no alpha, no metadata.
    static func rgb(from image: CGImage, maxPixels: Int = 512) -> (width: Int, height: Int, bytes: [UInt8])? {
        let scale = min(1, Double(maxPixels) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = rgba.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for p in 0..<(width * height) {
            rgb[p * 3] = rgba[p * 4]
            rgb[p * 3 + 1] = rgba[p * 4 + 1]
            rgb[p * 3 + 2] = rgba[p * 4 + 2]
        }
        return (width, height, rgb)
    }

    /// Crops `image` to a normalised rect (origin top-left), clamped to the frame.
    static func crop(_ image: CGImage, x: Double, y: Double, width: Double, height: Double) -> CGImage? {
        let w = Double(image.width), h = Double(image.height)
        let x0 = max(0, min(w, x * w)), y0 = max(0, min(h, y * h))
        let x1 = max(0, min(w, (x + width) * w)), y1 = max(0, min(h, (y + height) * h))
        guard x1 - x0 >= 16, y1 - y0 >= 16 else { return nil }
        return image.cropping(to: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0).integral)
    }
}
