import Foundation

/// Deterministic numbers measured by code (spec section 4). These come from
/// Vision geometry, pixel statistics, the clock, the moon and the battery —
/// never from the model.
public struct Measurements: Codable, Sendable, Equatable {
    /// Number of faces Vision found. The scan uses the largest one.
    public var faceCount: Int
    /// Largest face box area ÷ frame area, 0...1. `nil` when there is no face.
    public var faceAreaFraction: Double?
    /// How far the face centre is from the frame centre, as a fraction of the
    /// frame (max of x and y offsets). 0 = dead centre.
    public var faceCenterOffset: Double?
    /// Head roll from Vision, degrees. Positive or negative.
    public var headRollDegrees: Double?
    /// Head yaw from Vision, degrees.
    public var headYawDegrees: Double?
    /// Mean luminance of the frame, 0...1.
    public var brightness: Double
    /// Variance of the Laplacian on the downscaled grey image. Low = blurry.
    public var blurVariance: Double
    /// Moon illumination at photo time, 0...1.
    public var moonIllumination: Double
    /// Local time of the photo, minutes after midnight (0..<1440).
    public var minutesSinceMidnight: Int
    /// Battery level 0...1, or `nil` when unknown (e.g. Simulator).
    public var batteryLevel: Double?
    /// Classic Mode shirt hue in degrees, when the shirt region was sampled.
    public var shirtHueDegrees: Double?

    public init(
        faceCount: Int = 1,
        faceAreaFraction: Double? = 0.12,
        faceCenterOffset: Double? = 0.15,
        headRollDegrees: Double? = 5,
        headYawDegrees: Double? = 0,
        brightness: Double = 0.5,
        blurVariance: Double = 400,
        moonIllumination: Double = 0.5,
        minutesSinceMidnight: Int = 14 * 60,
        batteryLevel: Double? = 0.8,
        shirtHueDegrees: Double? = nil
    ) {
        self.faceCount = faceCount
        self.faceAreaFraction = faceAreaFraction
        self.faceCenterOffset = faceCenterOffset
        self.headRollDegrees = headRollDegrees
        self.headYawDegrees = headYawDegrees
        self.brightness = brightness
        self.blurVariance = blurVariance
        self.moonIllumination = moonIllumination
        self.minutesSinceMidnight = minutesSinceMidnight
        self.batteryLevel = batteryLevel
        self.shirtHueDegrees = shirtHueDegrees
    }

    public var hour: Int { minutesSinceMidnight / 60 }

    /// "23:41"
    public var clockText: String {
        String(format: "%02d:%02d", minutesSinceMidnight / 60, minutesSinceMidnight % 60)
    }

    public var headTilt: Double? { headRollDegrees.map(abs) }

    /// Blur thresholds for a ≤512 px image. Tune on device (see DECISIONS.md).
    public static let blurryBelow: Double = 60
    public static let sharpAbove: Double = 900

    public var isBlurry: Bool { blurVariance < Self.blurryBelow }
    public var isRazorSharp: Bool { blurVariance > Self.sharpAbove }
}

/// Everything the verdict engine looks at.
public struct ScanEvidence: Codable, Sendable, Equatable {
    public var measurements: Measurements
    public var observations: SubjectObservations

    public init(measurements: Measurements, observations: SubjectObservations) {
        self.measurements = measurements
        self.observations = observations
    }
}

extension Measurements {
    /// Minutes since local midnight for a date in a time zone.
    public static func minutesSinceMidnight(of date: Date, in timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}
