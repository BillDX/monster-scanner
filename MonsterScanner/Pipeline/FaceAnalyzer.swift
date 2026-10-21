import CoreGraphics
import CoreImage
import CoreML
import Foundation
import MonsterCore
import Vision

/// One face found by Vision. Geometry only: no identity, no embeddings, and
/// nothing is stored (spec section 10).
nonisolated struct DetectedFace: Sendable, Equatable {
    /// Normalised box, origin top-left.
    let box: UnitRect
    let rollDegrees: Double?
    let yawDegrees: Double?
    /// Inner-lip height ÷ width. High = mouth open.
    let mouthOpenRatio: Double?
    /// Mean eye height ÷ width. Low = eyes closed.
    let eyeOpenRatio: Double?
    var isSmiling = false
    var eyesClosed = false
}

nonisolated enum FaceAnalyzer {
    /// Faces in an upright image, largest first.
    static func detectFaces(in image: CGImage) -> [DetectedFace] {
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        let rectangles = VNDetectFaceRectanglesRequest()
        useCPUInSimulator(rectangles)
        do {
            try handler.perform([rectangles])
        } catch {
            DebugLog.shared.record("Face detection failed: \(error.localizedDescription)")
            return []
        }
        let found = rectangles.results ?? []
        guard !found.isEmpty else { return [] }

        let landmarks = VNDetectFaceLandmarksRequest()
        landmarks.inputFaceObservations = found
        useCPUInSimulator(landmarks)
        try? handler.perform([landmarks])
        let detailed = landmarks.results ?? []

        var faces = found.map { observation -> DetectedFace in
            let match = detailed.first { $0.uuid == observation.uuid }
                ?? detailed.max { overlap($0.boundingBox, observation.boundingBox) < overlap($1.boundingBox, observation.boundingBox) }
            return DetectedFace(
                box: topLeft(observation.boundingBox),
                rollDegrees: observation.roll.map { $0.doubleValue * 180 / .pi },
                yawDegrees: observation.yaw.map { $0.doubleValue * 180 / .pi },
                mouthOpenRatio: aspect(match?.landmarks?.innerLips),
                eyeOpenRatio: eyeAspect(match?.landmarks)
            )
        }
        faces.sort { $0.box.area > $1.box.area }
        applySmileAndBlink(to: &faces, image: image)
        return faces
    }

    /// Core Image's detector still offers smile and blink flags, which Vision lacks.
    private static func applySmileAndBlink(to faces: inout [DetectedFace], image: CGImage) {
        guard !faces.isEmpty,
              let detector = CIDetector(
                  ofType: CIDetectorTypeFace, context: nil,
                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
              ) else { return }
        let features = detector.features(
            in: CIImage(cgImage: image),
            options: [CIDetectorSmile: true, CIDetectorEyeBlink: true]
        ).compactMap { $0 as? CIFaceFeature }
        let width = Double(image.width), height = Double(image.height)
        for index in faces.indices {
            let box = faces[index].box
            // CI uses pixel coordinates with a bottom-left origin.
            let target = CGRect(
                x: box.x * width, y: (1 - box.maxY) * height,
                width: box.width * width, height: box.height * height
            )
            guard let best = features.max(by: { overlap($0.bounds, target) < overlap($1.bounds, target) }),
                  overlap(best.bounds, target) > 0.2 else { continue }
            faces[index].isSmiling = best.hasSmile
            faces[index].eyesClosed = best.leftEyeClosed && best.rightEyeClosed
        }
    }

    // MARK: - Geometry helpers

    static func topLeft(_ box: CGRect) -> UnitRect {
        UnitRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
    }

    /// Intersection over union.
    static func overlap(_ a: CGRect, _ b: CGRect) -> Double {
        let i = a.intersection(b)
        guard !i.isNull, i.width > 0, i.height > 0 else { return 0 }
        let inter = i.width * i.height
        return inter / (a.width * a.height + b.width * b.height - inter)
    }

    private static func aspect(_ region: VNFaceLandmarkRegion2D?) -> Double? {
        guard let points = region?.normalizedPoints, points.count >= 3 else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let w = (xs.max() ?? 0) - (xs.min() ?? 0)
        let h = (ys.max() ?? 0) - (ys.min() ?? 0)
        return w > 0 ? Double(h / w) : nil
    }

    private static func eyeAspect(_ landmarks: VNFaceLandmarks2D?) -> Double? {
        let ratios = [aspect(landmarks?.leftEye), aspect(landmarks?.rightEye)].compactMap { $0 }
        return ratios.isEmpty ? nil : ratios.reduce(0, +) / Double(ratios.count)
    }

    /// The Simulator has no Neural Engine; some Vision requests fail there
    /// unless pinned to the CPU.
    static func useCPUInSimulator(_ request: VNRequest) {
        #if targetEnvironment(simulator)
        if let cpu = MLComputeDevice.allComputeDevices.first(where: {
            if case .cpu = $0 { return true } else { return false }
        }) {
            request.setComputeDevice(cpu, for: .main)
        }
        #endif
    }
}
