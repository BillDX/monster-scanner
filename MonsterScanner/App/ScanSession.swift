import CoreGraphics
import MonsterCore
import Observation
import UIKit

/// One scan: the photo, the measurements, the observations, the verdict and
/// the dossier. Everything lives in memory and disappears when the session
/// is dropped.
@Observable
final class ScanSession {
    enum Phase: Equatable { case scanning, revealed, noSubject, failed }

    /// Who produced the observations used for the verdict.
    enum ObservationSource: Equatable {
        case classic
        case model(String)
    }

    static let minimumScan: Duration = .seconds(5.5)
    /// Shutter to reveal must stay under 12 s (spec section 1).
    static let maximumScan: Duration = .seconds(11)
    /// Past this point a still-running model call is abandoned for Classic.
    static let modelDeadline: Duration = .seconds(10.3)
    static let lineInterval: Duration = .milliseconds(330)

    private(set) var phase: Phase = .scanning
    private(set) var lines: [String] = []
    private(set) var gauge: Double = 0
    private(set) var analysis: ScanAnalysis?
    /// Measurements + the observations actually used (model or classic).
    private(set) var evidence: ScanEvidence?
    private(set) var verdict: Verdict?
    private(set) var dossier: Dossier?
    private(set) var calibration = 0
    private(set) var displayImage: UIImage?
    private(set) var isInvisibleVerdict = false
    private(set) var observationSource: ObservationSource = .classic
    private(set) var modelRun: ObservationRun?

    @ObservationIgnored private var input: ClassicScanner.Input?
    @ObservationIgnored private let observer: (any ObservationModel)?
    @ObservationIgnored private let tooHot: Bool
    @ObservationIgnored private var queue: [String] = []
    @ObservationIgnored private var gaugeTarget: Double = 64
    @ObservationIgnored private var analysisFinished = false
    @ObservationIgnored private var modelSettled = true
    @ObservationIgnored private var modelTask: Task<Void, Never>?

    init(input: ClassicScanner.Input, observer: (any ObservationModel)?, tooHot: Bool) {
        self.input = input
        self.observer = observer
        self.tooHot = tooHot
    }

    var observations: SubjectObservations { evidence?.observations ?? .unknown }

    var finalGauge: Double {
        guard let verdict else { return 0 }
        return verdict.monster == .human ? 100 - verdict.confidence : verdict.confidence
    }

    /// The dossier plus the AI's make-believe "field note", typed and read aloud.
    var narrationText: String? {
        guard let dossier else { return nil }
        guard !isInvisibleVerdict, let vibe = observations.vibe, !vibe.isEmpty else { return dossier.fullText }
        let note = vibe.prefix(1).uppercased() + vibe.dropFirst()
        let ending = note.hasSuffix(".") || note.hasSuffix("!") ? "" : "."
        return dossier.fullText + "\n\nField note: " + note + ending
    }

    var modeLabel: String {
        switch observationSource {
        case .classic: "CLASSIC (BACKUP CRYSTALS)"
        case .model(let name): "AI OBSERVER (\(name))"
        }
    }

    // MARK: Running

    func run() async {
        phase = .scanning
        lines = []
        gauge = 0
        queue = Array(Telemetry.warmUp.prefix(3))
        if tooHot { queue.append("SCANNER OVERHEATING — SWITCHING TO BACKUP CRYSTALS") }
        guard let input else { phase = .failed; return }

        let work = Task { () -> ScanAnalysis? in
            do {
                return try await ClassicScanner.analyze(input)
            } catch {
                DebugLog.shared.record("Analysis failed: \(error)")
                return nil
            }
        }
        let receiver = Task { [weak self] in
            let result = await work.value
            self?.receive(result)
        }
        await tick(until: { [weak self] in
            guard let self else { return true }
            return self.analysisFinished && self.modelSettled
        })
        _ = await receiver.value
    }

    func runSecondOpinion() async {
        guard analysis != nil else { return }
        phase = .scanning
        calibration += 1
        lines = []
        gauge = 10
        queue = ["RECALIBRATING SCANNER…", "CALIBRATION #\(calibration + 1) LOADED", "RE-READING EVIDENCE…"]
        decide()
        gaugeTarget = finalGauge
        if let evidence { queue += Array(Telemetry.measurementLines(for: evidence).shuffled().prefix(4)) }
        await tick(minimum: .seconds(3), until: { true })
        gauge = finalGauge
        phase = .revealed
    }

    func declareInvisible() {
        isInvisibleVerdict = true
        decide()
        gauge = finalGauge
        phase = .revealed
    }

    // MARK: Internals

    private func receive(_ result: ScanAnalysis?) {
        analysisFinished = true
        input = nil // drop the original photo bytes
        guard let result else {
            phase = .failed
            queue = []
            return
        }
        analysis = result
        evidence = result.evidence
        displayImage = UIImage(cgImage: result.photo.displayImage)

        guard let subject = result.subject else {
            queue += ["FACES IN FRAME: 0", "SUBJECT: NOT FOUND", "CHECKING FOR INVISIBILITY…"]
            gaugeTarget = 13
            return
        }

        queue += Telemetry.measurementLines(for: result.evidence, moonName: result.moonName)

        if let observer, !tooHot, let crop = Self.subjectCrop(result.photo.displayImage, face: subject.box) {
            modelSettled = false
            queue.insert("AI OBSERVER ENGAGED: \(observer.displayName)…", at: min(2, queue.count))
            modelTask = Task { [weak self] in
                let run = await observer.observeDetailed(image: crop, timeout: 20)
                self?.receiveModel(run)
            }
        } else {
            finishObservations()
        }
    }

    private func receiveModel(_ run: ObservationRun) {
        guard !modelSettled else { return } // already gave up at the deadline
        modelRun = run
        if let observations = run.observations, var evidence {
            evidence.observations = observations
            // The classic hue reading only stands if the model agrees on the colour.
            if analysis?.evidence.observations.shirtFamily != observations.shirtFamily {
                evidence.measurements.shirtHueDegrees = nil
            }
            self.evidence = evidence
            observationSource = .model(observer?.displayName ?? "AI")
            DebugLog.shared.record(String(
                format: "Model observation: %.1f s, %d attempt(s), %d tokens", run.seconds, run.attempts, run.generatedTokens
            ))
        } else {
            // Spec section 6: fall back silently, log on device only.
            DebugLog.shared.record("Model fallback to Classic: \(run.error ?? "invalid output")")
        }
        finishObservations()
    }

    private func finishObservations() {
        modelSettled = true
        decide()
        gaugeTarget = finalGauge
        guard let evidence else { return }
        let prefix = observationSource == .classic ? "" : "OBSERVER: "
        queue += Telemetry.observationLines(for: evidence, prefix: prefix)
        if let run = modelRun, run.observations != nil {
            queue.append(String(format: "OBSERVER RESPONSE TIME: %.1f S", run.seconds))
        }
        queue.append("CROSS-REFERENCING CRYPTID DATABASE…")
    }

    private func tick(minimum: Duration = ScanSession.minimumScan, until ready: () -> Bool) async {
        let clock = ContinuousClock()
        let start = clock.now
        while !Task.isCancelled {
            if !queue.isEmpty { lines.append(queue.removeFirst()) }
            let step = Double.random(in: 2...9)
            gauge = min(99.9, max(0, gauge + (gauge < gaugeTarget ? step : -step / 2)))

            let elapsed = clock.now - start
            if !modelSettled && elapsed >= Self.modelDeadline {
                modelTask?.cancel()
                DebugLog.shared.record("Model missed the scan deadline; using Classic")
                finishObservations()
            }
            let done = ready() && queue.isEmpty && elapsed >= minimum
            if done || (ready() && elapsed >= Self.maximumScan) { break }
            try? await Task.sleep(for: Self.lineInterval)
        }
        guard phase != .failed else { return }
        if ready() {
            gauge = finalGauge
            if analysis?.subject == nil, !isInvisibleVerdict, analysis != nil {
                phase = .noSubject
            } else if verdict != nil {
                phase = .revealed
            }
        }
    }

    private func decide() {
        guard let analysis else { return }
        let seed = analysis.seed(calibration: calibration)
        let evidence = self.evidence ?? analysis.evidence
        let verdict = isInvisibleVerdict
            ? VerdictEngine.invisibleSubject(seed: seed)
            : VerdictEngine.decide(evidence, seed: seed)
        self.verdict = verdict
        dossier = DossierLibrary.bundled.write(DossierInput(verdict: verdict, observations: evidence.observations))
    }

    // MARK: Helpers

    /// The subject with room for hair above and shirt below, for the model.
    nonisolated static func subjectCrop(_ image: CGImage, face: UnitRect) -> CGImage? {
        ImageBytes.crop(
            image,
            x: face.x - face.width * 0.9, y: face.y - face.height * 0.7,
            width: face.width * 2.8, height: face.height * 3.3
        )
    }
}
