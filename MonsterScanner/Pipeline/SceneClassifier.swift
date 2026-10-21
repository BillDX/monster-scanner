import CoreGraphics
import Foundation
import MonsterCore
import Vision

/// Classic Mode accessories and setting from Apple's built-in on-device image
/// classifier. Only the labels below are ever looked at; everything else the
/// classifier says is ignored (no people or body labels).
nonisolated enum SceneClassifier {
    struct Result: Sendable, Equatable {
        var accessories: [Accessory] = []
        var backgroundHint = "unknown"
    }

    static let accessoryLabels: [String: Accessory] = [
        "eyeglasses": .glasses,
        "sunglasses": .sunglasses,
        "goggles": .sunglasses,
        "hat": .hat, "baseball_hat": .hat, "cowboy_hat": .hat, "sunhat": .hat, "hardhat": .hat,
        "hoodie": .hood,
        "headphones": .headphones,
        "scarf": .scarf,
    ]

    /// Classifier label → background hint. Hints use words `Setting` knows.
    static let settingLabels: [String: String] = [
        "beach": "beach", "forest": "forest", "park": "park", "garden": "garden", "grass": "grass field",
        "mountain": "mountains", "snow": "snow", "street": "street", "cityscape": "cityscape",
        "night_sky": "night sky", "sky": "open sky", "blue_sky": "open sky", "skatepark": "skatepark",
        "amusement_park": "amusement park", "parking_lot": "parking lot", "outdoor": "outdoors",
        "living_room": "living room", "bedroom": "bedroom", "kitchen": "kitchen", "kitchen_room": "kitchen",
        "bathroom": "bathroom", "dining_room": "dining room", "classroom": "classroom", "office_supplies": "office",
        "restaurant": "restaurant", "bar": "bar", "nightclub": "nightclub", "interior_shop": "shop",
        "interior_room": "interior room", "concert": "concert",
    ]

    static let accessoryThreshold: Float = 0.35
    static let settingThreshold: Float = 0.25

    static func classify(_ image: CGImage) -> Result {
        let request = VNClassifyImageRequest()
        FaceAnalyzer.useCPUInSimulator(request)
        do {
            try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        } catch {
            DebugLog.shared.record("Scene classification failed: \(error.localizedDescription)")
            return Result()
        }
        let observations = request.results ?? []
        var result = Result()

        var accessories: [Accessory] = []
        for observation in observations where observation.confidence >= accessoryThreshold {
            if let accessory = accessoryLabels[observation.identifier], !accessories.contains(accessory) {
                accessories.append(accessory)
            }
        }
        // Sunglasses also score as eyeglasses; keep just one.
        if accessories.contains(.sunglasses) { accessories.removeAll { $0 == .glasses } }
        result.accessories = Array(accessories.prefix(3))

        if let best = observations
            .filter({ $0.confidence >= settingThreshold && settingLabels[$0.identifier] != nil })
            .max(by: { $0.confidence < $1.confidence }) {
            result.backgroundHint = settingLabels[best.identifier] ?? "unknown"
        }
        return result
    }
}
