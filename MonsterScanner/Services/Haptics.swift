import CoreHaptics
import Foundation

/// Core Haptics effects: shutter tap, scanning heartbeat, reveal spike.
/// Does nothing on devices without haptics (and in the Simulator).
final class Haptics {
    private var engine: CHHapticEngine?
    private var heartbeat: CHHapticPatternPlayer?

    private var supported: Bool { CHHapticEngine.capabilitiesForHardware().supportsHaptics }

    func prepare() {
        guard supported, engine == nil else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            engine.playsHapticsOnly = true
            engine.resetHandler = { [weak self] in
                Task { @MainActor in try? self?.engine?.start() }
            }
            try engine.start()
            self.engine = engine
        } catch {
            DebugLog.shared.record("Haptics unavailable: \(error.localizedDescription)")
        }
    }

    func tap() {
        play([event(.hapticTransient, at: 0, intensity: 0.6, sharpness: 0.8)])
    }

    /// Lub-dub that grows stronger over `seconds`.
    func startHeartbeat(seconds: Double) {
        stopHeartbeat()
        var events: [CHHapticEvent] = []
        var t = 0.0
        while t < seconds {
            let strength = Float(0.35 + 0.6 * t / seconds)
            events.append(event(.hapticTransient, at: t, intensity: strength, sharpness: 0.25))
            events.append(event(.hapticTransient, at: t + 0.18, intensity: strength * 0.7, sharpness: 0.2))
            t += max(0.45, 0.9 - 0.4 * t / seconds) // speeds up as it builds
        }
        heartbeat = play(events)
    }

    func stopHeartbeat() {
        try? heartbeat?.stop(atTime: CHHapticTimeImmediate)
        heartbeat = nil
    }

    /// The big thump when the verdict lands.
    func revealSpike() {
        play([
            event(.hapticTransient, at: 0, intensity: 1, sharpness: 1),
            CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
                ],
                relativeTime: 0.02, duration: 0.45
            ),
        ])
    }

    // MARK: Helpers

    private func event(_ type: CHHapticEvent.EventType, at time: Double, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: type,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    @discardableResult
    private func play(_ events: [CHHapticEvent]) -> CHHapticPatternPlayer? {
        prepare()
        guard let engine else { return nil }
        do {
            try engine.start()
            let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
            try player.start(atTime: CHHapticTimeImmediate)
            return player
        } catch {
            DebugLog.shared.record("Haptic pattern failed: \(error.localizedDescription)")
            return nil
        }
    }
}
