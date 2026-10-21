import CoreGraphics
import Foundation
import MonsterCore

/// Everything measured about one photo.
nonisolated struct ScanAnalysis: @unchecked Sendable {
    let photo: PreparedPhoto
    /// Largest first.
    let faces: [DetectedFace]
    let evidence: ScanEvidence
    let moonName: String

    var subject: DetectedFace? { faces.first }

    /// Seed for the verdict: SHA-256 of the analysis pixels + calibration.
    func seed(calibration: Int) -> UInt64 {
        SeededRandom.seed(imageBytes: photo.pixels.bytes, calibration: calibration)
    }
}

/// Classic Mode: code measurements + Vision + pixel sampling. No model.
nonisolated enum ClassicScanner {
    struct Input: Sendable {
        let data: Data
        let source: PreparedPhoto.Source
        let batteryLevel: Double?
        let now: Date
    }

    /// Runs off the main actor.
    @concurrent
    static func analyze(_ input: Input) async throws -> ScanAnalysis {
        let photo = try PhotoPreparer.prepare(data: input.data, source: input.source, now: input.now)
        let faces = FaceAnalyzer.detectFaces(in: photo.displayImage)
        let scene = SceneClassifier.classify(photo.displayImage)
        let evidence = measure(photo: photo, faces: faces, scene: scene, batteryLevel: input.batteryLevel)
        return ScanAnalysis(
            photo: photo, faces: faces, evidence: evidence,
            moonName: MoonPhase.name(at: photo.capturedAt)
        )
    }

    static func measure(
        photo: PreparedPhoto, faces: [DetectedFace], scene: SceneClassifier.Result, batteryLevel: Double?
    ) -> ScanEvidence {
        let pixels = photo.pixels
        let subject = faces.first

        // Blur is measured on the subject (with some margin), so a blurred
        // portrait-mode background doesn't make everyone a ghost.
        var blurRegion = UnitRect(x: 0, y: 0, width: 1, height: 1)
        if let box = subject?.box {
            blurRegion = UnitRect(x: box.x - box.width * 0.15, y: box.y - box.height * 0.15,
                                  width: box.width * 1.3, height: box.height * 1.3)
        }
        let blur = (pixels.cropped(to: blurRegion) ?? pixels).laplacianVariance

        var measurements = Measurements(
            faceCount: faces.count,
            faceAreaFraction: subject?.box.area,
            faceCenterOffset: subject.map { max(abs($0.box.midX - 0.5), abs($0.box.midY - 0.5)) },
            headRollDegrees: subject?.rollDegrees,
            headYawDegrees: subject?.yawDegrees,
            brightness: pixels.meanLuminance,
            blurVariance: blur,
            moonIllumination: MoonPhase.illumination(at: photo.capturedAt),
            minutesSinceMidnight: Measurements.minutesSinceMidnight(of: photo.capturedAt),
            batteryLevel: batteryLevel,
            shirtHueDegrees: nil
        )

        var observations = SubjectObservations(
            accessories: scene.accessories,
            backgroundHint: scene.backgroundHint
        )

        if let face = subject {
            let box = face.box
            let headwear = !Set(scene.accessories).isDisjoint(with: [.hat, .hood])

            // Hair: a band just above the face box.
            let hairRegion = UnitRect(x: box.x + box.width * 0.15, y: box.y - box.height * 0.3,
                                      width: box.width * 0.7, height: box.height * 0.25)
            if headwear {
                observations.hairColor = .hidden
            } else if let hair = ColorSampler.dominantHair(in: pixels, region: hairRegion) {
                observations.hairColor = hair
            }

            // Shirt: below the chin, about one face-width either side.
            let shirtRegion = UnitRect(x: box.midX - box.width * 0.6, y: box.maxY + box.height * 0.45,
                                       width: box.width * 1.2, height: box.height * 0.9)
            if let shirt = ColorSampler.dominantColor(in: pixels, region: shirtRegion), shirt.share > 0.3 {
                observations.shirtColor = shirt.family.rawValue
                measurements.shirtHueDegrees = shirt.hueDegrees
            }

            observations.expression = expression(for: face)
        }

        return ScanEvidence(measurements: measurements, observations: observations)
    }

    /// Classic Mode can tell smiling, sleepy, surprised and serious apart.
    /// "silly-face" needs the model.
    static func expression(for face: DetectedFace) -> FaceExpression {
        if face.isSmiling { return .smiling }
        if face.eyesClosed || (face.eyeOpenRatio ?? 1) < 0.12 { return .sleepy }
        if (face.mouthOpenRatio ?? 0) > 0.35 { return .surprised }
        return .serious
    }
}
