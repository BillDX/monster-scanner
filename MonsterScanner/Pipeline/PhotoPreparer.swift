import CoreGraphics
import Foundation
import ImageIO
import MonsterCore

/// A photo ready for analysis. Lives in memory only; nothing here is written
/// to disk (spec section 5).
nonisolated struct PreparedPhoto: @unchecked Sendable {
    enum Source: Sendable { case camera, library }

    /// ≤ 512 px long edge, upright, no metadata. Pixel stats and the seed use this.
    let analysisImage: CGImage
    let pixels: PixelImage
    /// ≤ 1024 px long edge, upright, no metadata. Vision and the reveal use this.
    let displayImage: CGImage
    /// EXIF capture time for library photos, otherwise the shutter time.
    let capturedAt: Date
    let source: Source
}

/// Downscales, applies orientation, and drops all metadata (EXIF, GPS, maker
/// notes). `CGImage` has no metadata, so anything built from these images is
/// clean; the original `Data` is discarded by the caller.
nonisolated enum PhotoPreparer {
    enum Failure: Error { case unreadable }

    static let analysisMaxPixels = 512
    static let displayMaxPixels = 1024

    static func prepare(data: Data, source: PreparedPhoto.Source, now: Date = .now) throws -> PreparedPhoto {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, options),
              let display = thumbnail(imageSource, maxPixels: displayMaxPixels),
              let analysis = thumbnail(imageSource, maxPixels: analysisMaxPixels),
              let pixels = PixelImage(cgImage: analysis) else {
            throw Failure.unreadable
        }
        let capturedAt = source == .library ? (exifCaptureDate(imageSource) ?? now) : now
        return PreparedPhoto(
            analysisImage: analysis, pixels: pixels, displayImage: display,
            capturedAt: capturedAt, source: source
        )
    }

    /// Upright thumbnail with the EXIF orientation applied.
    static func thumbnail(_ source: CGImageSource, maxPixels: Int) -> CGImage? {
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    /// Reads DateTimeOriginal (+ OffsetTimeOriginal when present). The value is
    /// only used for time of day and moon phase; the rest of the EXIF is ignored.
    static func exifCaptureDate(_ source: CGImageSource) -> Date? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let original = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String {
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ssXXXXX"
            if let date = formatter.date(from: original + offset) { return date }
        }
        // No offset recorded: treat it as local time on this phone.
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter.date(from: original)
    }
}
