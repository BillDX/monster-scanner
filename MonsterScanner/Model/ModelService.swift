import Foundation
import Observation
import UIKit

/// Owns the AI model's lifecycle: install state, download, SHA-256 check,
/// load (prewarm), and unload on memory warnings or backgrounding. The game
/// always works without it (Classic Mode).
@Observable
final class ModelService {
    enum Status: Equatable {
        /// No llama.cpp build for this platform (the iOS Simulator).
        case unsupported
        case notInstalled
        case downloading(Double)
        case verifying
        case loading
        case ready
        /// Installed and verified, but unloaded to save memory.
        case sleeping
        case failed(String)
    }

    enum Keys {
        static let aiEnabled = "settings.ai"
        static let cellular = "settings.cellular"
    }

    let pack = ModelCatalog.current
    private(set) var status: Status
    private(set) var lastLoadSeconds: Double?
    private(set) var lastVerifySeconds: Double?
    var aiEnabled: Bool {
        didSet {
            defaults.set(aiEnabled, forKey: Keys.aiEnabled)
            if !aiEnabled { unload(reason: "AI turned off in Settings") }
        }
    }
    var allowCellular: Bool { didSet { defaults.set(allowCellular, forKey: Keys.cellular) } }

    @ObservationIgnored private(set) var observer: (any ObservationModel)?
    @ObservationIgnored private var downloader: ModelDownloader?
    @ObservationIgnored private var verifiedThisLaunch = false
    @ObservationIgnored private var preparing = false
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        aiEnabled = defaults.object(forKey: Keys.aiEnabled) as? Bool ?? true
        allowCellular = defaults.bool(forKey: Keys.cellular)
        #if canImport(llama)
        status = ModelStore.isInstalled(ModelCatalog.current) ? .sleeping : .notInstalled
        #else
        status = .unsupported
        #endif
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.unload(reason: "memory warning") }
        }
    }

    /// Spec section 6: switch to Classic Mode when the phone is hot.
    static var isTooHot: Bool {
        ProcessInfo.processInfo.thermalState.rawValue >= ProcessInfo.ThermalState.serious.rawValue
    }

    /// The observer to use for a scan right now, or nil for Classic Mode.
    var observerForScan: (any ObservationModel)? {
        guard aiEnabled, status == .ready, !Self.isTooHot else { return nil }
        return observer
    }

    var isInstalled: Bool {
        switch status {
        case .ready, .sleeping, .loading, .verifying: true
        case .failed: ModelStore.isInstalled(pack)
        default: false
        }
    }

    // MARK: Lifecycle

    /// Verify (once per launch) and load the model. Called on the boot
    /// screen and when the app comes back to the foreground.
    func prepare() async {
        #if canImport(llama)
        guard aiEnabled, !preparing, observer == nil else { return }
        guard ModelStore.isInstalled(pack) else {
            if case .downloading = status { return }
            status = .notInstalled
            return
        }
        preparing = true
        defer { preparing = false }
        do {
            if !verifiedThisLaunch {
                status = .verifying
                let start = Date()
                try await ModelStore.verify(pack)
                lastVerifySeconds = Date().timeIntervalSince(start)
                verifiedThisLaunch = true
            }
            status = .loading
            let model = LlamaCppObservationModel(
                displayName: pack.displayName,
                modelPath: try ModelStore.url(for: pack.model, in: pack).path,
                projectorPath: try ModelStore.url(for: pack.projector, in: pack).path
            )
            lastLoadSeconds = try await model.load()
            observer = model
            status = .ready
            DebugLog.shared.record(String(
                format: "Model ready: verify %.1f s, load %.1f s, footprint %@, available %@",
                lastVerifySeconds ?? 0, lastLoadSeconds ?? 0,
                MemoryProbe.megabytes(MemoryProbe.footprintBytes), MemoryProbe.megabytes(MemoryProbe.availableBytes)
            ))
        } catch let error as ModelStore.StoreError {
            DebugLog.shared.record("Model check failed: \(error). Files deleted; download again.")
            try? ModelStore.delete(pack)
            status = .failed("\(error)")
        } catch {
            DebugLog.shared.record("Model load failed: \(error)")
            status = .failed("couldn't load the model")
        }
        #endif
    }

    func unload(reason: String) {
        guard let observer else { return }
        observer.unload()
        self.observer = nil
        status = .sleeping
        DebugLog.shared.record("Model unloaded (\(reason))")
    }

    // MARK: Download

    func download() {
        guard downloader == nil else { return }
        let downloader = ModelDownloader(allowCellular: allowCellular)
        self.downloader = downloader
        status = .downloading(0)
        let pack = self.pack
        Task {
            do {
                try await downloader.download(pack) { progress in
                    Task { @MainActor in
                        if case .downloading = self.status { self.status = .downloading(progress.fraction) }
                    }
                }
                self.downloader = nil
                verifiedThisLaunch = true // every file was hash-checked as it landed
                status = .sleeping
                DebugLog.shared.record("Model downloaded and verified")
                await prepare()
            } catch {
                self.downloader = nil
                if case ModelDownloader.DownloadError.cancelled = error {
                    status = .notInstalled
                } else {
                    DebugLog.shared.record("Model download failed: \(error)")
                    status = .failed("download failed: \(error)")
                }
            }
        }
    }

    func cancelDownload() {
        downloader?.cancel()
    }

    func deleteModel() {
        unload(reason: "deleted")
        try? ModelStore.delete(pack)
        verifiedThisLaunch = false
        #if canImport(llama)
        status = .notInstalled
        #endif
    }

    // MARK: Text for the boot screen and Settings

    var bootLine: String {
        switch status {
        case .unsupported: "AI MODEL: NOT AVAILABLE IN SIMULATOR"
        case .notInstalled: "AI MODEL: DOWNLOAD REQUIRED (\(pack.sizeText), WI-FI RECOMMENDED)"
        case .downloading(let f): "AI MODEL: DOWNLOADING \(Int(f * 100))%"
        case .verifying: "AI MODEL: CHECKING SEALS (SHA-256)…"
        case .loading: "AI MODEL: WARMING UP \(pack.displayName)…"
        case .ready: "AI MODEL: \(pack.displayName) READY"
        case .sleeping: "AI MODEL: \(pack.displayName) ASLEEP"
        case .failed: "AI MODEL: OFFLINE (SEE DEBUG LOG)"
        }
    }

    var modeLine: String {
        if Self.isTooHot { return "MODE: CLASSIC (scanner overheating — backup crystals)" }
        if !aiEnabled { return "MODE: CLASSIC (backup crystals)" }
        return status == .ready || status == .loading || status == .verifying || status == .sleeping
            ? "MODE: AI OBSERVER" : "MODE: CLASSIC (backup crystals)"
    }
}
