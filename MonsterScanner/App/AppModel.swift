import MonsterCore
import Observation
import SwiftUI
import UIKit

/// Top-level app state: which screen is showing, settings, and the current scan.
@Observable
final class AppModel {
    enum Screen: Equatable {
        case boot, consent, scanner, scanning, noSubject, reveal
    }

    enum Keys {
        static let consent = "consent.v1"
        static let voice = "settings.voice"
        static let haptics = "settings.haptics"
    }

    var screen: Screen = .boot
    var hasConsented: Bool { didSet { defaults.set(hasConsented, forKey: Keys.consent) } }
    var voiceEnabled: Bool {
        didSet {
            defaults.set(voiceEnabled, forKey: Keys.voice)
            if !voiceEnabled { narrator.stop() }
        }
    }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) } }
    /// A one-off message shown as an alert.
    var alertMessage: String?

    private(set) var session: ScanSession?

    let haptics = Haptics()
    let narrator = Narrator()
    let models = ModelService()

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hasConsented = defaults.bool(forKey: Keys.consent)
        voiceEnabled = defaults.object(forKey: Keys.voice) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
    }


    // MARK: Flow

    func finishBoot() {
        guard screen == .boot else { return }
        screen = hasConsented ? .scanner : .consent
    }

    func acceptConsent() {
        hasConsented = true
        if screen == .consent { screen = .scanner }
    }

    func startScan(data: Data, source: PreparedPhoto.Source) {
        narrator.stop()
        let input = ClassicScanner.Input(
            data: data, source: source, batteryLevel: Self.batteryLevel(), now: .now
        )
        let session = ScanSession(input: input, observer: models.observerForScan, tooHot: ModelService.isTooHot)
        self.session = session
        screen = .scanning
        Task { await run(session, secondOpinion: false) }
    }

    func secondOpinion() {
        guard let session, session.verdict != nil else { return }
        narrator.stop()
        screen = .scanning
        Task { await run(session, secondOpinion: true) }
    }

    /// From the "no subject" screen: accept the Ghost verdict.
    func declareGhost() {
        guard let session else { return }
        session.declareInvisible()
        screen = .reveal
    }

    /// Drops the photo and result from memory and returns to the scanner.
    func scanAgain() {
        narrator.stop()
        haptics.stopHeartbeat()
        session = nil
        screen = .scanner
    }

    private func run(_ session: ScanSession, secondOpinion: Bool) async {
        if hapticsEnabled { haptics.startHeartbeat(seconds: secondOpinion ? 3.5 : 7) }
        if secondOpinion {
            await session.runSecondOpinion()
        } else {
            await session.run()
        }
        haptics.stopHeartbeat()
        // The player may have left while we were scanning.
        guard self.session === session, screen == .scanning else { return }
        switch session.phase {
        case .revealed:
            screen = .reveal
        case .noSubject:
            screen = .noSubject
        case .failed:
            alertMessage = "The scanner jammed on that photo. Try another one."
            self.session = nil
            screen = .scanner
        case .scanning:
            break
        }
    }

    #if DEBUG
    /// Debug builds only: `-MSDebugScan <path>` skips boot and consent (without
    /// saving consent) and scans that image file as a library import. Used to
    /// test the pipeline in the Simulator, which has no camera.
    func applyDebugLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        #if canImport(llama)
        if args.contains("-MSRunBenchmark") {
            Task { _ = await ModelBenchmark.runWithService(models) { _ in } }
            return
        }
        #endif
        guard let flag = args.firstIndex(of: "-MSDebugScan"), flag + 1 < args.count else { return }
        let path = args[flag + 1]
        guard let data = FileManager.default.contents(atPath: path) else {
            DebugLog.shared.record("Debug scan: can't read \(path)")
            return
        }
        startScan(data: data, source: .library)
    }
    #endif

    static func batteryLevel() -> Double? {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        return level < 0 ? nil : Double(level)
    }
}
