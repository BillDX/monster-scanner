import CryptoKit
import Foundation

/// Small, fast, deterministic random number generator (SplitMix64).
/// The same seed always produces the same sequence on every device.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A Double in 0..<1.
    public mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    /// Seed = first 8 bytes of SHA-256(image bytes ‖ calibration).
    /// The same photo gives the same verdict until the calibration changes
    /// ("Second Opinion").
    public static func seed(imageBytes: some DataProtocol, calibration: Int) -> UInt64 {
        var hasher = SHA256()
        hasher.update(data: imageBytes)
        withUnsafeBytes(of: Int64(calibration).littleEndian) { hasher.update(bufferPointer: $0) }
        let digest = hasher.finalize()
        return digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
    }
}
